# Orbit and Unified Integrations Implementation Plan

> **For agentic workers:** Execute with the already requested implement-spec workflow: isolated implementers, integration, two-axis review, and real application verification.

**Goal:** Make physical wheel scrolling immediately visible with animated folding, adjustable orbit distance/capacity, freely captured return origins, and measured performance improvements.

**Architecture:** Bubble artwork is presented by owned Core Animation layers instead of NSButton cell drawing. A single integration record offers optional observation and precise-return capabilities; any foreground application can provide an application-level return anchor. Geometry derives capacity from available arc length and fixed bubble diameter.

**Tech Stack:** Swift 6, AppKit, Core Animation, SwiftUI settings, local JSON registries, executable Swift checks.

---

## Settled scope

- Keep current Space behavior. Remove the unselected fresh-panel experiment; do not rework Space transitions.
- First captured anchor remains the origin throughout Agent-to-Agent visits. Generic app return remains explicitly application-level.
- Physical mouse acceptance remains required: the stable-slot and window-flush probes both failed. Input/model checks do not establish visible presentation.

## Task 1: Layer presentation, orbit geometry, and folding animation

**Files:** Sources/CharApp/CompanionPanel.swift; Sources/CharCore/CompanionGeometry.swift; Sources/CharCore/CompanionScrollPolicy.swift; Sources/CharCore/CompanionPreferences.swift; Tests/CharCoreChecks/main.swift.

- [x] Add a backward-compatible `bubbleDistance` preference, default 20 pt, clamped to 8...72 pt. Geometry API accepts this argument with the same default. Compute radius as pet half-size + bubble half-size + distance; keep all bubbles on-screen for each placement. Derive capacity from the 44 pt diameter plus a small separation using chord length; desktop uses a full orbit, edges use the existing inward arc. Increasing distance must increase capacity where geometry allows it.
- [x] Replace cell-backed bubble artwork with owned CGImage layers. Preserve click dispatch, stable AX identity, hover, gaze, drag, pass-through, and disabled preview behavior.
- [x] Animate the orbit at constant speed over approximately 180 ms. Primary bubbles move along the orbit; entering bubbles grow out of the overflow miniature, outgoing bubbles shrink into it. Retarget from presentation state on rapid/reverse input; reduced motion uses immediate positions. No cycling if count fits capacity.
- [x] Remove temporary OrbitTrace and CompanionSpaceProbe code; preserve default Space feedback. Root owns removal of Runtime.swift probe callers.
- [x] Move autonomous idle artwork motion to compositor animations; update gaze/hover only while changing, and custom skins only on frame changes. Hidden surfaces must not raster repeatedly.
- [x] Run `swift run char-core-checks` and `bash scripts/build-app.sh`; retain exact geometry/capacity and real driver-burst replay checks. Root will integrate fixture smoke and perform real mouse acceptance.

## Task 2: Unified integration capabilities and free origin capture

**Files:** Sources/CharCore/IntegrationPlugins.swift; Sources/CharPlatform/Platform.swift; Sources/CharApp/RuntimePlugins.swift; PluginSettingsView portion of Sources/CharApp/PluginSettingsView.swift; Tests/CharCoreChecks/main.swift; Tests/CharPlatformChecks/main.swift; docs/integration-plugin-format.md; CONTEXT.md; docs/adr/.

- [x] Decode existing manifests/registry records and tombstones without resetting user configuration. Replace public Agent/source category branching with optional observation and return-adapter capabilities. Keep old IDs and migrate legacy kind fields on read.
- [x] Show one integration list with capability descriptions. Multiple CLI clients may share Warp. Enforce one enabled observer per work end and one precise adapter per bundle; generic return requires no installed plugin.
- [x] Capture any foreground application except Char itself. Prefer an enabled precise adapter when available; otherwise retain process ID and bundle in an application-level anchor. Generic Agent origins, including Warp, must be capturable.
- [x] Preserve first anchor while visiting another Agent, including when the origin is an Agent. Preserve generic anchors when an observer is disabled; invalidate precise anchors if their required adapter disappears. Do not mark application-level attention navigation as exact.
- [x] Prove migration, shared-Warp records, generic origin capture/return, exact adapter removal, and first-anchor preservation through executable checks.
- [x] Update existing domain decision explicitly: the requested free capture supersedes the source allowlist in ADR 0005; ADR 0006 remains the harness ownership decision. No new chat-reading permissions or private Space APIs.
- [x] Run `swift run char-core-checks` and `swift run char-platform-checks` and commit the isolated implementation. Leave AppearanceSettingsView to root.

## Task 3: Runtime distance wiring and measured IO optimization

**Files:** Sources/CharApp/Runtime.swift; AppearanceSettingsView portion of Sources/CharApp/PluginSettingsView.swift; Sources/CharObservations/KimiObservationPoller.swift; Sources/CharObservations/LocalObservationPoller.swift; Tests/CharObservationChecks/main.swift; docs/companion-performance-2026-10-04.md.

- [x] Add the runtime property and setter using `companionPreferences.setBubbleDistance(value)`, persist it, re-layout the panel immediately, and publish the computed visible capacity beside the slider. Exercise minimum/default/maximum distance at all pet sizes and placements.
- [ ] Measure the current seven-bubble idle app with `python3 scripts/profile-char.py PID --seconds 20 --sample /tmp/char-orbit-before.sample.txt`; repeat on the integrated candidate in the same scenario. Record source revisions and setting/hover state.
- [x] Replace unnecessary broad Kimi file attributes with stat metadata while preserving inode replacement/truncation/partial-line semantics. Reduce repeated directory discovery only if measured evidence supports it and new session discovery remains bounded and tested.
- [x] Remove Runtime.swift fresh-panel probe callers and fixture probe checks, leaving current default Space feedback.
- [x] Run `swift run char-observation-checks`, then integrated `bash scripts/check.sh`, build, and fixture smoke. Root coordinates all GUI launches.

## Task 4: Integration and delivery evidence

**Files:** docs/spec.md; docs/companion-polish-verification-2026-10-04.md; docs/companion-performance-2026-10-04.md; existing PR #2.

- [x] Merge isolated commits, resolve shared test changes without dropping either behavior, and run the required checks once on the combined source.
- [x] Review Standards and Spec independently; fix concrete findings in one isolated fixer if needed.
- [ ] Run the app, inspect minimum/default/maximum orbit states, unified settings, menu/settings closure, animated scrolling, and Agent-origin return behavior. Ask for a physical mouse confirmation only after the changed presentation path is running. Space is left at the user's accepted current scope.
- [ ] Report measured CPU/RSS and remaining runtime gaps accurately. Update the existing draft PR; mark ready only when the critical physical mouse path is verified or the user explicitly accepts a reduced scope.

## Coverage check

1. Mouse presentation: task 1 + real verification task 4.
2. Distance and variable capacity: tasks 1 and 3.
3. Linear folding movement: task 1.
4. Unified origin/Agent integrations: task 2.
5. Performance implementation and measurement: tasks 1 and 3.

## Execution evidence

Implemented and reviewed through `4b4d7e0`; `3c7e62d` fixes a smoke fixture precondition only. Required checks passed on `098767f`; bounded review fixes compile and source re-review passed. Directory revision invalidation preserves next-poll discovery; the root symlink regression was found and fixed. Final release build, unlocked package smoke, and strict signature validation passed on `3c7e62d`.

The normal-mode unlocked 20-second sample on 2026-10-05 measured 5.75% of one core, RSS about 58.3 MiB, compared with the prior same-config 18.84% sequential sample. Cross-day data changes and combined implementation changes prevent per-component attribution. The seven-bubble candidate sample ended with the Mac locked and is excluded from unlocked comparisons. The prepared seven-observation isolated normal instance uses real platform navigation; settings/folding UI, physical mouse, and Agent-origin return remain pending manual unlock. The draft PR retains these gates. See `docs/orbit-verification-2026-10-04.md` and `docs/companion-performance-2026-10-04.md`.
