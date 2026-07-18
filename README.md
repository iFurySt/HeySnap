# HeySnap

English version: [`HeySnap`](https://github.com/iFurySt/HeySnap)

## 简介

HeySnap 是一个面向 Agent 协作开发的基础仓库。它把协作规则、架构边界、执行计划、变更历史和发布记录都版本化在仓库里，让人和 Agent 可以围绕同一套本地上下文推进项目。

关于这套工作方式的来源，可以参考这篇文章：[日常Harness](https://www.ifuryst.com/blog/2026/daily-harness/)

## 如何使用

从 `AGENTS.md` 开始阅读仓库入口规则，再按任务类型进入 `docs/` 下的专题文档：

- `docs/REPO_COLLAB_GUIDE.md`：仓库协作、提交、文档同步与测试约定。
- `docs/ARCHITECTURE.md`：顶层结构和边界。
- `docs/HISTORY_GUIDE.md`：变更历史记录方式。
- `docs/PLANS_GUIDE.md`：复杂任务的 execution plan 维护方式。

当前仓库提供最小 release CI：push `v*` tag 后，GitHub Actions 会构建 macOS DMG 并上传到同 tag 的 GitHub Release。细节见 `docs/CICD.md` 和 `docs/releases/RELEASE_GUIDE.md`。

## macOS App

HeySnap 当前提供一个最小 macOS 截图 app：

- Preference 界面包含 `General`、`HotKeys`、`About` 三个侧边栏页面。
- 默认全局快捷键是 `Shift+Option+A` 截取当前鼠标所在屏幕，`Shift+Option+S` 框选区域截图；底层使用 Carbon `RegisterEventHotKey`。
- 截图基于 ScreenCaptureKit；`General > After capture` 可选择截图后自动保存到 Save location，或打开编辑器窗口再标注、复制和保存。
- `General` 里的保存位置、保存格式、Retina 保存缩放和窗口截图背景用于自动保存、编辑器 `Save` 动作及窗口截图处理，默认保存到 `~/Downloads`。
- app 图标以 `apps/macos/HeySnap/Resources/AppIcon.svg` 为矢量真源，构建时随 app 内置；改图标只需编辑该 SVG 后运行 `bash scripts/generate-app-icon.sh` 重新生成 `.icns`。
- 当前不包含登录、账号或云端同步能力。

构建并安装本地 `.app`：

```sh
make macos-app
```

开发阶段默认安装到 `~/Applications/HeySnap.app`，便于 Screen Recording 授权和日常运行使用同一个稳定路径。脚本会优先选择本机可用的 Developer ID Application 证书签名，和 release DMG 保持同一签名身份；没有 Developer ID 时才回退 Apple Development / Mac Developer，再没有可用证书时才回退 ad hoc。如需强制 ad hoc，可运行：

```sh
HEYSNAP_CODESIGN_IDENTITY=- make macos-app
```

只需要生成 `.build/macos/HeySnap.app` 而不安装时，可运行：

```sh
make macos-app-build-only
```

生成本地 DMG：

```sh
make macos-dmg
```

如果本机 Keychain 里有 `Developer ID Application` 证书，DMG 构建会优先用它签名；仓库本地可放一个被 gitignore 的 `.apple/` 目录保存证书、私钥和 notary 材料，不能提交。

打开开发期安装版：

```sh
make open-macos-app
```

改完 UI 或 app 代码后，先重新构建安装，再重启安装版，避免只是激活旧进程：

```sh
make macos-app
make restart-macos-app
```

HeySnap 运行时只允许同一 bundle identifier 保留一个实例；重复启动会激活已有窗口并退出新进程。开发验证不要使用 `open -n` 强开新实例。

产物路径：

```text
~/Applications/HeySnap.app
.build/macos/HeySnap.app
dist/release/heysnap/HeySnap-<version>.dmg
```

当前代码结构：

- `apps/macos/HeySnap/`：macOS app 壳、Preference UI、热键、设置和日志。
- `packages/HeySnapCore/`：与 UI 解耦的截图核心能力；编辑器等 app 交互能力放在 `apps/macos/HeySnap/`，后续滚动截图、OCR 等能力按边界继续拆分。

HeySnap 只做 macOS 本地应用，不需要登录。项目未来计划开源，license 可能采用 AGPL，或采用开源核心 + 商业付费版本的双轨模式；核心截图、编辑和 OCR 能力应默认本地可用。

## 许可证

[MIT](LICENSE)

## 备注

这套方法主要来自我们自己的持续实践和整理，同时也吸收了 OpenAI 在 [harness engineering 文章](https://openai.com/index/harness-engineering/) 中的一部分思路。
