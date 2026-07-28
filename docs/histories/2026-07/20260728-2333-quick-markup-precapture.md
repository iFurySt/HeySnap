## [2026-07-28 23:33] | Task: 优化 quick markup 确认截图竞态

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> quick markup 框选后点击勾时，如果快速切换窗口，会截图到新窗口，说明截图速度和效率太低。

### 🛠 Changes Overview

**Scope:** macOS app capture flow, HeySnapCore capture metadata, architecture docs

**Key Actions:**

- **[Pre-capture reuse]**: quick markup 在确认、保存、pin、打开编辑器时优先使用热键触发时的整屏快照裁切结果，不再默认关闭 overlay 后重新截图。
- **[Fallback preserved]**: 选区无法从预捕获快照裁出时，保留原来的等待 overlay 消失后实时区域截图路径。
- **[Source metadata]**: `CapturedScreenshot` 增加来源 rect，避免多屏场景里用确认时鼠标位置反推原始快照屏幕。
- **[Docs]**: 更新架构文档里的 quick markup 截图时机说明。

### 🧠 Design Intent (Why)

quick markup 的用户意图在框选完成时已经确定；确认按钮之后再等待 overlay 消失并重新抓屏，会给前台窗口切换留下竞态窗口。用预捕获快照裁切可以把确认动作变成同步本地图像处理，既更快，也能绑定用户最初要截的画面。保留实时截图回退是为了兼容跨屏或异常裁切场景。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `packages/HeySnapCore/Sources/HeySnapCore/Capture/ScreenshotService.swift`
- `docs/ARCHITECTURE.md`
