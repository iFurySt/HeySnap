#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=""
release_tag=""
dmg_path=""
output_dir="${repo_root}/dist/release/heysnap"
private_key_file="${repo_root}/.apple/sparkle_ed_private_key"
download_url_prefix=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --version)
      version="${2:-}"
      if [[ -z "${version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift
      ;;
    --release-tag)
      release_tag="${2:-}"
      if [[ -z "${release_tag}" ]]; then
        echo "--release-tag requires a value" >&2
        exit 1
      fi
      shift
      ;;
    --dmg-path)
      dmg_path="${2:-}"
      if [[ -z "${dmg_path}" ]]; then
        echo "--dmg-path requires a value" >&2
        exit 1
      fi
      shift
      ;;
    --output-dir)
      output_dir="${2:-}"
      if [[ -z "${output_dir}" ]]; then
        echo "--output-dir requires a value" >&2
        exit 1
      fi
      shift
      ;;
    --download-url-prefix)
      download_url_prefix="${2:-}"
      if [[ -z "${download_url_prefix}" ]]; then
        echo "--download-url-prefix requires a value" >&2
        exit 1
      fi
      shift
      ;;
    --private-key-file)
      private_key_file="${2:-}"
      if [[ -z "${private_key_file}" ]]; then
        echo "--private-key-file requires a value" >&2
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

if [[ -z "${version}" ]]; then
  version="$(git -C "${repo_root}" describe --tags --match 'v*' --exact-match 2>/dev/null | sed 's/^v//' || true)"
fi
if [[ -z "${version}" ]]; then
  version="0.0.0-dev"
fi

if [[ -z "${release_tag}" ]]; then
  release_tag="v${version}"
fi

if [[ -z "${dmg_path}" ]]; then
  dmg_path="${output_dir}/HeySnap-${version}.dmg"
fi

if [[ ! -f "${dmg_path}" ]]; then
  echo "DMG not found: ${dmg_path}" >&2
  exit 1
fi

if [[ -z "${download_url_prefix}" ]]; then
  download_url_prefix="https://github.com/iFurySt/HeySnap/releases/download/${release_tag}"
fi
download_url_prefix="${download_url_prefix%/}/"

private_key="${HEYSNAP_SPARKLE_ED_PRIVATE_KEY:-}"
if [[ -z "${private_key}" && -f "${private_key_file}" ]]; then
  private_key="$(tr -d '\n\r' < "${private_key_file}")"
fi
if [[ -z "${private_key}" ]]; then
  echo "Sparkle EdDSA private key is missing." >&2
  echo "Set HEYSNAP_SPARKLE_ED_PRIVATE_KEY or provide ${private_key_file}." >&2
  exit 1
fi

sparkle_install_dir="$("${repo_root}/scripts/prepare-sparkle.sh")"
appcast_source_dir="${repo_root}/.build/appcast/${version}"
appcast_output="${output_dir}/appcast.xml"
dmg_name="$(basename "${dmg_path}")"

/bin/rm -rf "${appcast_source_dir}"
mkdir -p "${appcast_source_dir}" "${output_dir}"
ditto "${dmg_path}" "${appcast_source_dir}/${dmg_name}"

if [[ -f "${repo_root}/docs/releases/feature-release-notes.md" ]]; then
  cp "${repo_root}/docs/releases/feature-release-notes.md" "${appcast_source_dir}/${dmg_name%.dmg}.md"
fi

printf '%s' "${private_key}" \
  | "${sparkle_install_dir}/bin/generate_appcast" \
      --ed-key-file - \
      --download-url-prefix "${download_url_prefix}" \
      --embed-release-notes \
      --disable-signing-warning \
      --maximum-versions 1 \
      -o "${appcast_output}" \
      "${appcast_source_dir}"

echo "${appcast_output}"
