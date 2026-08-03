## [2026-07-27 11:12] | Task: add scrolling capture entry

### Execution Context

- **Agent ID**: `TRAE CLI`
- **Base Model**: `GPT-5`
- **Runtime**: `TRAE CLI on macOS`

### User Query

> 增加滚动截图；先看 Shottr 和飞书的实现参考；优先实现 Shottr 式框选后自动滚动，同时 General 里提供自动/手动滚动切换；不新增独立快捷键，在框选 quick markup bar 的 Pin 左边加滚动截图按钮触发。

### Changes Overview

**Scope:** macOS app capture flow, settings UI, HeySnapCore stitching logic, docs.

**Key Actions:**

- **Reference plan**: Added an active execution plan recording Shottr `ScrollCapturer` evidence, Lark native prompt-window evidence, first-version scope, risks, and verification.
- **Manual scope**: Settled the first reliable scrolling capture implementation on manual scrolling only; removed the mode switch and automatic-scroll permission path from the shipped UI.
- **Quick markup entry**: Added a scrolling capture button immediately before Pin in the area-selection quick markup bar.
- **Workflow**: Added `ScrollingCaptureWorkflow` to sample the selected region while the user scrolls manually, show a small progress window, stop after movement settles, and open the stitched result in the editor.
- **Stitching core**: Added `ScrollingCaptureStitcher` for vertical overlap shift estimation and long-image composition, with focused unit tests.
- **Scrolling refinement**: Kept the selection overlay visible while scrolling capture runs, excluded HeySnap's own overlay windows from scrolling-frame sampling, rejected tiny/low-quality shift matches, and blocked capture hotkey re-entry during the scrolling workflow.

### Design Intent (Why)

Shottr's behavior is closer to the target UX, but automatic scrolling proved unreliable enough to keep out of the first shippable slice. ShareX's open-source implementation provided the safer shape: keep a click-through region frame, repeatedly sample while the user scrolls, stop when frames stop changing, and stitch with overlap matching. The first version keeps rolling capture separate from the single-frame backend: ScreenCaptureKit still captures frames, app layer owns the manual workflow, and Core owns the testable pixel stitching logic.

### Files Modified

- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/ScrollingCaptureWorkflow.swift`
- `apps/macos/HeySnap/Sources/Features/Preferences/PreferencesView.swift`
- `apps/macos/HeySnap/Sources/Infrastructure/Settings/AppSettings.swift`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `packages/HeySnapCore/Sources/HeySnapCore/Capture/ScreenshotService.swift`
- `packages/HeySnapCore/Sources/HeySnapCore/Capture/ScrollingCaptureStitcher.swift`
- `packages/HeySnapCore/Tests/HeySnapCoreTests/ScrollingCaptureStitcherTests.swift`
- `docs/exec-plans/active/20260727-scrolling-capture.md`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
