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

## 2026-10-06 installed-path repair

User reports missing Desktop reminders. The approved Desktop mount still points
to a removed local build. A fresh temporary event stream through the canonical
observer reproduces hook startup failure; changing only `hookBinary` to the
installed v0.1.2 Release makes running/turn-ended events write successfully.

Write boundary: the single Char entry in the user's Desktop patch, with private
backup and preservation of all other patch bytes. No DSH core, provider binding,
session or plugin source changes. Validate native YAML, unique mount, canonical
source path, real packaged writer and existing plugin suite. Live Host reload and
natural-turn verification remain user-run; browser UI is N/A for this observer.
