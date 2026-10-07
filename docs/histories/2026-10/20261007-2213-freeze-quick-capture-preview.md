## [2026-10-07 22:13] | Task: 定格快速截图预览

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 截图应该定格在触发的那一刻，再在截图上绘制标注，不能继续显示下面变化的内容。

### 🛠 Changes Overview

**Scope:** macOS 快速截图/标注 overlay。

- 原有预捕获快照用于导出但未绘制到 overlay，透明选区仍显示实时桌面。现在直接绘制快照底图，并通过 even-odd mask 只压暗选区外，保留选区不透明的原始像素。
- 进入快速截图时单次采集屏幕联合区域，各屏幕预览和最终导出通过共用 `CaptureSnapshotGeometry` 裁切，避免其他屏幕继续显示实时内容。
- 固定截图会话的窗口候选列表，避免实时窗口移动改变悬停选择框。
- 捕获失败不进入无底图的快速标注；防止重复热键在预捕获/已有 overlay 时截图 overlay 本身。
- 滚动截图主动隐藏定格底图并保留鼠标穿透，失败返回时重新显示会话原快照。

### 🧠 Design Intent (Why)

快速截图的可见画面与复制/保存结果必须来自同一份不可变截图，而不能一边看实时窗口一边导出旧快照。保留滚动截图需要连续采集的语义。

### ✅ Validation

- `scripts/test-macos-capture-snapshot.sh` 通过：负坐标、多屏上下裁切、1x/2x 像素、选区不透明、实时底图变化后多次重绘仍保留原图、不累积遮罩及滚动实时透出。
- 检查渲染预览；app 构建及 Developer ID 签名验证通过，使用无在线时间戳的本机开发构建。
- 安装并重启固定安装位置，确认运行路径和热键注册。真实动态桌面的端到端交互仍待用户验证。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/CaptureSnapshotGeometry.swift`
- `apps/macos/HeySnap/Tests/CaptureSnapshotTests.swift`
- `scripts/test-macos-capture-snapshot.sh`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/QUALITY_SCORE.md`、`docs/releases/feature-release-notes.md`
