import { execFile } from 'node:child_process';

/** Passive observer for Pi 1.0's final settlement and blocking UI events. */
export function createCharExtension({ hookBinary, eventsFile }) {
  return function charObserver(pi) {
    let active = false;
    let finalReason = 'unclassified';
    let warned = false;
    async function emit(ctx, event, reason) {
      const sessionID = ctx.sessionManager.getSessionId();
      if (!sessionID) return;
      const record = {
        schema: 1, session_id: sessionID, event, timestamp: new Date().toISOString(),
        process_id: process.pid,
        ...(ctx.sessionManager.getSessionFile() ? { session_file: ctx.sessionManager.getSessionFile() } : {}),
        ...(process.env.TMUX_PANE ? { tmux_pane: process.env.TMUX_PANE } : {}),
        ...(reason ? { reason } : {}),
      };
      try {
        // execFile has no shell; only the allowlisted metadata envelope reaches Char.
        await new Promise((resolve, reject) => {
          const child = execFile(hookBinary, ['--pi'], {
            env: { PATH: process.env.PATH, CHAR_HOOK_EVENTS: eventsFile },
            maxBuffer: 4096,
          }, error => error ? reject(error) : resolve());
          child.stdin.end(JSON.stringify(record));
          child.stdin.on('error', () => {});
        });
      } catch {
        // Pi owns terminal rendering. Raw stdout/stderr writes corrupt its TUI,
        // and shutdown/reload must not leave a notification after it is torn down.
        if (!warned && ctx.hasUI && event !== 'closed') {
          ctx.ui.notify('Char: Pi observation unavailable. Check the configured char-hook path and event-file permissions.', 'warning');
          warned = true;
        }
      }
    }
    pi.on('agent_start', async (_event, ctx) => {
      active = true;
      finalReason = 'unclassified';
      await emit(ctx, 'running');
    });
    pi.on('message_end', event => {
      if (event.message.role !== 'assistant') return;
      // Tool failures and transient provider errors do not create a stop on their own.
      switch (event.message.stopReason) {
        case 'stop': case 'toolUse': finalReason = 'turnEnded'; break;
        case 'error': finalReason = 'failure'; break;
        default: finalReason = 'unclassified';
      }
    });
    pi.on('agent_settled', async (_event, ctx) => {
      if (!active) return;
      active = false;
      await emit(ctx, 'settled', finalReason);
    });
    pi.on('ui_prompt_start', async (_event, ctx) => {
      if (active) await emit(ctx, 'question');
    });
    pi.on('ui_prompt_end', async (_event, ctx) => {
      if (active) await emit(ctx, 'running');
    });
    pi.on('session_shutdown', async (_event, ctx) => {
      active = false;
      await emit(ctx, 'closed');
    });
  };
}
