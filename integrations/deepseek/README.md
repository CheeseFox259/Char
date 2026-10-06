# Char observer for DeepSeek Harness Desktop

> v0.2.0 提供统一安装维护：设置 → 插件 → 工具菜单可自检、安装、更新和移除所属集成，使用当前用户 Char 稳定运行目录。以下保留手动安装步骤。详见[能力插件开发指南](../../docs/plugin-development.md)。

This explicit Desktop plugin supports DeepSeek Harness **0.2.0-rc.2**. It observes
live root Sessions and calls the installed `char-hook --deepseek`. It has no UI,
network request, Agent control, or conversation export. Existing history is not
replayed. Child Agents never create Char observations.

Mount this entry in the **Desktop** profile's existing patch list, with actual
absolute paths. The patch is a reviewable deployment change; creating this package
does not install it into the running Desktop or edit `~/.dsh`.

```yaml
- insert:
    - id: char-desktop-observer
      name: /absolute/path/to/Char/integrations/deepseek/index.js
      config:
        hookBinary: /Applications/Char.app/Contents/MacOS/char-hook
        eventsFile: /Users/YOUR_USER/Library/Application Support/Char/harness-hooks.jsonl
```

The package is mounted only in Desktop. Its runtime guard requires the native
`dsh-desktop-host/lib/index.js` entry and a connected Electron IPC channel.
A CLI/Web/TUI process is rejected even if it accidentally loads this package. Restart/reload the Desktop profile after the approved mount.

For everyday use, keep `hookBinary` at the installed Release path above. Older
mounts may reference `build/Char.app`; deleting that build breaks observation even
though the plugin itself still loads. Back up the Desktop patch and replace only
the Char entry's `hookBinary`, keeping one `char-desktop-observer` entry. Reload or
restart Desktop afterward: editing the file does not refresh a running plugin's
config. App updates at the same `/Applications/Char.app` path need no patch change.

Signals: root turn start/end; approval requested/resolved; actual question wait;
structured `RATE_LIMIT` and `CONTEXT_WINDOW_EXCEEDED`; other error; interrupted or
blocked/output-capped stop; source Session disposal. A timed unanswered question
remains pending after the foreground wait expires and suppresses ordinary turn-end
replacement until its actual reply. General tool calls and response text never
infer a stop.

`node --test integrations/deepseek/index.test.js` verifies the mapping, root-only
subscriptions and Desktop host provenance, pending questions, and metadata privacy. Installed native Cordis
integration was checked separately; actual Desktop turn/approval/question and
source disposal remain user-run acceptance, not claimed by these local tests.
