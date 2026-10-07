## [2026-10-07 21:20] | Task: 统一快速标注与 Editor 箭头样式

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 截图后直接拖出的箭头与 Editor 不同，希望完全复用；绘制统一后，中间锚点和拖动行为也必须与 Editor 一致。后续对齐默认大小、颜色及悬停指针，并修复属性条隐形大小选项和过大的颜色勾。

### 🛠 Changes Overview

**Scope:** macOS 标注绘制。

- 将 Editor 的渐宽箭身、实心箭头、单/双箭头、曲线中心线采样提取到 `AnnotationArrowRenderer`。
- Editor 绘制和命中采样复用共享实现，保持既有样式。
- 快速标注预览与复制/保存导出均改用共享渲染器，删除独立的空心箭头实现。
- 提取 `AnnotationArrowGeometry`，共用曲线上中间锚点、拖动反算控制点、端点调整、整体平移、边界、弯曲命中、圆形手柄命中与手柄绘制。
- 快速标注箭头不再夹制拖动位置和整体移动后的控制点，避免改变曲率，与 Editor 画布行为一致。
- Retina 导出同时缩放最小箭身及箭头尺寸，保证预览和结果的比例一致。
- 通过 `AnnotationDefaults` 共享 Editor 和快速标注的默认线宽 5、颜色 `#FF3B30`；快速标注三档调整为 2/5/7，默认选中间档，颜色选项首项也使用同一颜色。
- 将 Editor 四方向移动指针提取到共享标注目录，快速标注箭身和三个锚点悬停时使用同一指针，移除按方向切换的缩放指针逻辑。
- 属性条按实际大小数量布局，共享绘制、悬停及点击边界，移除可点击的假第四档；颜色勾缩小并双轴居中。
- 新增可运行的渲染检查脚本，同步架构文档。

### 🧠 Design Intent (Why)

三条绘制路径原本各自维护箭头实现，导致现场预览、导出及 Editor 外观不一致。共用一套几何使样式调整有唯一真源。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationArrowRenderer.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationArrowGeometry.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationDefaults.swift`
- `apps/macos/HeySnap/Sources/Features/Annotations/AnnotationCursors.swift`
- `apps/macos/HeySnap/Sources/Features/Editor/ScreenshotEditorWindowController.swift`
- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `apps/macos/HeySnap/Tests/AnnotationArrowRendererTests.swift`
- `scripts/test-macos-arrow-rendering.sh`
- `apps/macos/HeySnap/Sources/Features/Capture/QuickMarkupPropertyBarLayout.swift`
- `apps/macos/HeySnap/Tests/QuickMarkupPropertyBarLayoutTests.swift`
- `scripts/test-macos-quick-markup-controls.sh`
- `docs/ARCHITECTURE.md`

### 验证

- `scripts/test-macos-arrow-rendering.sh`：实心箭头/箭身检查通过，16 组粗细、单/双箭头、曲线和 1x/2x 轮廓一致性检查通过。
- 曲线上中点拖动、端点保持、整体平移、弯曲命中、手柄圆形命中检查通过。
- `scripts/test-macos-quick-markup-controls.sh`：三档可见选项命中、假第四档/尾部/间隙不命中、文字四字号、颜色勾尺寸及双轴居中检查通过。
- 渲染预览视觉核对通过。
- `scripts/build-macos-app.sh --build-only`：构建及 Developer ID 签名通过。
- 修复版已安装到标准系统应用路径并重启，安装前版本已备份。
