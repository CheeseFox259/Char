# DeepSeek Desktop observation bridge

Baseline: Char 905a012, installed DeepSeek Harness 0.2.0-rc.2, bundle `com.deepseek.dsh`.
Canonical package: `integrations/deepseek`, `@char/deepseek-observer` 0.1.0.

The explicit Desktop deployment mounts this plugin; Char never discovers credentials,
controls the Agent, edits the DSH installation, or reads compressed conversation logs.
The protected environment is the user's `~/.dsh` and running Desktop.

Seams: `session/event` and `session/disposed` metadata, live `ctx.agents.roots()`
identity, and the `user-questions/request` waterfall with an unchanged `next()` call.
Observers never replay existing events. Structured root lifecycle records go to
`char-hook --deepseek`, which owns the locked private JSONL writer.

Milestones: pure mapping/root/subagent/privacy tests; native Cordis subscription
integration in a disposable process; Swift classifier/private-stream contract checks.
Browser UI is N/A (the bridge has no UI). External providers are not required for
local contract checks and are not authorized. User-profile mount and actual Desktop
turn/approval/question acceptance remain USER_RUN_REQUIRED.

No DSH core changes. No generated artifact or temporary home is canonical source.
