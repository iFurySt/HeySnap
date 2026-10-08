#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="${repo_root}/.build/macos/scrolling-capture-checks"
mkdir -p "${check_dir}"
sources=()
while IFS= read -r source; do sources+=("${source}"); done < <(find "${repo_root}/packages/HeySnapCore/Sources" -name '*.swift' -print)
swiftc "${sources[@]}" \
  "${repo_root}"/apps/macos/HeySnap/Sources/Features/Annotations/*.swift \
  "${repo_root}"/apps/macos/HeySnap/Sources/Features/Capture/*.swift \
  "${repo_root}/apps/macos/HeySnap/Tests/ScrollingCaptureWorkflowTests.swift" \
  -o "${check_dir}/check"
"${check_dir}/check" "${check_dir}/preview.png"
