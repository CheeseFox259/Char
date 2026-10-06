# Pi observation in Warp

> v0.2.0 提供统一安装维护：设置 → 插件 → 工具菜单可自检、安装、更新和移除所属集成，使用当前用户 Char 稳定运行目录。以下保留手动安装步骤。详见[能力插件开发指南](../../docs/plugin-development.md)。

Char supports Pi running directly in Warp and inside Warp + tmux through an explicitly installed passive Pi extension. Char does not start Pi or take over its terminal. Navigation uses the agreed Warp application fallback, so visiting a bubble does not mark a session as exactly viewed.

## Install explicitly

For everyday use, select `char-hook` from the installed Release at `/Applications/Char.app`. This path survives updates in place. A hook under a temporary `build/Char.app` stops working when that build directory is removed. For development only, an explicit build path may be supplied.

```sh
python3 integrations/pi/install.py \
  --extension-dir "$HOME/.pi/agent/extensions/char" \
  --hook-binary "/Applications/Char.app/Contents/MacOS/char-hook" \
  --events-file "$HOME/Library/Application Support/Char/harness-hooks.jsonl"
```

This writes only the selected Char extension directory. It refuses to replace a nonempty directory without the Char ownership marker. Repeating the same command is idempotent. For an isolated test or a one-session opt-in, choose a temporary directory and load its `index.js` with `pi --extension /absolute/extension/index.js`; global discovery need not be changed. Installed global extensions load on the next Pi startup or extension reload. Existing Pi sessions are not modified by Char automatically.

## Repair an older installation

If you see `Char: Pi observation could not append a local event.`, inspect the `hookBinary` value in `~/.pi/agent/extensions/char/index.js`. Early local installations referenced `build/Char.app`; installing a Release does not rewrite this separate Pi extension configuration. Back up the Char extension outside Pi's extension-discovery directory, run the installation command above with the installed app path, then execute `/reload` in each open Pi session or restart Pi. No Char app rebuild or model request is required.

The same extension is used by direct Warp and Warp + tmux, so an invalid hook path breaks both. Check that the selected hook exists and is executable, and that the event file's parent directory is writable. An application update is safe as long as the installed path stays the same.

Write failures now use Pi's `ctx.ui.notify` once in interactive mode, never raw stdout/stderr. Print mode and session shutdown do not display a warning. This keeps failures inside Pi's renderer and prevents leftover text over the input region or after exiting. The warning does not become a prompt or a persisted conversation message.

## Structured signals

Initially tested against `@earendil-works/pi-coding-agent` **1.0.0** on 2026-10-04; native loader and CLI checks also passed with installed **1.0.3** on 2026-10-06. Pi's native event declarations and [official extension contract](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) provide the following boundaries:

| Native boundary | Char state |
| --- | --- |
| `agent_start` | Running |
| `ui_prompt_start` during an active agent run | Stopped: question |
| `ui_prompt_end` during an active agent run | Running |
| `agent_settled`, last assistant `stopReason=stop` or `toolUse` | Stopped: turn ended |
| `agent_settled`, last assistant `stopReason=error` | Stopped: failure |
| `agent_settled`, aborted/length/unknown final assistant outcome | Stopped: unclassified |
| `session_shutdown` | Closed observation lifecycle |

`agent_end` is deliberately not a stop: Pi can retry, compact, or continue queued work after it. A transient error updates only the pending outcome; a successful retry replaces it before settlement. Generic extension `confirm` dialogs are questions because their native event does not prove permission approval. Idle extension UI dialogs do not create agent attention. A shutdown due to reload or session replacement closes the old observation lifecycle; the next actual run resumes that native session's state.

Pi 1.0.0's final assistant outcome exposes a generic error, without an authoritative error category for rate limit or context exhaustion. Char does not infer these categories from error text. Automatic compaction is continuing work, not context exhaustion. Pi does not expose a built-in root-versus-spawned-child marker to this observer; user forks must not be mislabeled as child agents merely because their session header has `parentSession`. Custom extensions that spawn other Pi processes need a separate authoritative child-scope contract before those processes can be excluded reliably.

The native session ID comes from `ctx.sessionManager.getSessionId()`. The Pi PID and optional `TMUX_PANE` are target metadata; no tmux pane is required. The extension forwards no prompts, messages, UI titles, tool arguments, error text, or credentials. The child hook receives only `PATH` and the explicit event destination. `char-hook --pi` validates the metadata envelope and appends the normal `ObservationEvent` format to the existing private shared stream under its existing file lock. Char baselines that stream on startup, so old stops are not replayed.

## Why an extension is required

Pi's persisted session JSONL is a conversation tree. It records assistant outcomes, but does not persist the final `agent_settled` boundary or a blocking extension UI lifecycle. Watching it alone cannot prove that a transient provider failure or assistant response is the final settled stop. Char does not scan Pi journals and claim the same signal coverage. The official [SDK lifecycle documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sdk.md) distinguishes low-level run completion from final settlement.

## Verification

```sh
node integrations/pi/observer.test.mjs
CHAR_PI_PACKAGE=/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent \
  node integrations/pi/observer.test.mjs
node integrations/pi/native-cli.test.mjs /opt/homebrew/bin/pi .build/debug/char-hook
```

- The first check uses isolated event fixtures and an executable capture stub: direct Warp, optional tmux, question/resume, recovered transient failure, final failure/interruption, shutdown, privacy, and explicit installer idempotence. A real missing-executable failure must produce one Pi UI notification, no raw terminal text, and no fabricated event; print and shutdown failures stay silent.
- With `CHAR_PI_PACKAGE`, the second also loads the actual installed extension loader and dispatches through its native `ExtensionRunner`, using an in-memory session. This is native API compatibility evidence, not a real terminal session.
- The third launches the actual installed Pi CLI four times with a private agent directory, temporary HOME/project, disabled discovery/tools/context files, and `--offline`. A local HTTP stub returns completed and controlled-failure responses for both direct metadata and `TMUX_PANE` metadata. It verifies real native callbacks, actual `char-hook` normalized stream, distinct native session IDs, closure, and exclusion of private body text. All fixtures are removed afterward; no user credentials, profile, or running sessions are changed. The tmux case verifies event metadata, not an interactive Warp/tmux window.

The native CLI acceptance passed locally on 2026-10-04. It proves real CLI lifecycle capture, but does not prove a Warp window interaction or a live model-driven permission dialog. Existing Claude and Codex observation does not require `tmuxPaneID`: direct Warp sessions use the same app fallback, with tmux serving only as optional metadata.
