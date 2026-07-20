# CI/CD 说明

HeySnap 当前有一条最小真实 release workflow，用于按 git tag 构建 macOS DMG 并上传到 GitHub Release。

## 当前状态

- Release workflow：`.github/workflows/release.yml`
- 触发方式：push `v*` tag，例如 `v0.1.0`
- 本地产物入口：`make macos-dmg` 或 `./scripts/build-macos-dmg.sh --version 0.1.0`
- 本地 app 构建入口：`make macos-app`，会生成 `.build/macos/HeySnap.app` 并安装到 `~/Applications/HeySnap.app`。开发阶段统一打开安装路径，以保持 TCC 身份稳定；本地默认签名优先使用 Developer ID Application，找不到时才回退 Apple Development / Mac Developer。
- CI 产物路径：`dist/release/heysnap/HeySnap-<version>.dmg`
- GitHub Release：tag push 后 workflow 会创建或更新同 tag release，并上传 `HeySnap-<version>.dmg`。
- 本地 `.apple/` 目录用于保存证书、私钥、notary API key 等 Apple 发布材料，已被 `.gitignore` 忽略，不能提交。

PR gate、依赖扫描、SBOM 和 provenance 还没有接入。

## 签名与公证

workflow 支持两档模式：

- 未配置签名 secrets：构建 ad-hoc signed app，跳过 notarization，仍上传 DMG 作为 CI 可验证产物。
- 配置 Developer ID 和 Notary secrets：使用 Developer ID Application 签名、启用 hardened runtime 和 timestamp，再对 DMG 执行 notarization 与 staple。

本地 `scripts/build-macos-dmg.sh` 和 `scripts/build-macos-app.sh` 在未显式设置 `HEYSNAP_CODESIGN_IDENTITY` 时，都会优先使用当前 Keychain 中 Team ID `J9P29FA5BX` 的 `Developer ID Application` identity；找不到时 app 构建才回退到 Apple Development / Mac Developer。
CI 会把导入 p12 的临时 keychain 放进 user keychain search list，再解析和使用 codesign identity，避免 runner 上 `codesign` 找不到刚导入的证书。

签名 secrets：

- `HEYSNAP_CODESIGN_P12_BASE64`：Developer ID Application `.p12` 的 base64。
- `HEYSNAP_CODESIGN_P12_PASSWORD`：`.p12` 密码。
- `HEYSNAP_CODESIGN_KEYCHAIN_PASSWORD`：临时 keychain 密码，可选。
- `HEYSNAP_CODESIGN_IDENTITY`：证书名称，可选；不填时从导入的 keychain 自动解析。

公证配置：

- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_DEVELOPER_TEAM_ID`：可放 repo variable 或 secret；当前团队是 `J9P29FA5BX`。

## Release 流程

1. 确认本地构建和测试通过。
2. 更新用户可见 release note 与 history。
3. 打 tag：`git tag -a v0.1.0 -m "v0.1.0"`。
4. 推送：`git push origin main && git push origin v0.1.0`。
5. 检查 Actions 和 GitHub Release asset：`gh release view v0.1.0 --json assets,body,url`。

更完整的发版检查见 `docs/releases/RELEASE_GUIDE.md`。

## 后续补强

- 增加 PR gate，运行 `swift test` 和 macOS app build smoke。
- 为 release 产物补 SBOM、第三方依赖 license/NOTICE 和 provenance。
- 如果 workflow 失败暴露出新的流程坑，直接补回本文件或 release guide。
