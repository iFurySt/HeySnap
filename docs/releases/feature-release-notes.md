# 功能发布记录

## 2026-07

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-07-29 | macOS app | quick markup 框选后可以更快完成常用动作：左键双击选区复制到剪切板，右键单击选区保存到文件。 | 区域选区新增鼠标快捷完成路径，并复用现有 `copyRegion` / `saveRegion` 逻辑，确保预捕获裁切、标注合成、保存格式和 Retina 缩放行为保持一致。 |
| 2026-07-28 | macOS app | quick markup 框选后点击勾时，即使马上切换窗口，也会复制原本框选的画面。 | quick markup 在进入选择前预捕获鼠标所在屏幕，确认、保存、pin 和打开编辑器时优先从预捕获快照裁切并合成标注，避免确认后重新截图导致抓到新前台窗口；异常场景保留实时截图回退。 |
| 2026-07-27 | 发布 | 可以在 About 页手动检查 GitHub Releases 上的新版本，也可以开启后台自动检查和自动下载。 | 接入 Sparkle 2 更新机制：构建脚本固定下载并嵌入 `Sparkle.framework`，`Info.plist` 配置 signed appcast、公钥和自动更新默认值；release workflow 在 notarization/staple 后生成并上传 `appcast.xml`，供 app 从 GitHub Release 检测更新。 |
| 2026-07-09 | 发布 | 可以通过 GitHub tag 自动获得 HeySnap macOS DMG，并挂到对应 GitHub Release。 | 注册 `com.ifuryst.HeySnap` Apple App ID；新增 `scripts/build-macos-dmg.sh`、tag 触发的 `.github/workflows/release.yml` 和 release guide，支持 Developer ID 签名、公证 secrets 与 ad-hoc 降级。 |
| 2026-07-09 | macOS app | 可以按自己的工作流选择截图后直接保存，或进入编辑器继续标注。 | `General > Storage` 新增 `After capture` 下拉，支持 `Save to location` 和 `Open editor` 两种路由；热键截图、区域截图和窗口截图都会按该设置执行。 |
| 2026-07-09 | macOS app | 截图后先进入编辑器，而不是立即落盘；可以在同一个窗口里标注、遮挡、裁切，再复制或保存。 | 新增并打磨独立 AppKit 截图编辑窗口：full-size titlebar 顶部工具条 + 棋盘格画布背景，打开时自动适配窗口，支持受控滚轮缩放、`Command+=` / `Command+-` / `Command+0` 缩放快捷键、选择/移动、带 start/control/end 三锚点的曲线箭头、文字、矩形、圆形、直线、高亮、马赛克遮挡、裁切、撤销/重做、复制和按设置保存。 |
| 2026-07-09 | macOS app | 框选截图时鼠标悬停可自动感知并高亮 app 窗口，单击即截该窗口；框选后 HeySnap 不再抢占前台。 | overlay 改为每屏一层非激活 `NSPanel`，新增 `WindowEnumerator`（`CGWindowListCopyWindowInfo` 枚举 + 命中测试）与 `SCContentFilter` 精确窗口截取；`AreaSelectionController` 输出 `CaptureSelection`（窗口/区域/取消），拖动超过阈值才进入手动框选。 |
| 2026-07-09 | macOS app | 可以在 HotKeys 设置页直接点击输入框重录或清除截图快捷键，设置页外观与 HeyYo 原生风格统一。 | 设置页从 grouped Form 改回 HeyYo 卡片风格（SF Symbol 节标题 + 圆角卡片 + 行分隔线），新增 `ShortcutRecorderField` 胶囊录入框（点击高亮录制、ⓧ 清除），快捷键改为可选值并在变更时即时重注册。 |
| 2026-07-09 | macOS app | 可以用独立快捷键截当前屏幕或拖拽框选截图区域。 | 默认快捷键调整为 `Shift+Option+A` 当前屏幕截图，新增 `Shift+Option+S` 区域选择 overlay，并用 ScreenCaptureKit 保存选区。 |
| 2026-07-09 | macOS app | 多屏环境下快捷键截图只保存当前鼠标所在屏幕，避免把所有显示器拼成一张超宽图。 | 截图区域从所有屏幕 union 改为鼠标所在 `NSScreen`，并记录选中屏幕 frame 便于诊断。 |
| 2026-07-09 | macOS app | 可以通过默认快捷键快速截屏，并在 Preference 中配置保存位置。 | 新增 SwiftUI macOS Preference app，接入 Carbon 全局热键、ScreenCaptureKit 截图保存和稳定签名的 `.app` 构建脚本。 |
| 2026-07-09 | 仓库协作 | 让贡献者从 GitHub 入口和仓库文档看到一致的 HeySnap 项目定位。 | 清理 `.github` issue/PR 模板、停用项目初始化入口，并同步 README、协作文档、安全和质量说明。 |

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-08 | 仓库基础 | 提供 HeySnap 的 Agent-first 协作基础能力。 | 补齐了 AGENTS 入口、execution plan、history、release note 和基础协作文档。 |
