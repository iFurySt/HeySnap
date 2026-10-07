## [2026-10-07 22:16] | Task: 圆圈轮廓锚点与快速文字拖动

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> Editor 和快速截图的圆形四角锚点应在圆形上；快速截图放置文本后无法再次拖动位置，需要修复。

### 🛠 Changes Overview

- 圆圈斜向锚点按椭圆参数坐标投到轮廓上，两处 UI 共用绘制坐标、命中和 hover；矩形和裁切保持原有八点布局。
- 斜向拖动反算外接矩形角点，以固定对角为基准修正手柄内缩比例，避免按下或拖动时跳变；保留 Shift 等比缩放与双向坐标适配。
- 快速标注已有文本单击开始移动、双击进入编辑，消除文字工具状态下直接进入编辑而绕过移动分支的问题。
- 共用文本输入控件可把边缘鼠标事件交给画布；快速标注启用此适配，允许输入期间拖动边框，同时保留内部文本选择/编辑。
- 更新架构、前端约定、发布记录与 AppKit 回归检查。

### 🧠 Design Intent (Why)

锚点应表达形状本身，缩放计算需要随其位置同步变化，不能仅改显示。文本的位置移动与字符编辑通过单击/双击及输入框边缘明确区分。

### ✅ Validation

- 基础标注 AppKit 回归通过：增加椭圆八点轮廓方程、旧角点不命中、无跳变、锚点随鼠标、两 UI 的普通/Shift 缩放一致性，以及真实文本控件边缘透传和内部编辑命中、移动保留文本样式。
- 1x 渲染预览核对圆圈锚点，app 构建与 Developer ID 签名验证、安装版重启检查通过（本机开发构建关闭在线时间戳）。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationShapeGeometry.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationInlineTextView.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/OverlayMarkupAnnotation.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/Features/Editor/EditorAnnotation.swift`
- `apps/macos/HeySnap/Sources/Features/Editor/ScreenshotEditorWindowController.swift`
- `apps/macos/HeySnap/Tests/BasicAnnotationTests.swift`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/releases/feature-release-notes.md`
