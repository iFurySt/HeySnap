## [2026-07-27 10:31] | Task: Fix window-click quick markup

### Execution Context

- **Agent ID**: `TRAE CLI`
- **Base Model**: `GPT-5`
- **Runtime**: `TRAE CLI`

### User Query

> Area Selection 里直接 hover 到某个 app 并点击整窗截图时，不应该直接进入 Editor，而应该出现手动框选同款 markup bar。

### Changes Overview

**Scope:** macOS area-selection overlay and repo docs

**Key Actions:**

- **Window click routing**: When quick markup is enabled, a clicked detected window now routes into `enterMarkupMode(rect:)` using the window frame instead of completing a `.window` selection immediately.
- **Docs sync**: Updated architecture notes to state that both window clicks and manual region selections use the in-place quick markup bar.

### Design Intent (Why)

Quick markup is the lightweight post-capture path for area selection. A hover-clicked app window is still a user-selected screen region in this flow, so it should keep the overlay alive and expose the same in-place markup controls instead of opening the full editor.

### Files Modified

- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `docs/ARCHITECTURE.md`
