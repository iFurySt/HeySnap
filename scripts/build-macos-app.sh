#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="HeySnap"
install_user_app=1
codesign_identity="${HEYSNAP_CODESIGN_IDENTITY:-auto}"
codesign_keychain="${HEYSNAP_CODESIGN_KEYCHAIN:-}"
codesign_timestamp="${HEYSNAP_CODESIGN_TIMESTAMP:-auto}"
codesign_options_runtime="${HEYSNAP_CODESIGN_OPTIONS_RUNTIME:-auto}"
codesign_team_id="${HEYSNAP_CODESIGN_TEAM_ID:-J9P29FA5BX}"
codesign_developer_name="${HEYSNAP_CODESIGN_DEVELOPER_NAME:-Yifan PANG}"
bundle_short_version=""
bundle_version=""
source_dir="${repo_root}/apps/macos/${app_name}/Sources"
core_source_dir="${repo_root}/packages/HeySnapCore/Sources"
resource_dir="${repo_root}/apps/macos/${app_name}/Resources"
build_dir="${repo_root}/.build/macos"
module_cache="${build_dir}/module-cache"
tmp_dir="${build_dir}/tmp"
app_dir="${build_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
frameworks_dir="${contents_dir}/Frameworks"
sparkle_install_dir=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --install-user-app)
      install_user_app=1
      ;;
    --build-only)
      install_user_app=0
      ;;
    --version)
      bundle_short_version="${2:-}"
      if [[ -z "${bundle_short_version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift
      ;;
    --bundle-version)
      bundle_version="${2:-}"
      if [[ -z "${bundle_version}" ]]; then
        echo "--bundle-version requires a value" >&2
        exit 1
      fi
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

find_codesigning_identity() {
  local identity_pattern="$1"

  security find-identity -v -p codesigning \
    | awk -v pattern="$identity_pattern" '$0 ~ pattern && $0 !~ /CSSMERR|REVOKED/ { print $2; exit }' \
    | head -n 1
}

codesigning_identity_name() {
  local signing_identity="$1"

  if [[ "${signing_identity}" == "-" ]]; then
    echo "ad-hoc"
    return
  fi

  security find-identity -v -p codesigning \
    | awk -v identity="$signing_identity" '$2 == identity {
        line = $0
        sub(/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"/, "", line)
        sub(/"$/, "", line)
        print line
        exit
      }'
  if [[ "${signing_identity}" != "" ]]; then
    security find-identity -v -p codesigning \
      | awk -v identity_name="$signing_identity" 'index($0, "\"" identity_name "\"") > 0 {
          print identity_name
          exit
        }'
  fi
}

resolve_codesign_identity() {
  if [[ "${codesign_identity}" != "auto" ]]; then
    echo "${codesign_identity}"
    return
  fi

  local identity=""
  identity="$(find_codesigning_identity "Developer ID Application:.*\\(${codesign_team_id}\\)")"
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Developer ID Application:.*${codesign_developer_name}")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Developer ID Application:")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Apple Development:.*${codesign_developer_name}")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Apple Development:.*\\(${codesign_team_id}\\)")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Mac Developer:.*${codesign_developer_name}")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Mac Developer:.*\\(${codesign_team_id}\\)")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Apple Development:")"
  fi
  if [[ -z "${identity}" ]]; then
    identity="$(find_codesigning_identity "Mac Developer:")"
  fi

  if [[ -n "${identity}" ]]; then
    echo "${identity}"
  else
    echo "-"
  fi
}

mkdir -p "${module_cache}" "${tmp_dir}"
rm -rf "${app_dir}"
mkdir -p "${macos_dir}" "${resources_dir}" "${frameworks_dir}"
sparkle_install_dir="$("${repo_root}/scripts/prepare-sparkle.sh")"

cp "${resource_dir}/Info.plist" "${contents_dir}/Info.plist"
if [[ -n "${bundle_short_version}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${bundle_short_version}" "${contents_dir}/Info.plist"
fi
if [[ -n "${bundle_version}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${bundle_version}" "${contents_dir}/Info.plist"
fi

if [[ -f "${resource_dir}/AppIcon.icns" ]]; then
  cp "${resource_dir}/AppIcon.icns" "${resources_dir}/AppIcon.icns"
else
  echo "Warning: ${resource_dir}/AppIcon.icns not found; run scripts/generate-app-icon.sh" >&2
fi

swift_sources=()
while IFS= read -r source_file; do
  swift_sources+=("${source_file}")
done < <(find "${source_dir}" -name '*.swift' -print | sort)
while IFS= read -r source_file; do
  swift_sources+=("${source_file}")
done < <(find "${core_source_dir}" -name '*.swift' -print | sort)

if [[ "${#swift_sources[@]}" -eq 0 ]]; then
  echo "No Swift sources found in ${source_dir}" >&2
  exit 1
fi

TMPDIR="${tmp_dir}" xcrun swiftc \
  -target arm64-apple-macosx26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "${module_cache}" \
  -F "${sparkle_install_dir}" \
  -parse-as-library \
  -O \
  -Xlinker -rpath \
  -Xlinker "@executable_path/../Frameworks" \
  -framework AppKit \
  -framework SwiftUI \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -framework UniformTypeIdentifiers \
  -framework ImageIO \
  -framework Sparkle \
  "${swift_sources[@]}" \
  -o "${macos_dir}/${app_name}"

bundle_sparkle_framework() {
  local sparkle_framework_source="${sparkle_install_dir}/Sparkle.framework"
  local sparkle_framework_destination="${frameworks_dir}/Sparkle.framework"

  if [[ ! -d "${sparkle_framework_source}" ]]; then
    echo "Sparkle framework not found at ${sparkle_framework_source}" >&2
    exit 1
  fi

  rm -rf "${sparkle_framework_destination}"
  ditto "${sparkle_framework_source}" "${sparkle_framework_destination}"
}

bundle_sparkle_framework

bundle_webp_dylibs() {
  local webp_lib=""
  local sharpyuv_lib=""

  for candidate in /opt/homebrew/lib/libwebp.7.dylib /usr/local/lib/libwebp.7.dylib; do
    if [[ -f "${candidate}" ]]; then
      webp_lib="${candidate}"
      break
    fi
  done

  for candidate in /opt/homebrew/lib/libsharpyuv.0.dylib /usr/local/lib/libsharpyuv.0.dylib; do
    if [[ -f "${candidate}" ]]; then
      sharpyuv_lib="${candidate}"
      break
    fi
  done

  if [[ -z "${webp_lib}" || -z "${sharpyuv_lib}" ]]; then
    echo "warning: libwebp not bundled; WebP export will require a system libwebp.dylib at runtime." >&2
    return
  fi

  cp -f "${webp_lib}" "${frameworks_dir}/libwebp.7.dylib"
  cp -f "${sharpyuv_lib}" "${frameworks_dir}/libsharpyuv.0.dylib"
  chmod 755 "${frameworks_dir}/libwebp.7.dylib" "${frameworks_dir}/libsharpyuv.0.dylib"

  install_name_tool -id "@rpath/libwebp.7.dylib" "${frameworks_dir}/libwebp.7.dylib"
  install_name_tool -change "@rpath/libsharpyuv.0.dylib" "@rpath/libsharpyuv.0.dylib" "${frameworks_dir}/libwebp.7.dylib" 2>/dev/null || true
  install_name_tool -change "/opt/homebrew/opt/webp/lib/libsharpyuv.0.dylib" "@rpath/libsharpyuv.0.dylib" "${frameworks_dir}/libwebp.7.dylib" 2>/dev/null || true
  install_name_tool -change "/usr/local/opt/webp/lib/libsharpyuv.0.dylib" "@rpath/libsharpyuv.0.dylib" "${frameworks_dir}/libwebp.7.dylib" 2>/dev/null || true
  install_name_tool -id "@rpath/libsharpyuv.0.dylib" "${frameworks_dir}/libsharpyuv.0.dylib"
}

bundle_webp_dylibs

resolved_identity="$(resolve_codesign_identity)"
resolved_identity_name="$(codesigning_identity_name "${resolved_identity}")"

codesign_path() {
  local target="$1"
  local -a args=(--force --sign "${resolved_identity}")

  if [[ -n "${codesign_keychain}" && "${resolved_identity}" != "-" ]]; then
    args+=(--keychain "${codesign_keychain}")
  fi

  case "${codesign_options_runtime}" in
    auto)
      if [[ "${resolved_identity}" != "-" ]]; then
        args+=(--options runtime)
      fi
      ;;
    true|1|yes)
      args+=(--options runtime)
      ;;
    false|0|no|none)
      ;;
    *)
      echo "Unsupported HEYSNAP_CODESIGN_OPTIONS_RUNTIME: ${codesign_options_runtime}" >&2
      exit 1
      ;;
  esac

  case "${codesign_timestamp}" in
    auto)
      if [[ "${resolved_identity_name}" == Developer\ ID\ Application:* ]]; then
        args+=(--timestamp)
      else
        args+=(--timestamp=none)
      fi
      ;;
    true|1|yes)
      args+=(--timestamp)
      ;;
    false|0|no|none)
      args+=(--timestamp=none)
      ;;
    *)
      echo "Unsupported HEYSNAP_CODESIGN_TIMESTAMP: ${codesign_timestamp}" >&2
      exit 1
      ;;
  esac

  codesign "${args[@]}" "${target}"
}

xattr -cr "${app_dir}" 2>/dev/null || true
if compgen -G "${frameworks_dir}/*.dylib" >/dev/null; then
  for dylib_path in "${frameworks_dir}"/*.dylib; do
    codesign_path "${dylib_path}"
  done
fi
if [[ -d "${frameworks_dir}/Sparkle.framework" ]]; then
  sparkle_version_dir="${frameworks_dir}/Sparkle.framework/Versions/B"
  if [[ -d "${sparkle_version_dir}/XPCServices/Downloader.xpc" ]]; then
    codesign_path "${sparkle_version_dir}/XPCServices/Downloader.xpc"
  fi
  if [[ -d "${sparkle_version_dir}/XPCServices/Installer.xpc" ]]; then
    codesign_path "${sparkle_version_dir}/XPCServices/Installer.xpc"
  fi
  if [[ -d "${sparkle_version_dir}/Updater.app" ]]; then
    codesign_path "${sparkle_version_dir}/Updater.app"
  fi
  if [[ -f "${sparkle_version_dir}/Autoupdate" ]]; then
    codesign_path "${sparkle_version_dir}/Autoupdate"
  fi
  codesign_path "${frameworks_dir}/Sparkle.framework"
fi
codesign_path "${app_dir}"
echo "codesign identity: ${resolved_identity_name}" >&2
codesign -dv --verbose=2 "${app_dir}" 2>&1 | awk '/Authority=|TeamIdentifier=|Signature=|Identifier=/ { print }' >&2
codesign -d -r- "${app_dir}" 2>&1 | sed -n '/designated/p' >&2

if [[ "${install_user_app}" -eq 1 ]]; then
  install_dir="${HOME}/Applications"
  install_app_dir="${install_dir}/${app_name}.app"
  mkdir -p "${install_dir}"
  rm -rf "${install_app_dir}"
  ditto "${app_dir}" "${install_app_dir}"
  echo "${install_app_dir}"
  exit 0
fi

echo "${app_dir}"
