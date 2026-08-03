# 稳定性与可运维性

这里用来定义项目的运行质量底线。

## 当前 macOS 验证入口

- `make macos-app`：编译 Swift sources，组装 `.build/macos/HeySnap.app`，签名后复制到 `/Applications/HeySnap.app`；开发阶段统一从该路径打开，用于稳定 Screen Recording 授权和真实运行。未显式设置 `HEYSNAP_CODESIGN_IDENTITY` 时优先使用 Developer ID Application 签名，找不到时才回退 Apple Development / Mac Developer。
- `make install-macos-app`：`make macos-app` 的同义入口，保留给需要显式表达安装动作的脚本或历史命令。
- `make macos-app-build-only`：只生成 `.build/macos/HeySnap.app`，不覆盖 `/Applications/HeySnap.app`。
- `make macos-dmg`：生成 `dist/release/heysnap/HeySnap-<version>.dmg`，用于本地验证 release 打包路径。
- `HEYSNAP_CODESIGN_IDENTITY=- make macos-app`：强制 ad hoc 签名，仅用于不关心 TCC 稳定性的临时构建；正常开发不要用它，避免破坏 Screen Recording 授权稳定性。
- `make open-macos-app`：打开 `/Applications/HeySnap.app`。不要使用 `open -n` 强开新实例；HeySnap 运行时会激活已有实例并退出重复启动的新进程。
- `make restart-macos-app`：结束现有 `HeySnap` 进程并重新打开 `/Applications/HeySnap.app`。每次改完 UI 或 app 代码并完成 `make macos-app` 后，都应重启安装版，避免只激活旧进程导致验证的不是最新构建。
- `codesign --verify --deep --strict --verbose=2 /Applications/HeySnap.app`：验证开发期实际运行 bundle 的签名和 sealed resources。
- `plutil -lint /Applications/HeySnap.app/Contents/Info.plist`：验证 app bundle metadata。
- `hdiutil verify dist/release/heysnap/HeySnap-<version>.dmg`：验证 release DMG 镜像 checksum。
- `open /Applications/HeySnap.app`：本地启动 Preference 窗口；ScreenCaptureKit 权限弹窗、真实截图、编辑器打开、复制和保存需要在可交互桌面里验证。
- 滚动截图从框选截图的 quick markup bar 触发；第一版只支持手动滚动。真实验证时应覆盖一个原生滚动视图或网页：进度浮窗显示期间由用户滚动目标内容，停止滚动后应自动完成拼接并打开 Editor。
- `~/Library/Logs/HeySnap/HeySnap.log`：记录 app 启动、Carbon hotkey 注册、热键触发、截图开始、编辑器打开、保存和失败原因。

## 后续建议维护的内容

- 启动、健康检查和基本可用性要求。
- 日志、指标、链路的采集和访问约定。
- timeout、retry、backoff 的默认策略。
- 本地以及后续流水线中的关键路径验证方式。
- 常见故障、排查路径和恢复步骤。

CI/CD 状态和后续接入方式，统一写在 `docs/CICD.md`。
