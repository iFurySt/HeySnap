## [2026-10-07 22:06] | Task: 统一快速标注基础工具与 Editor

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 提交推送已完成的箭头改动，再把矩形、圆圈、直线、文字按照箭头的方式与 Editor 对齐并复用实现。

### 🛠 Changes Overview

**Scope:** macOS AppKit 标注、预览和导出。

- 已提交推送箭头与属性条改动 `38f2ae5`。
- 提取共享矩形/圆圈几何和手柄；统一绘制、空心轮廓命中、八点缩放、方向指针及 Shift 等比约束，显式适配上下相反的画布坐标。
- 直线共用 Editor 的二次曲线及圆角端点，沿用箭头的曲线上中点、拖动反算、整体移动和命中；修复快速标注直线按端点连线命中、控制点锚点离开曲线的问题。
- 共用文字渲染、布局和真实输入控件，统一默认字号 12、中文字体、内边距、自动尺寸、多行和 Normal/Filled；快速标注添加样式选项、选择时同步属性、Esc 恢复编辑前状态，文字不再显示缩放手柄。导出不带编辑环，Retina 同时缩放字体、内边距和背景圆角。
- 将两个 UI 的标注模型拆成独立文件，保留各自状态与坐标适配；更新架构、前端约定、质量说明、发布记录和 execution plan。

### 🧠 Design Intent (Why)

共享几何、绘制和输入控件，让快速标注与 Editor 的操作由同一套实现决定，避免各自维护近似算法再次出现样式与锚点差异。窗口和快照/撤销状态仍由各 UI 持有。

### ✅ Validation

- `scripts/test-macos-basic-annotations.sh`：空心命中、16 组八点缩放/坐标适配、直线中点/移动、文字 Normal/Filled、自动尺寸、多行、Retina、中文输入及样式控件通过。
- `scripts/test-macos-arrow-rendering.sh`、`scripts/test-macos-quick-markup-controls.sh` 通过。
- 视觉核对 1x/2x 标注预览；构建、Developer ID 签名验证和安装版重启通过，日志确认安装版路径及热键注册。
- 在线签名时间戳服务不可用，本机验证构建使用 `HEYSNAP_CODESIGN_TIMESTAMP=none`，保持原 Developer ID 身份；未自动验证真实窗口的完整鼠标/输入法候选交互。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationShapeGeometry.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationLineRenderer.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationTextRenderer.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationInlineTextView.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationArrowGeometry.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationDefaults.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/OverlayMarkupAnnotation.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/QuickMarkupPropertyBarLayout.swift`
- `apps/macos/HeySnap/Sources/Features/Editor/EditorAnnotation.swift`
- `apps/macos/HeySnap/Sources/Features/Editor/ScreenshotEditorWindowController.swift`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `apps/macos/HeySnap/Tests/BasicAnnotationTests.swift`
- `scripts/test-macos-basic-annotations.sh`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/QUALITY_SCORE.md`、`docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/20261007-shared-basic-annotations.md`
