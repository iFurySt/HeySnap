#!/usr/bin/env bash

# Generate HeySnap's app icon (.icns) and a review preview PNG from AppIcon.svg.
#
# Source of truth: apps/macos/HeySnap/Resources/AppIcon.svg
# Outputs:
#   apps/macos/HeySnap/Resources/AppIcon.icns
#   apps/macos/HeySnap/Resources/AppIcon-preview.png
#
# Idempotent: safe to re-run after editing the SVG. Requires rsvg-convert and
# iconutil (both available via Homebrew librsvg / the macOS toolchain).

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resource_dir="${repo_root}/apps/macos/HeySnap/Resources"
svg_source="${resource_dir}/AppIcon.svg"
icns_out="${resource_dir}/AppIcon.icns"
preview_out="${resource_dir}/AppIcon-preview.png"

if [[ ! -f "${svg_source}" ]]; then
  echo "Missing icon source: ${svg_source}" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found. Install it with: brew install librsvg" >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "iconutil not found (expected on macOS)." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
iconset_dir="${work_dir}/AppIcon.iconset"
mkdir -p "${iconset_dir}"
trap 'rm -rf "${work_dir}"' EXIT

render() {
  local size="$1" name="$2"
  rsvg-convert --width "${size}" --height "${size}" \
    --output "${iconset_dir}/${name}" "${svg_source}"
}

# macOS iconset requires 16, 32, 128, 256, 512 in @1x and @2x variants.
render 16   "icon_16x16.png"
render 32   "icon_16x16@2x.png"
render 32   "icon_32x32.png"
render 64   "icon_32x32@2x.png"
render 128  "icon_128x128.png"
render 256  "icon_128x128@2x.png"
render 256  "icon_256x256.png"
render 512  "icon_256x256@2x.png"
render 512  "icon_512x512.png"
render 1024 "icon_512x512@2x.png"

iconutil --convert icns --output "${icns_out}" "${iconset_dir}"

# Human-review preview at a comfortable size.
rsvg-convert --width 512 --height 512 --output "${preview_out}" "${svg_source}"

echo "Wrote ${icns_out}"
echo "Wrote ${preview_out}"
