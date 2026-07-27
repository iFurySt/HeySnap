# 发版指南

这份文档约束 HeySnap 的 macOS DMG release 流程。

## 什么时候必读

- bump 版本
- 打 release tag
- 推送 release tag
- 排查 GitHub Actions release 失败
- 重新发布某个 tag 的 DMG

## 当前 release 入口

- 本地构建 DMG：`./scripts/build-macos-dmg.sh --version <version>`
- 本地生成 Sparkle appcast：`./scripts/generate-sparkle-appcast.sh --version <version>`
- Makefile 入口：`make macos-dmg`
- CI workflow：`.github/workflows/release.yml`
- 用户可见发布记录：`docs/releases/feature-release-notes.md`

## 版本来源

CI 以 git tag 作为 release 版本源：

- tag `v0.1.0` 会生成 `HeySnap-0.1.0.dmg`
- app bundle 的 `CFBundleShortVersionString` 会写成 `0.1.0`
- app bundle 的 `CFBundleVersion` 默认使用 GitHub Actions run number
- Sparkle appcast 会发布为同一个 GitHub Release 下的 `appcast.xml`，app 内固定读取 latest release asset：`https://github.com/iFurySt/HeySnap/releases/latest/download/appcast.xml`

本地没有精确 tag 时，`scripts/build-macos-dmg.sh` 默认使用 `0.0.0-dev`；正式 release 应显式传 `--version` 或从 tag checkout 运行。

## Release Checklist

1. 更新用户可见记录：

   - `docs/releases/feature-release-notes.md`
   - 本轮对应的 `docs/histories/YYYY-MM/YYYYMMDD-HHmm-*.md`

2. 本地验证：

   ```sh
   swift test --package-path packages/HeySnapCore
   ./scripts/build-macos-dmg.sh --version 0.1.0
   ./scripts/generate-sparkle-appcast.sh --version 0.1.0
   ```

   本机如已导入 `Developer ID Application: Yifan PANG (J9P29FA5BX)`，DMG 脚本会优先用该 identity 签名；本地证书、私钥、Sparkle EdDSA private key 和 notary API key 可放在 ignored `.apple/` 目录，不要提交。

3. 检查产物：

   ```sh
   test -f dist/release/heysnap/HeySnap-0.1.0.dmg
   test -f dist/release/heysnap/appcast.xml
   hdiutil verify dist/release/heysnap/HeySnap-0.1.0.dmg
   xmllint --noout dist/release/heysnap/appcast.xml
   ```

4. 提交 release 准备变更。

5. 打 tag 并推送：

   ```sh
   git tag -a v0.1.0 -m "v0.1.0"
   git push origin main
   git push origin v0.1.0
   ```

6. 检查 GitHub Release：

   ```sh
   gh release view v0.1.0 --json assets,body,url
   ```

## CI secrets

未配置 secrets 时，workflow 仍会构建 ad-hoc signed DMG 供验证，但不会得到可直接面向普通用户分发的 Developer ID notarized 产物。

Developer ID 签名：

- `HEYSNAP_CODESIGN_P12_BASE64`
- `HEYSNAP_CODESIGN_P12_PASSWORD`
- `HEYSNAP_CODESIGN_KEYCHAIN_PASSWORD`（可选）
- `HEYSNAP_CODESIGN_IDENTITY`（可选）

Apple notarization：

- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_DEVELOPER_TEAM_ID`

`APPLE_DEVELOPER_TEAM_ID` 也可以放 repo variable；当前 HeySnap App ID 所属团队是 `J9P29FA5BX`。

Sparkle appcast：

- `HEYSNAP_SPARKLE_ED_PRIVATE_KEY`

本地默认读取 ignored `.apple/sparkle_ed_private_key`。CI 中必须配置 `HEYSNAP_SPARKLE_ED_PRIVATE_KEY`，否则 `Generate Sparkle appcast` 会失败，避免发布一个无法被 app 验签的更新源。

## Release 失败时怎么查

```sh
gh run list -R iFurySt/HeySnap --limit 10
gh run view -R iFurySt/HeySnap <run-id> --log-failed
```

常见问题：

- Swift 编译失败：看 `Build HeySnap DMG`。
- `codesign` 找不到 identity：确认 `.p12` secret 是否导入成功，或 `HEYSNAP_CODESIGN_IDENTITY` 是否与证书名称一致。
- notarization 被跳过：确认四个 `APPLE_NOTARY_*` 配置是否齐全，且 app 不是 ad-hoc 签名。
- appcast 生成失败：确认 `HEYSNAP_SPARKLE_ED_PRIVATE_KEY` 已配置，或本地 `.apple/sparkle_ed_private_key` 存在且内容是 Sparkle EdDSA private key。
- GitHub Release asset 没上传：确认 workflow 是 tag push 触发，不是手动 `workflow_dispatch` 触发；正式 release 应包含 DMG 和 `appcast.xml` 两个 asset。
