# 供应链安全

这份文档记录 HeySnap 当前的供应链安全状态，以及后续接入真实技术栈后应补齐的能力。

## 当前状态

HeySnap 当前有 GitHub Actions release workflow，会按 `v*` tag 构建 macOS DMG 并上传到 GitHub Release；尚未接入供应链扫描、SBOM 或 release provenance。

当前 macOS app 构建脚本会在本机存在 Homebrew `webp` 时，把 `libwebp.7.dylib` 和 `libsharpyuv.0.dylib` 复制到 app bundle 的 `Contents/Frameworks`，用于 WebP 截图导出。这是运行时依赖，不通过 SwiftPM 管理；发布前需要固定来源版本、记录 license，并把对应 NOTICE/SBOM 纳入 release 产物。

保留的默认约束是：

- 不提交密钥、令牌或本地私有配置。
- `.apple/` 是本地 Apple 证书、私钥、notary API key 和 profile/export 材料目录，必须保持 ignored；提交前应确认没有把其中内容复制到可追踪文件。
- 接入真实依赖后，必须提交可审计的依赖清单和 lockfile。
- GitHub Actions 应固定到不可变的 commit SHA，而不是漂移的版本标签；当前 release workflow 已固定 `actions/checkout` 和 `actions/upload-artifact`。
- 未来计划开源，license 可能采用 AGPL 或开源核心 + 商业付费版本双轨；新增依赖前必须确认 license 与该方向兼容。

## 后续可接入的工具

- `actions/dependency-review-action`：审查 PR 依赖变更。
- `google/osv-scanner-action`：扫描已知开源漏洞。
- `anchore/sbom-action`：生成 SPDX 格式的 SBOM。
- `actions/attest-build-provenance`：为 release artifact 生成签名 provenance。

## 限制和前提

- Dependency Review 在 public repo 可以直接使用；private repo 通常需要 GitHub Advanced Security 或对应的代码安全能力。
- 当前没有自动化依赖审计、SBOM 或 provenance 产出。
- 供应链能力需要在 HeySnap 技术栈确定后重新接入。
- OpenSSF Scorecard 默认不启用，因为 HeySnap 还没有真实分支保护、release 历史和 SAST 姿态可以评分；等仓库规则配置完成后再按需加回。

## 后续建议继续做的事

- 锁定并提交项目真实依赖的 lockfile。
- 让构建过程尽量可重复、可验证。
- 为 macOS app 生成 release 包前补齐第三方依赖 license 清单和 NOTICE。
- 如果条件允许，在部署链路里增加对 provenance 的校验。
- 把 attestation 校验继续下沉到部署平台或准入层。
