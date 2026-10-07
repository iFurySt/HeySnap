#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="${repo_root}/.build/macos/basic-annotations-checks"
mkdir -p "${check_dir}"
swiftc \
  "${repo_root}"/apps/macos/HeySnap/Sources/Features/Annotations/*.swift \
  "${repo_root}/apps/macos/HeySnap/Sources/Features/Capture/OverlayMarkupAnnotation.swift" \
  "${repo_root}/apps/macos/HeySnap/Sources/Features/Capture/QuickMarkupPropertyBarLayout.swift" \
  "${repo_root}/apps/macos/HeySnap/Sources/Features/Editor/EditorAnnotation.swift" \
  "${repo_root}/apps/macos/HeySnap/Tests/BasicAnnotationTests.swift" \
  -o "${check_dir}/check"
"${check_dir}/check" "${check_dir}/preview"
