# 架构总览

这份文档用于描述 HeySnap 的顶层结构。当前仓库第一片真实应用是一个 Swift macOS 截图工具，围绕 Preference 配置页和快捷键截图能力展开。

## 仓库结构

- `apps/macos/HeySnap/`：SwiftUI + AppKit macOS app，负责应用生命周期、Preference 界面、全局热键注册、用户设置和 macOS 窗口行为。
- `packages/HeySnapCore/`：截图核心能力包，承载与 UI 解耦的 capture domain、权限检查、坐标/屏幕选择、截图保存等逻辑。
- `infra/`：部署、基础设施和环境定义。
- `scripts/`：仓库级自动化脚本，供人和 Agent 直接调用。
- `docs/`：仓库知识库，也是本地规则和上下文的正式来源。

## 当前 macOS 边界

- `apps/macos/HeySnap/Sources/App/`：SwiftUI App 入口和 `AppDelegate` 生命周期钩子。`AppDelegate` 只编排设置、热键和截图服务，并在启动早期做单实例保护：若同 bundle identifier 已有实例运行，新进程会激活已有实例后退出，避免重复注册热键和打开多个 Preference 窗口。应用级 Settings 菜单绑定 `Command+,`，会从任意活动窗口重新打开并聚焦主设置窗口。
- `apps/macos/HeySnap/Sources/Features/Preferences/`：Preference 界面，侧边栏固定为 `General`、`HotKeys`、`About`；窗口最小尺寸策略（侧边栏收起 520 / 展开 720，收窄自动折叠、展开自动加宽）由其中的 `MainWindowSizingConfigurator` 维护。
- `apps/macos/HeySnap/Sources/Infrastructure/Settings/`：本地 `UserDefaults` 设置，包含截图后行为（自动保存 / 打开快速标注条 / 打开编辑器）、截图保存目录、截图保存格式、保存时是否把 Retina 截图缩到 1x、窗口截图背景和可自定义的快捷键；快捷键可清除（禁用），清除以 sentinel 值持久化，变更通过 `onShortcutsChange` 回调触发重新注册。
- `apps/macos/HeySnap/Sources/Infrastructure/HotKeys/`：Carbon `RegisterEventHotKey` 包装，默认注册 `Shift+Option+A` 当前屏幕截图和 `Shift+Option+S` 框选区域截图；支持按 action 注销，未提供快捷键的 action 会被取消注册。
- `apps/macos/HeySnap/Sources/Infrastructure/Logging/`：本地诊断日志，写入 `~/Library/Logs/HeySnap/HeySnap.log`。
- `apps/macos/HeySnap/Sources/Features/Capture/`：交互式截图选择 overlay（`AreaSelectionController`）。按框选热键后，在每块屏幕铺一层非激活 `NSPanel` overlay（`.nonactivatingPanel`，不把 HeySnap 拉到前台）：鼠标悬停时用 `WindowEnumerator` 感知光标下的 app 窗口并高亮描边，单击直接选中该窗口截图；按住拖动超过阈值则切换为手动矩形框选。`Esc` 取消。若 `General > After capture` 选择 `Show quick markup bar`，区域框选松手后 overlay 不关闭，而是原地保留选区、显示可拖动的现场工具条，并支持先在 overlay 上画矩形/圆形/线/箭头/高亮/文字占位/马赛克等临时标注；第一条标注产生后选区会锁定以保持标注坐标稳定；点击勾或按 Enter 会关闭 overlay、按选区截图、把 overlay 标注合成到结果里，并复制 PNG 到剪切板。非 quick markup 路径输出 `CaptureSelection`（`.window` / `.region` / `.cancelled`）交给 `AppDelegate` 路由。
- `apps/macos/HeySnap/Sources/Features/Editor/`：截图后编辑窗口，采用独立 AppKit window 和自绘 canvas，不复用 Preference 主窗口外观。窗口使用原生 `NSToolbar` 承载品牌、工具、全局样式、撤销/重做、复制和保存动作，避免把顶部操作区作为内容区里的假工具条；首次打开会按鼠标所在屏幕的可见区域居中，下方是棋盘格背景的可滚动图片画布；打开首帧会按当前编辑窗口自适应缩放，之后通过受控步进滚轮缩放、`Command+=` / `Command+-` 缩放、`Command+0` 重新适配窗口。当前支持选择/移动、带 start/control/end 三锚点的曲线箭头、文字、矩形、圆形、直线、高亮、马赛克遮挡、裁切、撤销/重做、复制和保存。棋盘格仅作为视图背景，复制/保存不会把棋盘格写入导出图片。编辑器只处理本地位图与标注状态，用户点击 Save 时才调用截图服务按设置写入保存目录。编辑器工具习惯（上次工具、颜色、线宽、箭头样式、文本 Normal/Filled、字号与填充色等）保存到 `~/Library/Application Support/HeySnap/EditorPreferences.json`，只存本地偏好，不保存截图内容或上传云端。
- `packages/HeySnapCore/Sources/HeySnapCore/Capture/`：ScreenCaptureKit 截图与导出，当前要求 macOS 26+；当前屏幕截图只截取鼠标所在屏幕，框选截图按用户选择的 rect 捕获，窗口截图按 `windowID` 用 `SCContentFilter(desktopIndependentWindow:)` 精确抓取（即使被遮挡也干净，且天然排除选择 overlay）。框选 overlay 和窗口枚举使用 AppKit 全局坐标（底左原点），进入 `SCScreenshotManager.captureScreenshot(rect:)` 前由 `CaptureCoordinateConverter` 按所在屏幕翻转成 ScreenCaptureKit 截图坐标（顶左原点），避免上下位置反截。窗口截图背景策略支持 `Transparent`、`Shadow`、`Solid Color`、`Wallpaper`：Transparent 保留窗口圆角外的透明像素，Shadow 在透明画布上扩出轻阴影，Solid Color 用系统窗口背景色做同尺寸底色合成，Wallpaper 用窗口区域截图作为底图近似桌面背景。热键路径按 `General > After capture` 路由：可直接按设置写入 Save location，可打开快速标注条，也可把捕获到的 `CGImage` 和捕获 scale 交给 app 层编辑器；直接保存方法仍保留为底层能力。`WindowEnumerator` 基于公开 API `CGWindowListCopyWindowInfo` 枚举 layer 0 的可见窗口并做命中测试，坐标从 Quartz 顶左原点翻转为 AppKit 底左原点，不依赖 Accessibility 或私有 CGS 符号。Core 层通过保存目录 provider、保存格式 provider、Retina 保存缩放 provider、窗口背景 provider 和日志闭包接收 app 层依赖，不直接依赖 `AppSettings` 或 `AppLogger`。保存格式支持显式 PNG/JPEG/WebP，也支持 Auto 候选格式集合；默认 Auto 候选为 PNG/JPEG，并按编码后体积阈值选择。若用户启用 `Resize retina screenshots`，Core 在保存/导出前按捕获 scale 用高质量插值把 2x Retina 结果缩到 1x，编辑器画布仍保留原始捕获分辨率。
- `scripts/build-macos-app.sh` 使用 `swiftc` 直接构建 `.build/macos/HeySnap.app`，签名后默认安装到 `~/Applications/HeySnap.app`，开发阶段统一从该路径打开以保持 TCC 身份稳定；只有显式传 `--build-only` 时才只保留 `.build` 产物。脚本默认优先使用 Team ID `J9P29FA5BX` 的 Developer ID Application 签名，和 release DMG 保持同一身份；找不到 Developer ID 时才回退 Apple Development / Mac Developer，最后才 ad-hoc。脚本支持 `--version` / `--bundle-version` 覆盖 bundle 版本，并通过 `HEYSNAP_CODESIGN_KEYCHAIN`、`HEYSNAP_CODESIGN_TIMESTAMP` 和 `HEYSNAP_CODESIGN_OPTIONS_RUNTIME` 支持 CI 导入 Developer ID 证书签名。构建机如安装 Homebrew `webp`，脚本会把 `libwebp.7.dylib` 和 `libsharpyuv.0.dylib` 复制到 `Contents/Frameworks`、修正 install name，并随 app 一起签名，供 WebP 导出使用。构建时若存在 `AppIcon.icns` 会一并拷入 `Contents/Resources`，配合 `Info.plist` 的 `CFBundleIconFile` 让 Dock/Finder 显示 app 图标。
- `scripts/build-macos-dmg.sh` 调用 app 构建脚本生成已签名 app，再组装 `dist/release/heysnap/HeySnap-<version>.dmg`。本地未显式设置 `HEYSNAP_CODESIGN_IDENTITY` 时，脚本优先选择当前 Keychain 里 Team ID `J9P29FA5BX` 的 `Developer ID Application` identity，避免 release DMG 误走 ad-hoc。`.github/workflows/release.yml` 在 push `v*` tag 时运行该脚本，创建或更新同 tag 的 GitHub Release asset；未配置 Developer ID / notary secrets 时降级为 ad-hoc signed DMG，配置齐全时执行 hardened runtime 签名、notarization 和 staple。
- `.apple/`：本地私密 Apple 发布材料目录，保存证书、私钥、CSR、notary API key 和历史 profile/export 参考，已被 `.gitignore` 忽略，不属于可提交源代码或文档真源。
- 应用图标以 `apps/macos/HeySnap/Resources/AppIcon.svg` 为唯一可编辑真源（macOS 圆角方板 + 抽象 S 光圈，单色中性）。`scripts/generate-app-icon.sh` 用 `rsvg-convert` + `iconutil` 从该 SVG 生成 `AppIcon.icns` 和一张 `AppIcon-preview.png`；不要手改 `.icns`，改图标只需编辑 SVG 后重跑生成脚本。

## 后续功能边界

- `Capture`：当前屏幕、区域、窗口、重复区域、延时截图。该层输出截图文件或图像结果，不负责编辑 UI。
- `ScrollingCapture`：滚动截图需要 Accessibility 权限、合成滚动事件、连续帧采样、位移估计和拼接，应作为独立 workflow，不塞进单帧 capture backend。
- `Editor`：当前已有第一版截图后编辑器。后续可继续补齐计数器、放大镜、聚光灯、OCR/QR、pin window、拖拽导出、背景/backdrop 与更完整的对象属性面板；这些能力仍应独立于截图获取逻辑。
- `OCR`：基于 Vision 的文字识别、复制和后续可能的 QR/条码识别，输入应是已捕获或导入的图片。
- `Library/History`：如果后续要保存截图历史、固定图片或最近截图，应独立于编辑和截图 backend。
- `Licensing/Distribution`：项目只做 macOS 本地应用，不需要登录；未来如采用 AGPL 或开源核心 + 商业付费版本，应把 license gate、更新分发、商业功能开关放在 app/distribution 层，不污染 core capture/editor/OCR 包。

## 开源默认约束

- 核心包优先保持本地、可审计、无网络依赖。
- 截图、OCR、编辑等处理默认在本机完成，不上传用户屏幕内容。
- 如果未来有商业版本，开源 core API 不应依赖闭源服务才能工作。
- 引入第三方依赖时优先选择 license 与 AGPL/商业双轨兼容的库，并同步更新 `docs/SUPPLY_CHAIN_SECURITY.md`。
