# Appearance capabilities v2 Implementation Plan

> Execute inline in the current task. User authorization covers implementation, commit/push, and installation; actual custom-package acceptance remains with the user.

**Goal:** Keep v1 appearances compatible and let v2 packages customize rendering, sound, event-driven behavior, and installed icons through documented Char APIs.

**Architecture:** A validated declarative manifest supplies variants, layers, themes, bubble style, hit regions and behavior defaults. A persistent JavaScriptCore helper receives bounded JSON events and returns typed Char actions; it exposes no command, filesystem or network bridge. Rendering and geometry stay native; changing an installed icon uses a verified, recoverable bundle transaction.

**Tech Stack:** Swift/AppKit/Core Animation, JavaScriptCore, JSON, PNG, NSSound, codesign, universal macOS Release builds.

## 1. Schema and store

Files: `Sources/CharPlatform/PetSkinFeatures.swift`, `PetSkins.swift`, `Tests/CharPlatformChecks/PetSkinChecks.swift`.

- [x] Add optional `features` to `PetSkinManifest`; accept versions 1 and 2, keep v1's seven-clip contract and budgets.
- [x] Define typed variants (`clips`, `anchor`, `rotation`, `mirrorX`), themes, tracking layers, sound bindings, bubble style, hit regions, event bindings and behavior preferences.
- [x] Resolve base → edge variant → theme → theme edge variant. Validate every reference, numeric bound, action and event; reject unreferenced assets, path escapes and oversized packages.
- [x] Cache assets by package/path; named clips loop only when declared. Persist theme selection separately from immutable package resources.

## 2. Native rendering and events

Files: `Sources/CharApp/RuntimeAppearance.swift`, `RuntimePlugins.swift`, `CompanionPanel.swift`, `AppearanceSettingsView.swift`, `Runtime.swift`.

- [x] Resolve selected variant for every clip, including settled idle. Apply authored anchor/mirroring/rotation consistently.
- [x] Render eye overlays with bounded gaze displacement and pointer-direction head overlays. Quantize gaze keys so stationary frames reuse raster images.
- [x] Read shell/status/font/CLI/hover/shatter/orbit styling from the resolved theme. Keep Agent identity independent from shell resources.
- [x] Dispatch `select`, `theme`, `hoverEnter`, `hoverLeave`, `dragStart`, `dragEnd`, `click`, `attention`, `return`, `placement` only at transitions, without conversation contents.
- [x] Route typed actions `playClip`, `setTheme`, `playSound`, `setPlacement`, `returnHome`, `showSettings`, `cycleBubbles` on the main actor. Apply package behavior defaults without overwriting user preferences.
- [x] Honor mute/Reduce Motion. Apply hit regions, drag collision mode, focus following, return policy, layout preferences. Add bilingual theme selection.

## 3. Script helper

Files: `Sources/CharAppearanceScript/main.swift`, `Sources/CharApp/AppearanceScriptHost.swift`, `Package.swift`, release/build scripts and CI.

- [x] Define JSONL `init`/`event` requests with request IDs; reply with validated action arrays or errors.
- [x] Load UTF-8 JavaScript in a JSContext with only `onEvent(event)` and JSON data. No native object bridge. Keep one helper per selected package.
- [x] Serial background I/O, bounded payload/action count, request deadline and process termination on timeout; selection/delete shuts down previous helper.
- [x] Test stateful events, exceptions, invalid actions and infinite-loop timeout. Pure manifests require no helper.

## 4. Installed icon

Files: `Sources/CharPlatform/InstalledAppearanceIcon.swift`, runtime icon integration and tests.

- [x] Probe a disposable signed bundle; use PNG-derived ICNS resource plus `CFBundleIconFile`, re-sign and strictly verify the staged bundle.
- [x] Keep a pristine Release archive outside application discovery; stage on the installation filesystem, atomic swap with rollback, register LaunchServices. Serialize/coalesce latest requested icon; no writes per animation frame.
- [x] Default selection/delete restores pristine icon. Show failure in settings if installation is not writable. Preserve a single installed Char and record signature/permission implications accurately.

## 5. SDK, verification and delivery

Files: `docs/pet-skin-format.md`, `docs/appearance-development.md`, `docs/appearance-customization.md`, `Resources/Skins/AGENTS.md`, `docs/development-prompts.md`, `docs/plugin-user-acceptance.md`.

- [x] Supply full generic v2 field/API reference and examples for independent edge art, tracking, bubble styling, theme, sound and scripts. The developer reads SDK docs rather than exploring host source.
- [x] Keep a minimal basic-check gate; final report gives complete GUI acceptance steps. Do not install a user-developed package or make model requests during development.
- [x] Build and run focused platform/script/runtime checks; inspect actual isolated native rendering and theme switching. Reuse v1 edge regression evidence.
- [ ] Commit explicit implementation/docs files, push, produce Release artifacts and install downloaded Release. Required project gates and focused native checks passed locally.

## Acceptance and performance

`swift run char-platform-checks` covers package contract/cache/budget/icon transactions; `swift run Char --smoke --appearance-v2-check` covers native variants/tracking/theme/actions and script isolation. A v1 package must still import, select and render at all edges. Idle scripts receive no frame ticks; gaze is native and quantized; themes reuse referenced assets; sounds have cooldown; decoded image budget remains bounded. User acceptance covers visible four-edge behavior, pointer tracking, actual audio, interactions and Finder/Launchpad refresh on their system.

## Phase 1 evidence

PR #21 merged at `58a093c`; v0.2.2 CI passed required checks and universal ZIP/DMG gates. Actual custom-package native regression failed before the orientation fix and passed after it at desktop/four edges and 36/48/88pt. Release installation follows checksum/signature verification.
