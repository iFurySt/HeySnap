#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_dir="${repo_root}/.build/macos/capture-snapshot-checks"
mkdir -p "${check_dir}"
swiftc \
  "${repo_root}/apps/macos/HeySnap/Sources/Features/Capture/CaptureSnapshotGeometry.swift" \
  "${repo_root}/apps/macos/HeySnap/Tests/CaptureSnapshotTests.swift" \
  -o "${check_dir}/check"
"${check_dir}/check" "${check_dir}/preview"
