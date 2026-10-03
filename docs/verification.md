# Product verification

2026-10-03, macOS 26, Apple Silicon, Swift 6.3.2 Command Line Tools. This note distinguishes deterministic contracts, fixture application paths, native integrations and distribution checks. Review readiness does not mean every release acceptance path has been run.

## Verified

- `scripts/check.sh`: 4 persisted-settings checks, 15 attention/Hold checks, 6 local observation contract groups, 7 platform contract groups, and 4 VS Code extension tests pass. Swift checks throw and exit nonzero on failure; no XCTest installation is required.
- The same command runs both actual Python hook installers against disposable settings with an existing hook and an unrelated preference. Repeated installation is idempotent. Executing their generated commands produces a shared normalized stream with correct Claude/Codex Desktop identity, no harness-facing output, no prompt/command sentinel text, and file mode 0600. No user harness configuration is changed.
- `swift build` compiles the integrated core, observer and platform modules. The foundation release bundle was locally signed and verified; the final companion bundle and UI paths are recorded below when run.
- Local record shapes were inspected for structured keys and enums only. Codex Desktop question call/output and turn markers have representative contracts. Historical records are baselined, incomplete lines wait for completion, child/remote records are skipped, and a complete sleep/wake batch precedes attention-clock advancement.
- Platform mocks verify owning-app visits return fallback, preserve unviewed attention, refuse missing/ambiguous exact sources, validate source lifetime and degrade WeChat application return. These mocks do not prove a real app switched.

## Runtime evidence

Companion runtime checks are pending integration. This section will name the exact fixture launch, actual UI actions and observations; fixture navigation must not be presented as native Warp/Codex/WeChat activation.

## Not run

- Live Claude/Codex hook approval lifecycle and Codex CLI rollout acceptance. Native signal coverage and unavailable categories are listed in [observation integration](observation-integration.md); unknown reason and absence of a stop signal are different cases.
- Native owning-app activation through the final companion, live WeChat return, Tabbit moved/navigated/closed-tab return with Automation authorization, and VS Code editor/terminal return inside a disposable Extension Development Host.
- Login registration/approval and an actual logout/login cycle; saved launch-at-login preference alone is not evidence of registration.
- Multiple displays, multiple Spaces, fullscreen app visibility, Reduce Motion enabled at system level, screen placement during live focused-window changes, and a user comprehension check of the graphical legend.
- Audible system/custom audio playback and application settings behavior through an actual quit/relaunch cycle beyond the persisted store contract.
- Runtime packet capture. Source inspection and local stream checks establish the implemented local data path; they are not a packet-level audit.

## Blocked / deferred

- Exact Warp pane navigation/reattachment and exact Warp source capture are outside the approved first-release scope ([#10](https://github.com/CheeseFox259/Char/issues/10)); no usable Warp Control endpoint was established on the installed Stable build.
- Exact Codex chat and WeChat chat return are outside the approved first-release scope ([#11](https://github.com/CheeseFox259/Char/issues/11), [#12](https://github.com/CheeseFox259/Char/issues/12)). A browser security rejection of a custom Codex URI was not bypassed.
- Codex failure/rate/context stops and Claude context exhaustion currently lack reliable observer signals. The capability matrix records them as unavailable, never as inferred unclassified events.

## Not applicable

Cloud/SSH sessions, remote synchronization, telemetry, Agent process ownership, Linux/Windows support and responding to prompts from the companion are outside the specification. Developer ID distribution signing and notarization are not part of this source PR; the build script produces an ad hoc signed local bundle.
