## [2026-10-07 22:29] | Task: Editor 本地 OCR 和滚动截图图标

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 修复框选工具条 Scrolling Capture 图标不显示；Editor 左侧添加 OCR 图标，使用 macOS 本地 OCR 识别框选截图里的文字并自动复制到剪切板。

### 🛠 Changes Overview

- 实测 `rectangle.stack.badge.arrow.down` 不存在，替换为系统已验证可用的 `arrow.up.and.down`，保留滚动截图动作和原位置。
- Core 新增 `ScreenshotTextRecognizer`，用 Vision accurate 模式、自动语言检测和中英文优先列表识别已有截图，返回多行纯文本。
- Editor 品牌右侧、复制/保存左侧新增 `text.viewfinder` OCR 按钮；识别当前底图（含已应用裁切，有待确认裁切框时识别框内），不包含标注覆盖层或界面，不重新截图。
- 后台识别、成功自动复制，空图/失败保留剪切板；短暂状态反馈、关闭窗口后取消结果交付，日志不记录文本。OCR 按钮禁用 AppKit 自动校验，防止识别未完成就被自动启用。
- 新增 Core 实际 OCR 测试及真实 Editor 按钮/剪切板测试脚本，同步架构、前端规范、质量、安全及发布记录。

### 🧠 Design Intent (Why)

OCR 只依赖本地位图与 Apple Vision；用户一键得到可粘贴文本，图标不会因为无效符号悄悄消失，后台识别不阻塞画布操作。

### ✅ Validation

- `swift test --package-path packages/HeySnapCore`：24 项通过，包括中英文混排、多行顺序、空图及裁切范围。
- `scripts/test-macos-editor-ocr.sh`：真实工具栏图标、后台识别按钮状态、自动写剪切板、空结果保留通过，测试后恢复剪切板；检查 UI 渲染预览。
- app 构建、Developer ID 签名验证和固定安装位置重启通过；本机构建关闭在线时间戳。
- 参考 Apple 官方 `VNRecognizeTextRequest` / `automaticallyDetectsLanguage` 文档。

### 📁 Files Modified

- `packages/HeySnapCore/Sources/HeySnapCore/OCR/ScreenshotTextRecognizer.swift`
- `packages/HeySnapCore/Tests/HeySnapCoreTests/ScreenshotTextRecognizerTests.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/Features/Editor/ScreenshotEditorWindowController.swift`
- `apps/macos/HeySnap/Tests/EditorOCRTests.swift`
- `scripts/test-macos-editor-ocr.sh`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/QUALITY_SCORE.md`、`docs/SECURITY.md`、`docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/20261007-local-editor-ocr.md`
