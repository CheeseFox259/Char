# Developer docs and capability icons Implementation Plan

> Execute inline in the current authorized task. Keep PR #2 and the user's accepted Space behavior. No Windows implementation or release publication is requested.

**Goal:** Show integration capabilities as icons, remove the obsolete work-end legend, document executable extension workflows and Windows feasibility, and push the verified branch.

**Architecture:** Keep configuration-only integration packages and data-only pet packages. Add a small CLI that invokes the existing production stores/validator in temporary storage. Documentation links the current implementation and distinguishes reuse from new adapter development.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Package Manager; Markdown; Microsoft/Swift/Warp primary documentation for Windows assessment.

---

### Task 1: Settings
Files: Sources/CharApp/PluginSettingsView.swift, Sources/CharApp/SettingsView.swift.
- [x] Replace row capability text with SF Symbols: bell.fill for observation, scope for configured exact return, macwindow for application return. Use fixed icon slots, help and accessibility names; exact means configured capability, not current permission status.
- [x] Remove only the obsolete WorkEnd.allCases legend grid. Retain the current status/navigation legend.
- [x] Build, open native settings, inspect row alignment, accessible names and remaining legend. No tests mirroring these static views.

### Task 2: Usable package validation
Files: Package.swift, Sources/CharPackageCheck/main.swift.
- [x] Add char-package-check, accepting integration or skin and a directory path.
- [x] Skin uses PetSkinStore.validatePackage. Integration imports into a disposable IntegrationPluginStore with built-in observers disabled. Delete temporary storage on exit; never access the user's registry.
- [x] Run both complete bundled samples; require nonzero for malformed manifests and usage errors. Explain that actual catalog conflicts remain checked at UI import.

### Task 3: Developer guides and copyable prompts
Files: docs/plugin-development.md, docs/appearance-development.md, docs/development-prompts.md; existing format pages.
- [x] Describe format fields, limits, current protocol/adapter boundaries, installation, conflict resolution, lifecycle and rollback.
- [x] Include complete configuration-package, new-protocol/source-contribution and pet-package prompts with concrete defaults, exact file pointers, commands and pass/fail criteria.
- [x] Validate examples with the CLI; review against production decoder and renderer. Correct current import-selection prose.

### Task 4: Current documentation
Files: docs/README.md, docs/architecture.md, README.md.
- [x] Index usage, mechanisms, formats, developer prompts, performance and accepted limitations.
- [x] Explain observation EOF baseline, generation gating, attention routing, first anchor, fallback, native UI and animation/cache paths. Cite source files and existing measurements.
- [x] Summarize measured CPU/RSS with scenario/version and limits; keep optimization proposals separate from implemented work. Correct stale split-list and Warp-origin claims in README.

### Task 5: Windows assessment
File: docs/windows-feasibility.md.
- [x] Verify Windows Swift, Win32 activation/hotkeys/layered windows, virtual desktop API, DPI and WSL using official documentation.
- [x] Inventory ImageIO/AppKit/Darwin/bundle-ID/socket dependencies. Compare shared Swift core plus native shell with a C# rewrite; give a staged spike and acceptance gates.
- [x] State source assessment only: no Windows machine build or runtime pass, no invented portability percentage or guaranteed precise navigation.

### Task 6: Verification and delivery
- [x] Run scripts/check.sh, release build, both package validations, native smoke and strict codesign.
- [x] Use CUA for actual settings and icon/legend check. Record the checks actually run.
- [x] Finish remote delivery: authentication refreshed; feat/char-v1 pushed, PR #2 updated. No merge or release publication.

Execution evidence: docs/developer-docs-verification-2026-10-05.md. Complete smoke was run twice and FAILED at the existing Space assertion; it is not counted as success.

Follow-up: concrete task prompts were replaced by three generic subordinate AGENTS.md on user request; motion changes and final successful smoke are recorded in docs/motion-verification-2026-10-05.md.
