## [2026-10-07 22:18] | Task: 排除截图中的系统鼠标并提交推送

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 截图中不能出现系统自带的鼠标，修复后提交推送。

### 🛠 Changes Overview

- 屏幕/区域的 `SCScreenshotConfiguration` 曾默认开启指针，定格预览将其作为图片像素显示。统一改为 `showsCursor = false`，删除两个私有采集方法的指针开关参数，防止调用方再次启用。
- 窗口、滚动帧的 `SCStreamConfiguration` 继续显式排除指针；窗口背景采集同样固定不采指针。
- 无指针底图直接供定格预览、复制、保存、Pin 与 Editor 使用，不修改交互时系统 cursor 的正常显示。
- 同步架构、前端规范、发布记录与前轮计划状态；按用户要求提交推送此前已验证的共用基础标注、定格预览、圆圈轮廓锚点和文本拖动改动。

### 🧠 Design Intent (Why)

从采集源头排除指针，避免它成为无法由标注层移除的底图像素。所有截图类型保持一致。

### ✅ Validation

- HeySnapCore 单元测试与四个 AppKit 回归脚本通过。
- app 构建和 Developer ID 签名检查通过，本机开发构建关闭在线时间戳；安装并重启固定安装位置。
- 检查所有四处截图配置均显式设置 `showsCursor = false`。

### 📁 Files Modified

- `packages/HeySnapCore/Sources/HeySnapCore/Capture/ScreenshotService.swift`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/20261007-shared-basic-annotations.md`
