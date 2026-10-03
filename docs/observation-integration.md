# Local observation integration

`LocalObservationPoller` reads Claude Code project journals under `~/.claude/projects`, Codex journals under `~/.codex/sessions`, and an optional `char-hook` event file. Construct it with those URLs, call `start()` once, then call `poll()` on a timer. `start()` records current byte offsets and reads only Codex session metadata; it does not replay old waits. A file created after startup is read from byte zero. Incomplete final lines remain pending. When waking from sleep, pass **the entire returned batch** to the attention router before advancing its clock, so a stop followed by a resume during sleep is not presented as an active wait. Adjacent duplicate states for the same native session are collapsed, including a Claude Stop seen through both transcript and hook.

The observer stores only `ObservationEvent` metadata in memory: work end, native session ID, event time, state, and target path/process/pane when a source actually provides it. It does not retain prompt, command, or response text. It never starts or controls an Agent. `SessionTarget`'s pane ID is usually absent from the native journals; this first release uses application fallback navigation.

The poller retains the newest event timestamp per native session even when adjacent states are duplicates. Delayed records from a second stream cannot move that timestamp backwards or suppress a later valid stop. One contract check drives the real poller and attention router through late-stop and duplicate-running sequences.

## Signals currently confirmed

| Source | Structured signal | Event |
| --- | --- | --- |
| Claude project JSONL | `type=user` (non-meta) | running |
| Claude project JSONL | `type=assistant`, `message.stop_reason=end_turn` | turn ended |
| Codex session JSONL | `event_msg.payload.type=task_started` | running |
| Codex session JSONL | `event_msg.payload.type=task_complete` | turn ended |
| Codex session JSONL | `turn_started` / `turn_complete` in current upstream persistence policy | running / turn ended |
| Codex session JSONL | `event_msg.payload.type=turn_aborted` | unclassified stop |
| Codex session JSONL | `response_item` function call named `request_user_input` or `request_user_input_async` | question |
| Codex session JSONL | matching function call output `call_id` after a question | running |
| Claude official hook | `PermissionRequest` or `Notification(permission_prompt)` | approval |
| Claude official hook | `Elicitation`, `Notification(elicitation_dialog)`, or `PreToolUse(AskUserQuestion)` | question |
| Claude official hook | `Stop` | turn ended |
| Claude official hook | `StopFailure(error=rate_limit)` | rate limit |
| Claude official hook | `StopFailure` with another error value | failure; missing error is unclassified |
| Claude official hook | `PostToolUse`, `PostToolUseFailure`, `ElicitationResult`, ordinary `PreToolUse` | running after a pending interaction |
| Claude official hook | `SessionEnd` | closed |
| Codex official hook (optional) | `PermissionRequest` | approval candidate |
| Codex official hook (optional) | `PreToolUse(request_user_input*)` | question candidate |
| Codex official hook (optional) | `PostToolUse` | running after tool resolution |
| Codex official hook (optional) | `Stop` / `Interrupt` | turn ended / unclassified |

Claude's hook names and structured error values come from its [official hooks reference](https://code.claude.com/docs/en/hooks). Codex's app-server documentation confirms distinct turn completion status, but does not promise a stable on-disk JSONL contract; the local mappings above were checked against redacted record **shapes** on this Mac. See [Codex app-server documentation](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server). Format changes should be handled by updating contract fixtures after inspecting keys/enums only.

Codex JSONL on this host did expose direct `request_user_input` and `request_user_input_async` function calls and matching outputs in local Desktop rollouts. Current [upstream rollout persistence policy](https://github.com/openai/codex/blob/main/codex-rs/rollout/src/policy.rs) persists turn start/complete but excludes approval requests, user-input requests, and `Error` events from JSONL. The [official Codex hooks interface](https://learn.chatgpt.com/docs/hooks) can optionally observe permission requests and tool continuations; its `transcript_path` is not a stable format contract. The Codex hook adapter resolves matching local `session_meta` before emitting anything, to preserve CLI/Desktop identity and skip child/remote origins. If metadata is absent, it emits nothing.

| Work end | Turn end | Question | Approval | Failure | Rate limit | Context exhausted |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code CLI | transcript or optional `Stop` hook | optional `Elicitation` / `AskUserQuestion` hook | optional `PermissionRequest` hook | optional `StopFailure` hook | optional `StopFailure(error=rate_limit)` hook | unavailable |
| Codex Desktop local | sampled JSONL turn complete or optional `Stop` hook | sampled direct function call/output; optional tool hook | optional `PermissionRequest` hook; not yet tested live | unavailable | unavailable | unavailable |
| Codex CLI local | upstream persisted turn markers or optional `Stop` hook; live CLI rollout still unverified | direct function call/output or optional tool hook; live CLI unverified | optional `PermissionRequest` hook; live CLI unverified | unavailable | unavailable | unavailable |

Claude's observed transcript alone did not expose approval, question, or API failure categories; the hook provides those. Neither source currently confirms context exhaustion separately: `max_output_tokens` in Claude's `StopFailure.error` is an output cap, so it maps to failure. The observer never guesses a category from arbitrary response text or idle time. A confirmed stop with an unknown cause maps to `unclassified` only where the source supplies a stop event; absence of any stop signal means no observation. Child session records (`isSidechain`, `subagents/`, Codex `parent_thread_id`/`thread_source=subagent`) and explicit remote/cloud Codex origins are skipped. Claude transcript records with an explicit non-CLI entrypoint are skipped. Claude hook input does not contain an authoritative CLI-versus-Desktop field, so a user-level hook can only be treated as an opt-in Claude Code signal, not independently proven as CLI-only.

## Optional Claude hook

The `char-hook` executable consumes one official hook JSON object on stdin and appends a normalized JSONL event to `~/Library/Application Support/Char/harness-hooks.jsonl` (or `CHAR_HOOK_EVENTS`). It writes no model-facing output and does not change the hook's decision. Build with `swift build -c release`. To opt in, explicitly run:

```sh
python3 integrations/claude/install.py \
  --settings "$HOME/.claude/settings.json" \
  --hook-binary "/absolute/path/to/.build/release/char-hook" \
  --events-file "$HOME/Library/Application Support/Char/harness-hooks.jsonl"
```

The installer merges command handlers into existing hook arrays and leaves other settings and hook entries in place. Repeating the same command is idempotent. This repository does not install the hook automatically. Review the settings file and grant its normal local write permissions before opting in. The poller should receive the same `hookEventsFile` path. Existing hook records at `start()` are baselined like transcript records.

## Optional Codex hook

Codex documents command hooks in `~/.codex/hooks.json`, including `PermissionRequest`, `PreToolUse`, `PostToolUse`, `Stop`, and `Interrupt`. Installing the handler is explicit and preserves existing hook entries:

```sh
python3 integrations/codex/install.py \
  --hooks "$HOME/.codex/hooks.json" \
  --hook-binary "/absolute/path/to/.build/release/char-hook" \
  --events-file "$HOME/Library/Application Support/Char/harness-hooks.jsonl"
```

The app observes this shared file for both harnesses. Give both installers this same `--events-file` path; `LocalObservationPoller` accepts one normalized hook stream. Codex may require hook trust review before it runs non-managed handlers. `char-hook --codex` returns no model-visible output and does not approve, deny, rewrite, or interrupt tools. It only emits when the hook's session ID matches a local root journal's `session_meta` ID.
