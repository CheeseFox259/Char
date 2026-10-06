# Capability Plugins Implementation Plan

> **For agentic workers:** Execute the steps inline in this session. The user has authorized implementation; no delegation or execution-choice prompt is needed.

**Goal:** A developer can import a new client package and receive monitoring, visit/return and lifecycle behavior without editing or rebuilding Char.

**Architecture:** A version 3 manifest selects a process adapter through a versioned local JSON interface. Char owns attention aggregation and transient first-origin anchors; adapters own client protocols, opaque page/session identities and only their own installation records. Existing version 1/2 manifests and seven built-in observers continue to work. Native integrations use a host-managed stable helper and deployment directory.

**Tech Stack:** Swift/Foundation Process and pipes, JSON Lines request/response/events, existing AppKit/SwiftUI UI, Node/Python native integrations.

---

## Task 1 — Dynamic identities and compatible manifests

Files: `Sources/CharCore/Models.swift`, `IntegrationPlugins.swift`, `AttentionRouter.swift`; display callers in `Sources/CharApp`; existing core checks.

- [x] Replace the closed WorkEnd enum with a validated, Codable string identity; retain the seven static constants and built-in ordering. Derive bubble membership from current sessions/items and render names/icons/CLI badges from manifests.
- [x] Extend manifests with optional adapter descriptor `{runtime, entrypoint, capabilities}`, interface kind and package version. Version 1/2 data decodes with its current meaning. Validate executable/script paths inside copied packages.
- [x] Support same-ID package update with atomic registry commit, preserving enable state; unchanged updates remain idempotent.
- [x] Run `swift run char-core-checks` and `swift build`. Existing migration and routing checks must pass; a namespaced custom identity must aggregate without enum edits.

Wire identity example:
```json
{"workEnd":"vendor.client.desktop","nativeID":"native-root-session"}
```

## Task 2 — Process adapter interface and test surface

Create `Sources/CharPluginHost/AdapterProcess.swift`, `CapabilityHost.swift`; expose a focused check executable through `Package.swift`.

- [x] Implement framed requests, bounded async responses and event draining; own adapter startup/stop and detach cleanup. Process stderr stays outside UI; protocol errors fail requests, never become observation records.
- [x] Implement these methods: `hello`, `inspect`, `install`, `update`, `uninstall`, `start`, `stop`, `visit`, `capture`, `check`, `focus`. Version mismatch is unavailable; `inspect` reports ready/notInstalled/reloadRequired/unavailable. Methods outside manifest capabilities are rejected by the host.
- [x] Decode events with ISO-8601 time, declared work-end identity, native identity, state, optional reason/target and child marker. Preserve enabled generations and reject events from removed processes.
- [x] Exercise the same host interface with a temporary authored adapter: custom event, accurate visit, capture/check/focus, failed request, version mismatch, stop and install/update/uninstall.

Request and response:
```json
{"version":1,"id":"1","method":"inspect","params":{}}
{"version":1,"id":"1","result":{"status":"ready"}}
```
Event:
```json
{"version":1,"event":{"workEnd":"vendor.client.desktop","nativeID":"s1","timestamp":"2026-10-06T00:00:00Z","state":"stopped","reason":"question"}}
```

## Task 3 — Runtime, navigation and first anchor

Files: `Sources/CharApp/Runtime.swift`, `RuntimePlugins.swift`, new `RuntimeCapabilities.swift`, platform host coordinator; settings/models/router.

- [x] Start adapters only for enabled packages; read pushed events into the existing router. Built-in log readers stay incremental. Settings distinguish enable intent from runtime readiness and expose inspect/install/update actions.
- [x] Use adapter visits when declared; otherwise retain application activation. Capture exact adapter origins asynchronously before visits, bind opaque tokens to original PID and adapter instance. Fallback capture remains available for arbitrary applications.
- [x] Route check/focus through the owning adapter; false means closed, unknown retains retry. Verify accurate arrival before returning exact. Release anchors on adapter removal; application anchors remain independent.
- [x] Add original/latest/disabled origin policy with original as default, preserving old settings. Add an application-origin preference; retain existing Ctrl+B and grace settings.
- [x] Exercise imported custom bubbles and first-origin behavior in isolated native smoke. Failed visits do not replace origin; removing a plugin clears its monitor and exact anchors.

## Task 4 — Stable native integration lifecycle

Create native lifecycle adapter/runtime resources; modify packaging scripts to include canonical native files.

- [x] Deploy bundled `char-hook` and native integration resources to host-owned stable locations under the current user's Char support directory. Supply resolved paths through adapter context, never a developer home or build path.
- [x] Migrate pi/Kimi/DeepSeek via explicit lifecycle actions, private backups and owned-entry edits. Inspect confirms actual installed paths/configuration and distinguishes restart-required from active runtime proof. Uninstall removes only owned hooks/mounts.
- [x] Test lifecycle against temporary HOME and synthetic client config; preserve same-event user hooks and unrelated YAML/TOML. User configs are touched only under existing authorization; no model requests or client restarts by the agent.
- [x] Run `bash scripts/check.sh`, focused host checks, and package validation. Package the development app for verification without replacing the official Release installation.

## Task 5 — Developer delivery and verification

Files: `docs/plugin-development.md`, `integration-plugin-format.md`, protocol/lifecycle docs, `integrations/AGENTS.md`, `Resources/Integrations/AGENTS.md`, `Resources/Skins/AGENTS.md`, architecture/README as affected.

- [x] Provide a runnable scaffold, production package check and event replay through the actual host. Describe supported runtimes, precision verification, installation ownership and performance contract.
- [x] Rewrite all three generic AGENTS instructions for their actual responsibilities. They select client/design from the user's task and do not prescribe a particular plugin or appearance.
- [x] Run native isolated import → monitor → visit → return → disable/update/delete using a never-used temporary registry. Record real app GUI and fixture evidence separately. Inspect final settings, custom bubble icon and capability/readiness feedback through CUA.
- [x] Measure normal idle adapter cost and stop behavior; confirm no per-plugin recurring polling timer and no orphan adapter after disable/quit. Keep official app and existing user sessions intact.
- [x] Save the verification report with exact passed commands and unrun live/provider checks; update the plan checkboxes only when evidence exists.

## Evidence and boundary

See [capability-plugins-verification-2026-10-06.md](../../capability-plugins-verification-2026-10-06.md). The acceptance client is an authored independent fixture, navigation is simulated, native lifecycle uses temporary HOME, and GUI is isolated. Live client reload, release/installation and whole-app performance are not claimed. No user client configurations or official installation were changed by the lifecycle tests.
