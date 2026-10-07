import { observation, appendObservation } from './event-writer.mjs';

/** Passive observer for Pi 1.0's final settlement and blocking UI events. */
export function createCharExtension({ eventsFile }) {
  return function charObserver(pi) {
    let active = false;
    let finalReason = 'unclassified';
    let warned = false;
    async function emit(ctx, event, reason) {
      const sessionID = ctx.sessionManager.getSessionId();
      if (!sessionID) return;
      const target = { bundleIdentifier: 'dev.warp.Warp-Stable', processID: process.pid,
        ...(ctx.sessionManager.getSessionFile() ? { sourcePath: ctx.sessionManager.getSessionFile() } : {}),
        ...(process.env.TMUX_PANE ? { tmuxPaneID: process.env.TMUX_PANE } : {}),
      };
      const kind = event === 'settled' ? reason : event;
      try {
        appendObservation(eventsFile, observation('pi', sessionID, target, Date.now(), kind));
      } catch {
        // Pi owns terminal rendering. Raw stdout/stderr writes corrupt its TUI,
        // and shutdown/reload must not leave a notification after it is torn down.
        if (!warned && ctx.hasUI && event !== 'closed') {
          ctx.ui.notify('Char: Pi observation unavailable. Check the Char event-file permissions.', 'warning');
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
