#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=""
bundle_version="${HEYSNAP_BUNDLE_VERSION:-${GITHUB_RUN_NUMBER:-$(git -C "${repo_root}" rev-list --count HEAD 2>/dev/null || echo 1)}}"
output_dir=""
codesign_team_id="${HEYSNAP_CODESIGN_TEAM_ID:-J9P29FA5BX}"

usage() {
  cat <<'EOF'
Usage: ./scripts/build-macos-dmg.sh [--version X.Y.Z] [--bundle-version N] [--output-dir PATH]

Builds a signed HeySnap.app and packages it into a drag-install DMG.

Environment:
  HEYSNAP_CODESIGN_IDENTITY=auto|-|"Developer ID Application: Example (TEAMID)"
  HEYSNAP_CODESIGN_KEYCHAIN=/path/to/signing.keychain-db
  HEYSNAP_CODESIGN_TIMESTAMP=auto|true|false
  HEYSNAP_CODESIGN_OPTIONS_RUNTIME=auto|true|false
  HEYSNAP_CODESIGN_TEAM_ID=J9P29FA5BX
  HEYSNAP_BUNDLE_VERSION=CI_BUILD_NUMBER
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      version="${2:-}"
      if [[ -z "${version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --bundle-version)
      bundle_version="${2:-}"
      if [[ -z "${bundle_version}" ]]; then
        echo "--bundle-version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      if [[ -z "${output_dir}" ]]; then
        echo "--output-dir requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${version}" ]]; then
  if tag="$(git -C "${repo_root}" describe --tags --exact-match 2>/dev/null)"; then
    version="${tag#v}"
  else
    version="0.0.0-dev"
  fi
fi

if [[ -z "${output_dir}" ]]; then
  output_dir="${repo_root}/dist/release/heysnap"
fi

find_codesigning_identity() {
  local identity_pattern="$1"

  security find-identity -v -p codesigning \
    | awk -v pattern="$identity_pattern" '$0 ~ pattern && $0 !~ /CSSMERR|REVOKED/ { print $2; exit }' \
    | head -n 1
}

if [[ -z "${HEYSNAP_CODESIGN_IDENTITY+x}" ]]; then
  developer_id_identity="$(find_codesigning_identity "Developer ID Application:.*\\(${codesign_team_id}\\)")"
  if [[ -n "${developer_id_identity}" ]]; then
    export HEYSNAP_CODESIGN_IDENTITY="${developer_id_identity}"
    export HEYSNAP_CODESIGN_TIMESTAMP="${HEYSNAP_CODESIGN_TIMESTAMP:-true}"
    export HEYSNAP_CODESIGN_OPTIONS_RUNTIME="${HEYSNAP_CODESIGN_OPTIONS_RUNTIME:-true}"
  fi
fi

app_name="HeySnap"
app_path="${repo_root}/.build/macos/${app_name}.app"
dmg_root="${output_dir}/dmg-root"
dmg_path="${output_dir}/${app_name}-${version}.dmg"

rm -rf "${output_dir}"
mkdir -p "${dmg_root}"

"${repo_root}/scripts/build-macos-app.sh" \
  --build-only \
  --version "${version}" \
  --bundle-version "${bundle_version}" \
  >/dev/null

plutil -lint "${app_path}/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "${app_path}" >&2

ditto "${app_path}" "${dmg_root}/${app_name}.app"
ln -s /Applications "${dmg_root}/Applications"

hdiutil create \
  -volname "${app_name}" \
  -srcfolder "${dmg_root}" \
  -ov \
  -format UDZO \
  "${dmg_path}" \
  >/dev/null

echo "${dmg_path}"
