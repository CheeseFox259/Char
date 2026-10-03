# New native observation contracts — 2026-10-04

Scope: DeepSeek Harness Desktop, Kimi Code CLI in Warp, and Kimi Code App.
Baseline Char 905a012. Read-only source inspection used these installed versions:
DeepSeek Harness 0.2.0-rc.2 (`com.deepseek.dsh`), Kimi Code App 1.0.4
(`com.kimi.code.desktop`), Kimi CLI 2.1.1. No user-profile hook/plugin was installed,
no conversation contents were printed, and no external provider was called.

## Source boundary

Kimi's [official hook contract](https://moonshotai.github.io/kimi-code/en/customization/hooks)
and [session storage](https://moonshotai.github.io/kimi-code/en/guides/sessions.html)
were checked against the installed bundle's `agent-core-v2/features/externalHooks`
and `wire` implementations in `out/screenshot-gqZU6x82.cjs`. Hook field names are
converted dynamically from camelCase; absence of a literal `client_type` string
is not absence of hooks. Desktop `DESKTOP_MSH_PLATFORM` is `kimi_code_desktop`;
CLI is `kimi_code_cli`. Agent hook Stop/PreToolUse omit `agent_id`, so they cannot
prove a root. Session hooks bind a native session to its owning interface, main
wire events prove root execution, and approval hooks include root Agent/turn/ID.

DeepSeek's bundled packages `dsh-session`, `dsh-agent-loop`, `dsh-user-questions`,
`dsh-user-approval`, `dsh-session-telemetry`, and Cordis 4.0.4 establish the native
live seams. The Desktop plugin additionally requires the native `dsh-desktop-host/lib/index.js`
process entry and connected Electron IPC channel (installed Desktop main launch
source); CLI `lib/cli.js` and Web/TUI hosts are rejected. It uses those seams, preserving the original
waterfall result/error and never replaying history. Compressed v4 session journals
and shared `~/.dsh` storage are not used to guess Desktop provenance.

## Implemented coverage

| Interface | Source | Reasons and continuation |
|---|---|---|
| Kimi CLI / App | native SessionStart binding + main wire | running; foreground question + matching result; completed turn; cancelled/blocked unclassified; structured failure/rate limit/context overflow |
| Kimi CLI / App | root approval hooks with native turn/approval IDs | approval and resolution; delayed requests after resolution and hooks after completed turns rejected |
| DeepSeek Desktop | explicit Desktop plugin, native live root events | running; question wait/reply; approval/resolution; completed turn; failure/rate limit/context overflow; confirmed unknown stop; closed |

Kimi bindings present before Char starts are metadata only. Existing root wires
are baselined at EOF; previous waits are not restored. Unbound native sessions are
ignored. Both paths write through Char's existing private locked metadata stream.
Kimi's typed metadata envelope is ignored by ordinary ObservationEvent decoding
and handled only by its native poller. All resulting events join the existing
whole-batch time ordering and watermark filter.

## Evidence and remaining acceptance

- L1: eight Swift observation contract groups include Kimi baseline, interface
  identity, root-only wire, question pairing, and structured resource reasons.
- L1/L2: three DeepSeek Node contract groups cover real subprocess metadata writes,
  Desktop process provenance, child suppression, structured reasons, and pending timed questions.
- L2: installed native Cordis loaded the canonical plugin and emitted through the
  actual built `char-hook`; Swift date/state encoding was verified in its output.
- L3: `swift build --product char-hook`; installed `kimi doctor config` accepted
  the generated native TOML.
- Actual Kimi CLI/App and DeepSeek Desktop lifecycle acceptance: USER_RUN_REQUIRED
  after explicit native integration installation. No provider or GUI run is
  inferred from fixture, configuration-validation, or Cordis seam checks.
- Original Claude/Codex missing signal categories remain unchanged blockers.

Canonical sources: `integrations/deepseek/index.js`, `integrations/kimi/install.py`,
`Sources/CharObservations/NewAgentHooks.swift`, and `KimiObservationPoller.swift`.
Temporary extracted installed modules and disposable contract directories were
outside the repository. Disposable test directories were removed; persistent
native data roots and Desktop installations were preserved.
