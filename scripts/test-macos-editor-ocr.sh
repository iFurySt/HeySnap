#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="${repo_root}/.build/macos/editor-ocr-checks"
mkdir -p "${check_dir}"
sources=()
while IFS= read -r source; do sources+=("${source}"); done < <(find "${repo_root}/packages/HeySnapCore/Sources" -name '*.swift' -print)
swiftc "${sources[@]}" \
  "${repo_root}"/apps/macos/HeySnap/Sources/Features/Annotations/*.swift \
  "${repo_root}"/apps/macos/HeySnap/Sources/Features/Editor/*.swift \
  "${repo_root}/apps/macos/HeySnap/Sources/Infrastructure/Logging/AppLogger.swift" \
  "${repo_root}/apps/macos/HeySnap/Tests/EditorOCRTests.swift" \
  -o "${check_dir}/check"
"${check_dir}/check" "${check_dir}/preview.png"
