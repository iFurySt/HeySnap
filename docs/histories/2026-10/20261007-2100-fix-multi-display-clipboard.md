## [2026-10-07 21:00] | Task: 修复多屏截图确认后无法复制

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 截图双击或点击勾后无法进入剪贴板，之前正常，希望定位并修复。

### 🛠 Changes Overview

**Scope:** HeySnapCore 坐标转换和 macOS app 诊断。

- 将 AppKit 到 ScreenCaptureKit 的转换统一绕主显示器顶边翻转，避免下方显示器被映射到不存在的屏幕区域。
- 覆盖上下排列、不同高度显示器和失败区域的回归测试。
- 快速标注复制检查剪贴板写入结果，失败时不再记录成功。
- 启动日志记录实际 bundle 路径和版本，方便诊断重复安装导致的运行版本混淆。
- 同步架构中的坐标约定。

### 🧠 Design Intent (Why)

截图 API 接收跨显示器的全局坐标，不能按各屏自己的顶边翻转。截图阶段失败时无法进入复制流程，表面表现为剪贴板失效。

### 📁 Files Modified

- `packages/HeySnapCore/Sources/HeySnapCore/Capture/CaptureCoordinateConverter.swift`
- `packages/HeySnapCore/Tests/HeySnapCoreTests/CaptureCoordinateConverterTests.swift`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `docs/ARCHITECTURE.md`

### 验证

- `swift test --package-path packages/HeySnapCore`：21 项测试通过。
- 本机截图 API 对比：旧下方屏幕区域坐标复现采集失败；修正区域及整屏均返回有效图像。
- PNG 编码和独立测试剪贴板写入、读回一致性验证通过，不覆盖用户现有剪贴板。
- macOS app 构建及 Developer ID 签名校验通过；已备份系统目录旧应用并安装修复版，确认新进程运行在标准系统安装路径，现有屏幕录制权限有效。
- 原用户目录副本保留，已退出其进程；真实双击/勾确认后的目标应用粘贴仍需用户手动复验。
