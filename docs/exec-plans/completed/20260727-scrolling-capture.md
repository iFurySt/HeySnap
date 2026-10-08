# Scrolling Capture

Status: Completed (initial manual-only implementation)

2026-10-07：后续手动/自动修复与真实浏览器验证由 [新的执行计划](../active/20261007-reliable-scrolling-capture.md) 接续；下文保留初版范围与原始验证要求，不代表当前行为。

## Goal

Add scrolling capture to the existing area-selection flow without adding a separate hotkey. Users select an area, then trigger scrolling capture from the quick markup bar. The first reliable version waits for the user to scroll manually and focuses on stable sampling/stitching.

## Reference Findings

- Shottr 1.9.1 has `ScrollCapturer`, `grabScrolling(direction:method:then:)`, `grabScrollingManual(method:then:)`, `findShift(...)`, `overlayCompareSegment(...)`, and `combine(...)`. Its defaults include `scrollingManualEnabled = 0`, `scrollingMax = 20000`, and `scrollingSpeed = 2`.
- Shottr synthesizes scroll-wheel events with CoreGraphics and requires Accessibility permission in addition to Screen Recording. That automatic path remains a future reference, not part of the current reliable scope.
- ShareX open-source implementation keeps a click-through region frame visible, samples the selected region repeatedly, stops when consecutive frames stop changing, and stitches by matching overlap while ignoring noisy edges. The current HeySnap implementation follows this manual-capture shape first.
- Lark 131 ships `libbv-screen-capture.dylib` with native prompt-window and window-capture primitives such as `ScreenCaptureImpl::GetWindowList`, `WindowPromptView`, `EnablePromptWindow`, `SetPromptWindowInfo`, `CGWindowListCreateImage`, and `SCStream`. Its evidence is most useful for overlay/window prompt behavior rather than long-image stitching.

## First Implementation Scope

- Do not expose a mode switch yet; scrolling capture is manual-only in the first reliable implementation.
- Add one scrolling-capture icon in the quick markup bar immediately before `Pin`.
- Keep the feature scoped to vertical scrolling for the selected region.
- In manual mode, keep the selection visible, sample while the user scrolls, and stop shortly after movement stops.
- Pressing Escape during scrolling capture cancels the scrolling workflow immediately and stops posting further scroll events.
- In manual mode, sample the selected region for a short bounded window while the user scrolls.
- Stitch by estimating vertical displacement from overlapping frame strips, then append the non-overlapping bottom band.
- Route the stitched image to the editor, matching the existing "use the editor for complex output" behavior.

## Risks

- Some apps use smooth scroll inertia, custom scroll views, or scroll modifiers, so synthetic wheel events may not move the content predictably.
- Simple overlap matching can fail on repeated patterns or animated content. The first version should cap height and stop on repeated no-movement rather than producing very large bad images.

## Verification

- Build the app with `make macos-app-build-only`.
- Run package tests with `swift test --package-path packages/HeySnapCore`.
- Manually verify the markup bar still lays out and the new icon appears before Pin in a running app when an interactive desktop is available.
