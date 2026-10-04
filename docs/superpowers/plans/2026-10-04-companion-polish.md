# Companion Polish Implementation Plan

> **For agentic workers:** Execute the existing implement-spec workflow task by task. Use the named implementer for its isolated worktree; the root handles runtime wiring and final native verification.

**Goal:** Resolve the user's nine visual/interaction corrections, measure actual CPU cost, and deliver an evidence-based performance plan.

**Architecture:** Preserve observation and Hold contracts. Share one placement and normalized position across displays; keep size in companion preferences. The surface owns compact geometry, glass artwork, gaze/hover, deliberate wheel input, and short local Space feedback. A menu-bar controller exposes the same runtime actions and three display status groups; native reason data remains intact.

**Tech Stack:** Swift 6, AppKit, Core Animation, SwiftUI settings, executable SwiftPM checks, native macOS sample/ps and CUA.

---

## 1. Compact rendering and interaction

Files: `Sources/CharApp/CompanionPanel.swift`, `Sources/CharCore/CompanionGeometry.swift`, `Tests/CharCoreChecks/CompanionGeometryChecks.swift`.

- [ ] Use `petFrame(placement:petSize:)` and `layout(count:offset:placement:petSize:)`, default 48 pt pet, 44 pt bubbles, compact orbit; test all four physical edge clips for 36/48/88 pt sizes. Keep event bounds stable during deformation.
- [ ] Remove default pet appendages. Scale default authored 76 pt drawing to the configured frame. Add an inward-facing, tilted, rounded peek pose with gaze, rather than leaving the face cut down the middle.
- [ ] Draw neutral translucent glass; enlarge the existing official app icon, add a dark rounded terminal badge to CLI work ends. Display one prominent status/count pill: interaction, issue, or turn ended. Preserve precise reasons in accessibility and menu text.
- [ ] Follow nearby bubbles with softly damped eyes; hovered bubble gets a brief spring lift/scale and brighter rim. Cache base artwork; do not redraw the whole canvas.
- [ ] Ignore wheel and next/previous when `count <= 6`. Accumulate precise wheel delta to 36 pt, one step per 180 ms, ignore momentum and reset after 250 ms inactivity; discrete wheels step once per throttle. Check the gate through a pure input policy.
- [ ] Expose `spaceFeedback()` on the surface. It plays short tuck/peek feedback without operating the system compositor. Default migration phases become 90/150 ms; authored custom clips retain their full duration.

## 2. Preferences, cross-display timing, menu bar

Files: `Sources/CharApp/CompanionPreferences.swift`, `Sources/CharApp/Runtime.swift`, `Sources/CharApp/RuntimePlugins.swift`, `Sources/CharApp/PluginSettingsView.swift`; new `Sources/CharApp/StatusBarController.swift` and shared core presentation/input policy if needed.

- [ ] Decode old companion preferences while dropping per-display state. Persist `{placement, petSize, normalizedX, normalizedY}`; default 48, clamp 36...88. Add an accessible size slider and reset.
- [ ] Keep the same edge and normalized coordinate on every screen. Calculate the physical frame from one global state; clamp full bubble targets into the visible area. Move tracking out of the 500 ms observation tick; use a 150 ms focus/display check plus workspace activation notification. Observation polling stays 500 ms.
- [ ] On `activeSpaceDidChangeNotification`, call surface feedback; do not reposition or overwrite the shared state solely because Space changed. Register/remove workspace observers with runtime lifetime.
- [ ] Add a template menu-bar square-face icon and menu for settings, return home, mute, show pet, status groups and quit. Aggregate display status only; no change to detection or attention sorting.
- [ ] Run existing core checks and package smoke, extend smoke to size persistence/global placement contracts and menu controller state where the actual seam allows it.

## 3. Performance analysis and bounded fixes

Artifacts: `/tmp/char-polish-performance-baseline.md`, `docs/companion-performance-2026-10-04.md`.

- [ ] Measure actual running Char with a short CPU-time delta and native `sample`; record build, fixture/normal mode, bubble count and settings state. Separate sample stack weight from CPU-time cost; do not invent precise component percentages.
- [ ] Rank hypotheses: continuous AppKit redraw/layer commits; repeated workspace/accessibility preference reads; observation/focus IO. Compare normal idle and seven-bubble demo under the same unlocked environment.
- [ ] Apply only measured high-cost fixes that preserve animation, gaze and click-through. Prefer Core Animation idle transforms, cached motion preferences, and change-only pointer/hit state; verify with the same sample loop.
- [ ] Report measured before/after and a prioritized follow-on plan with cost, expected effect, proof command and remaining limitations.

## 4. Integration and delivery

- [ ] Merge the renderer implementer into `feat/char-v1`; inspect all changed callers and fix integration errors.
- [ ] Run `scripts/check.sh`, `scripts/build-app.sh`, `build/Char.app/Contents/MacOS/Char --smoke`, strict codesign, diff check. These commands must pass; injected navigation is not native return evidence.
- [ ] Use CUA on the built app for glass/CLI marker, compact sizing slider, edge pose, hover, menu bar and cycle. Record genuine event/tool limitations for Space/multi-display/wheel, and request one bounded manual check only if needed.
- [ ] Update visual/spec/evidence docs and existing PR. Repeat required two-axis review on the affected diff, resolve findings in the single implementer. Restore normal passive instance and archive the implementer worktree after completion.

## Coverage decisions

The menu bar uses three presentation groups: attention (question/approval/unclassified; neutral label “需关注” so an unclassified stop does not imply confirmed interaction), issue (failure/rate limit/context exhausted), and turn ended. Precise native categories and recovered/unviewed semantics remain available through accessible descriptions. The existing #15 whole-screen request remains deferred; this task implements the user's new local pet feedback alternative.
