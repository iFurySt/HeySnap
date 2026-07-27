#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sparkle_version="${HEYSNAP_SPARKLE_VERSION:-2.9.4}"
sparkle_sha256="${HEYSNAP_SPARKLE_SHA256:-ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9}"
sparkle_url="${HEYSNAP_SPARKLE_URL:-https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz}"
vendor_root="${repo_root}/.build/vendor/sparkle"
download_dir="${vendor_root}/downloads"
install_dir="${vendor_root}/Sparkle-${sparkle_version}"
archive_path="${download_dir}/Sparkle-${sparkle_version}.tar.xz"

if [[ -d "${install_dir}/Sparkle.framework" && -x "${install_dir}/bin/generate_appcast" ]]; then
  echo "${install_dir}"
  exit 0
fi

mkdir -p "${download_dir}"

if [[ ! -f "${archive_path}" ]]; then
  curl -fL "${sparkle_url}" -o "${archive_path}"
fi

actual_sha256="$(shasum -a 256 "${archive_path}" | awk '{ print $1 }')"
if [[ "${actual_sha256}" != "${sparkle_sha256}" ]]; then
  echo "Sparkle archive checksum mismatch." >&2
  echo "expected: ${sparkle_sha256}" >&2
  echo "actual:   ${actual_sha256}" >&2
  exit 1
fi

/bin/rm -rf "${install_dir}"
mkdir -p "${install_dir}"
/usr/bin/tar -xJf "${archive_path}" -C "${install_dir}"
chmod +x "${install_dir}/bin/generate_appcast" "${install_dir}/bin/sign_update" "${install_dir}/bin/generate_keys"

echo "${install_dir}"
