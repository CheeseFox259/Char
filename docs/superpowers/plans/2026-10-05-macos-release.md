# macOS Release Implementation Plan

> Execute platform/release inline, independent settings and bubble tasks in their own existing clean worktrees under implement-spec; integrate and review before publication.

**Goal:** Publish a usable v0.1.0 macOS application with reliable login/focus behavior, click dismissal, bilingual concise settings and matching feedback symbols.

**Architecture:** Keep existing native app and observation modules. Separate display geometry from permission-dependent AX, use ServiceManagement registration as the source of login state, dismiss successfully visited attention independently from navigation precision, and share visual symbols across settings/companion.

**Tech Stack:** Swift/AppKit/SwiftUI/Core Animation, ServiceManagement, SPM; GitHub release ZIP/DMG and SHA256.

---

## Frontier

- Platform: Sources/CharPlatform/LoginItem.swift, WorkspaceRuntime.swift; tests in CharPlatformChecks. Root diagnoses current native status and repairs ServiceManagement notFound handling plus permission-independent focused-display geometry. Completes before installed-runtime verification.
- Settings: Sources/CharCore/Settings.swift; Sources/CharApp/SettingsView.swift, PluginSettingsView.swift, StatusBarController.swift, localization helper and bounded Runtime status text. Independent; language defaults from system, selection persists and applies immediately. Remove explanatory paragraphs, keep concise control labels/errors/help. Use common scope/macwindow/unavailable symbols in legend and product.
- Bubble: AttentionRouter visit completion, Runtime.visit, CompanionPanel burst renderer and meaningful checks/docs. Independent; exact and application fallback successful visits dismiss the clicked attention item; unavailable retains it. Running-only bubble behavior is explicitly accounted for. Burst uses bounded short-lived image fragments, transform/opacity, Reduce Motion alternative.
- Release: blocked by all above. scripts/build-app.sh and new package script produce versioned macOS app, ZIP/DMG/SHA256; verified architecture/minimum OS, signing truth and installation steps. Native login and focus paths verified from installed app. Tag verified release commit and publish assets to CheeseFox259/Char, update PR #2.

## Completion checks

- [x] Current UI records actual login/AX state; red-capable platform checks catch the bug before fix.
- [x] Focus tracking works without AX where window geometry is available; largest-overlap display handles spanning windows. No content/title capture.
- [x] Login enable/disable follows real ServiceManagement state and does not reject first registration; app bundle is registered/installed correctly.
- [x] Successful left-click visits clear one item and play a burst; failure retains retry; old precision/attention domain docs updated.
- [x] 中文/English setting persists/reloads, settings/menu/dialogs/status labels match selection; shared feedback symbols and compact layout verified.
- [x] scripts/check.sh, release build, native smoke, targeted interaction/animation checks and signature pass.
- [x] Installed app focus/login and visible UI checked; source fixtures not represented as native integration acceptance.
- [x] ZIP/DMG extraction/resource/signature/version/hash checks pass; GitHub release assets/tag verified remotely.
