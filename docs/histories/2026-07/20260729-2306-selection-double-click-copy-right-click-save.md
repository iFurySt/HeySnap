## [2026-07-29 23:06] | Task: selection double click copy

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 框选后，左键双击框选区域自动复制到剪切板；右键单击保存到文件。

### 🛠 Changes Overview

**Scope:** macOS capture overlay

**Key Actions:**

- **Mouse shortcut support**: 在 quick markup 选区内支持左键双击复制、右键单击保存。
- **Shared completion path**: 复用工具条和 Enter 的 `copyRegion` / `saveRegion` completion，确保预捕获裁剪和标注合成行为一致。
- **Docs sync**: 更新架构文档里的 Capture overlay 行为说明。

### 🧠 Design Intent (Why)

新增鼠标快捷行为应该只改变选区完成方式，不复制截图保存或剪切板逻辑。通过复用已有 completion，保存格式、Retina 缩放、预捕获快照和标注渲染继续由原路径处理。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-07/20260729-2306-selection-double-click-copy-right-click-save.md`
