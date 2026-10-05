# Companion Polish Implementation Plan

> **For agentic workers:** Execute the existing implement-spec workflow task by task. Use the named implementer for its isolated worktree; the root handles runtime wiring and final native verification.

**Goal:** Resolve the user's nine visual/interaction corrections, measure actual CPU cost, and deliver an evidence-based performance plan.

**Architecture:** Preserve observation and Hold contracts. Share one placement and normalized position across displays; keep size in companion preferences. The surface owns compact geometry, glass artwork, gaze/hover, deliberate wheel input, and short local Space feedback. A menu-bar controller exposes runtime actions; bubbles use three display status groups; native reason data remains intact.

**Tech Stack:** Swift 6, AppKit, Core Animation, SwiftUI settings, executable SwiftPM checks, native macOS sample/ps and CUA.

---

## 1. Compact rendering and interaction

Files: `Sources/CharApp/CompanionPanel.swift`, `Sources/CharCore/CompanionGeometry.swift`, `Tests/CharCoreChecks/CompanionGeometryChecks.swift`.

- [x] Use `petFrame(placement:petSize:)` and `layout(count:offset:placement:petSize:)`, default 48 pt pet, 44 pt bubbles, compact orbit; test all four physical edge clips for 36/48/88 pt sizes. Keep event bounds stable during deformation.
- [x] Remove default pet appendages. Scale default authored 76 pt drawing to the configured frame. Add an inward-facing, tilted, rounded peek pose with gaze, rather than leaving the face cut down the middle.
- [x] Draw neutral translucent glass; enlarge the existing official app icon, add a dark rounded terminal badge to CLI work ends. Display one prominent status/count pill: interaction, issue, or turn ended. Preserve precise reasons in accessibility text; the menu contains actions only.
- [x] Follow nearby bubbles with softly damped eyes; hovered bubble gets a brief spring lift/scale and brighter rim. Cache base artwork; do not redraw the whole canvas.
- [x] Ignore wheel and next/previous when `count <= 6`. Phased trackpads use a 6 pt first step then 36 pt, one step per 180 ms and ignore momentum; phase-less precise mouse bursts accept onset once, recognize 65 ms quiet, reversals and renewed peaks. Discrete wheels step once per throttle. Check the gate through a pure input policy.
- [x] Expose `spaceFeedback()` on the surface. It plays 700 ms local arrival feedback with zero initial velocity and a shared pet/bubble layer pose, without operating the system compositor or changing native window alpha. Default migration phases become 90/150 ms; authored custom clips retain their full duration.

## 2. Preferences, cross-display timing, menu bar

Files: `Sources/CharApp/CompanionPreferences.swift`, `Sources/CharApp/Runtime.swift`, `Sources/CharApp/RuntimePlugins.swift`, `Sources/CharApp/PluginSettingsView.swift`; new `Sources/CharApp/StatusBarController.swift` and shared core presentation/input policy if needed.

- [x] Decode old companion preferences while dropping per-display state. Persist `{placement, petSize, normalizedX, normalizedY}`; default 48, clamp 36...88. Add an accessible size slider and reset.
- [x] Keep the same edge and normalized coordinate on every screen. Calculate the physical frame from one global state; clamp full bubble targets into the visible area. Move tracking out of the 500 ms observation tick; use a 150 ms focus/display check plus workspace activation notification. Observation polling stays 500 ms.
- [x] On `activeSpaceDidChangeNotification`, call surface feedback; do not reposition or overwrite the shared state solely because Space changed. Register/remove workspace observers with runtime lifetime.
- [x] Add a template menu-bar square-face icon and menu for settings, return home, mute, show pet and quit (user later removed menu statistics). Aggregate bubble display status only; no change to detection or attention sorting. Settings exposes only a close button.
- [x] Run existing core checks and package smoke, extend smoke to size persistence/global placement contracts and menu controller state where the actual seam allows it.

## 3. Performance analysis and bounded fixes

Artifacts: `/tmp/char-polish-performance-baseline.md`, `docs/companion-performance-2026-10-04.md`.

- [x] Measure actual running Char with a short CPU-time delta and native `sample`; record build, fixture/normal mode, bubble count and settings state. Separate sample stack weight from CPU-time cost; do not invent precise component percentages.
- [x] Rank hypotheses: continuous AppKit redraw/layer commits; repeated workspace/accessibility preference reads; observation/focus IO. Compare normal idle and seven-bubble demo under the same unlocked environment.
- [x] Apply only measured high-cost fixes that preserve animation, gaze and click-through. Prefer Core Animation idle transforms, cached motion preferences, and change-only pointer/hit state; verify with the same sample loop.
- [x] Report measured before/after and a prioritized follow-on plan with cost, expected effect, proof command and remaining limitations.

## 4. Integration and delivery

- [x] Merge the renderer implementer into `feat/char-v1`; inspect all changed callers and fix integration errors.
- [x] Run `scripts/check.sh`, `scripts/build-app.sh`, `build/Char.app/Contents/MacOS/Char --smoke`, strict codesign, diff check. These commands must pass; injected navigation is not native return evidence.
- [ ] Use CUA on the built app for glass/CLI marker, compact sizing slider, edge pose, hover, menu bar and cycle. Record genuine event/tool limitations for Space/multi-display/wheel, and request one bounded manual check only if needed.
- [ ] Update visual/spec/evidence docs and existing PR. Repeat required two-axis review on the affected diff, resolve findings in the single implementer. Restore normal passive instance and archive the implementer worktree after completion.

## Coverage decisions

The menu bar uses three presentation groups: attention (question/approval/unclassified; neutral label “需关注” so an unclassified stop does not imply confirmed interaction), issue (failure/rate limit/context exhausted), and turn ended. Precise native categories and recovered/unviewed semantics remain available through accessible descriptions. The existing #15 whole-screen request remains deferred; this task implements the user's new local pet feedback alternative.

## Latest physical-feedback correction

User rejected the a930824 physical mouse first-step behavior and Space speed/bubble flicker. Captured one detent as 12 phase-less precise events; old policy accepted two steps. The actual replay was RED, the onset-only policy is GREEN. Candidate24b93aa is packaged and open for final physical retest; shared parent-layer animation and a700 ms zero-velocity spring are implemented. Native CUA screenshot, core checks, package smoke and strict signature passed. Physical first-frame and actual Space quality remain pending; cleanup, final performance capture and PR readiness follow that evidence.

Final-candidate follow-up:250 ms quiet incorrectly swallowed consecutive physical detents; captured continuation/reversal regression is now GREEN with65 ms, direction and peak onset detection. Space appearance belongs to observed hide/show cycles, not delayed workspace notices. Review found a rapid-second-Space interruption edge; its focused fix is in progress. Physical retest is pending.

Display-deferral investigation remains open: actual mouse continues one visual step behind until pointer exit after the input-count fixes. NSWindow flush A/B also failed. Candidate5f6011b fixes physical control slots and rebinds content/AX/click identities; actual surface smoke passed, physical result pending. Space public occlusion is not a reliable first-pixel boundary; opt-in740c583 prepared-new-panel probe is compiled and fixture-checked, default off, real Space not run. Both source review axes found no new concrete issues; diagnostics cleanup/final performance/PR readiness remain incomplete.
