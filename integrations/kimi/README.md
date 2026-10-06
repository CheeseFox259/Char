# Native Kimi Code integration

> v0.2.0 提供统一安装维护：设置 → 插件 → 工具菜单可自检、安装、更新和移除所属集成，使用当前用户 Char 稳定运行目录。以下保留手动安装步骤。详见[能力插件开发指南](../../docs/plugin-development.md)。

Supported installed contracts: Kimi Code CLI **2.1.1**, Kimi Code App **1.0.4**.
The native hooks identify the interface with `client_type`; Char reads only
`agents/main/wire.jsonl` to classify root execution. No tmux pane is required for
CLI usage in Warp.

Run the explicit installer with Python **3.11+**, selecting the native config and
Char bundle paths. It preserves the existing TOML and hooks and is idempotent.
This operation is not run automatically by Char.

```sh
python3 integrations/kimi/install.py \
  --settings "$HOME/.kimi-code/config.toml" \
  --hook-binary /Applications/Char.app/Contents/MacOS/char-hook \
  --events-file "$HOME/Library/Application Support/Char/harness-hooks.jsonl"
```

Use the installed Release path for everyday use. An early installation may still
point to a removed `build/Char.app`; app updates do not rewrite the separate Kimi
config. Back up the config and rerun the command above. The installer migrates
its four existing Char hook commands in place, preserving other settings and
user hooks, rather than appending a second set beside the dead commands.

Start or resume a session after installing the hook. Existing unbound sessions
cannot be attributed to CLI or Desktop and are ignored. Set `KIMI_CODE_HOME` for
Char as well when the native data root is customized.

SessionStart/End retain only an interface binding. Root approval hooks require
native `agent_id=main`, `turn_id`, and approval `id`; completed turns and resolved
approval IDs reject delayed hooks. Rootless hook Stop/PreToolUse inputs are ignored
because this installed build emits them for child Agents without an Agent ID.

Root wire signals: prompt/steer/step begin, foreground AskUserQuestion and matching
tool result, completed/failed/cancelled/blocked turn. Structured `provider.rate_limit`
and `context.overflow` identify resource failures. Arbitrary message/error text
never classifies a reason. Background questions do not stop the root Agent.

Hook input may include user text, but Char's shared private stream stores only the
binding/phase/IDs/time and final observation metadata. No conversation text,
command, title, tool arguments, or error message is persisted by the adapter.
