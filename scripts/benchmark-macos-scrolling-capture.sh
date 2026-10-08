#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="${repo_root}/.build/macos/scrolling-capture-checks"
mkdir -p "${check_dir}"
swiftc -O "${repo_root}/packages/HeySnapCore/Sources/HeySnapCore/Capture/ScrollingCaptureStitcher.swift" \
    "${repo_root}/apps/macos/HeySnap/Tests/ScrollingCapturePerformanceTests.swift" -o "${check_dir}/benchmark"
"${check_dir}/benchmark"
