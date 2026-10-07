# Char observer for DeepSeek Harness Desktop

> v1.0.0 提供统一安装维护：设置 → 插件 → 工具菜单可自检、安装、更新和移除所属集成，使用当前用户 Char 稳定运行目录。以下保留手动安装步骤。详见[能力插件开发指南](../../docs/plugin-development.md)。

This explicit Desktop plugin supports DeepSeek Harness **0.2.0-rc.2**. It observes
live root Sessions and writes allowlisted `ObservationEvent` metadata inside the existing Desktop runtime. It has no UI,
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

For everyday use, install/update using the Char settings maintenance menu. The current observer no longer executes `hookBinary`; this legacy configuration key is retained for compatibility. Older
mounts may reference `build/Char.app`; the old observer can fail after that build is deleted. Updating its code and reloading Desktop migrates to direct writes. Back up the Desktop patch and replace only
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

## Performance and updating

No event starts a Hook process. There is no additional daemon, pending write queue, retained file descriptor or per-session timer. One bounded metadata record is appended with one `O_APPEND` write, then the descriptor closes, so rotation remains visible. Records over 16 KiB or filesystem failures produce at most one metadata-only logger warning. Synchronous local I/O can delay a callback on a stalled filesystem; the normal private local support directory is the intended destination. Root/child filtering, pending-question behavior and structured error categories remain unchanged.

After updating Char, use **Settings → Plugins → DeepSeek Harness → Update integration**, then reload/restart Desktop to load the new observer. Char does not restart the client. Shared journal parsing improvements also benefit Kimi, Claude and Codex; see [performance](../../docs/performance.md).
