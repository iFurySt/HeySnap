## [2026-07-27 10:52] | Task: Add Sparkle update checks

### Execution Context

- **Agent ID**: `TRAE CLI`
- **Base Model**: `GPT-5`
- **Runtime**: `TRAE CLI`

### User Query

> 增加 Sparkle 自动检测版本更新机制，基于 GitHub Releases 检测；可以提醒用户手动更新，也可以让用户开启自动更新。

### Changes Overview

**Scope:** macOS app distribution, release workflow, and repo docs

**Key Actions:**

- **Sparkle integration**: Added an app-layer `UpdateController` backed by Sparkle 2 `SPUStandardUpdaterController`, started after app launch.
- **Preferences UI**: Added About-page controls for manual update checks, automatic background checks, and automatic downloads.
- **Build integration**: Added `scripts/prepare-sparkle.sh` to download Sparkle 2.9.4 with SHA-256 verification, embed `Sparkle.framework`, and sign nested Sparkle code in the app bundle.
- **Release appcast**: Added `scripts/generate-sparkle-appcast.sh` and updated `.github/workflows/release.yml` to generate signed `appcast.xml` after notarization/staple and upload it beside the DMG.
- **Docs sync**: Updated architecture, CI/CD, release, security, supply-chain, and user-visible release notes.

### Design Intent (Why)

Update delivery belongs in the app/distribution layer, not the screenshot core. Sparkle provides the expected macOS update UX, signed appcast validation, and automatic download/install behavior without hand-rolling GitHub API polling. GitHub Releases remain the source of release artifacts: the app reads a stable latest-release appcast URL, and the appcast points to the versioned DMG asset.

### Files Modified

- `.github/workflows/release.yml`
- `Makefile`
- `apps/macos/HeySnap/Resources/Info.plist`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `apps/macos/HeySnap/Sources/Features/Preferences/PreferencesView.swift`
- `apps/macos/HeySnap/Sources/Infrastructure/Updates/UpdateController.swift`
- `scripts/prepare-sparkle.sh`
- `scripts/generate-sparkle-appcast.sh`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/SECURITY.md`
- `docs/SUPPLY_CHAIN_SECURITY.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`
