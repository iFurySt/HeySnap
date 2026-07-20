## [2026-07-20 22:16] | Task: configure release signing secrets

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 用 gh 配置 GitHub CI/CD，让 HeySnap 能在 GitHub Actions 里打包出 DMG，参考本地 agent-bar；Apple 签名材料在 `.apple/` 里。

### Changes Overview

**Scope:** GitHub Actions release workflow and repository release documentation

**Key Actions:**

- **GitHub secrets**: Configured Developer ID p12 and Apple notary secrets with `gh secret set`, using local `.apple/` materials without printing secret values.
- **Workflow fix**: Added the temporary signing keychain to the user keychain search list before resolving and using the codesign identity.
- **Docs sync**: Updated CI/CD documentation to record the CI keychain behavior.

### Design Intent (Why)

The release workflow imports the Developer ID certificate into a temporary CI keychain. Adding that keychain to the search list makes the imported identity visible to `codesign` during app and framework signing.

### Files Modified

- `.github/workflows/release.yml`
- `docs/CICD.md`
