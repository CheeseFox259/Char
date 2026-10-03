# Char observer for DeepSeek Harness Desktop

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
        hookBinary: /absolute/path/to/Char.app/Contents/MacOS/char-hook
        eventsFile: /Users/YOUR_USER/Library/Application Support/Char/harness-hooks.jsonl
```

The package is mounted only in Desktop. Its runtime guard requires the native
`dsh-desktop-host/lib/index.js` entry and a connected Electron IPC channel.
A CLI/Web/TUI process is rejected even if it accidentally loads this package. Restart/reload the Desktop profile after the approved mount.

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
