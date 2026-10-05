import { spawn } from 'node:child_process';
import { isAbsolute } from 'node:path';

export const inject = ['agents'];

export function classify(event) {
  switch (event.type) {
    case 'turn/start': return 'running';
    case 'approval/asked': return 'approval';
    case 'approval/decided': return 'running';
    case 'turn/end': {
      const reason = event.data?.reason;
      switch (reason?.kind) {
        case 'completed': return 'turnEnded';
        case 'error':
          if (reason.error?.code === 'RATE_LIMIT') return 'rateLimit';
          if (reason.error?.code === 'CONTEXT_WINDOW_EXCEEDED') return 'contextExhausted';
          return 'failure';
        case 'aborted': case 'blocked': case 'max-tokens': return 'unclassified';
        default: return null;
      }
    }
    default: return null;
  }
}

export function isDesktopHostRuntime(runtime = process) {
  return runtime.argv?.[1]?.replaceAll('\\', '/').endsWith('/@deepseek-ai/dsh-desktop-host/lib/index.js') === true
    && runtime.connected === true && typeof runtime.send === 'function';
}

export function apply(ctx, config) {
  if (!isDesktopHostRuntime()) throw new Error('Char DeepSeek observer requires the native Desktop IPC host');
  observe(ctx, config);
}

export function observe(ctx, config) {
  if (!config || !isAbsolute(config.hookBinary ?? '') || !isAbsolute(config.eventsFile ?? '')) {
    throw new Error('Char observer requires absolute hookBinary and eventsFile paths');
  }
  const knownRoots = new WeakSet();
  const pendingQuestions = new WeakMap();
  let writes = Promise.resolve();
  const root = (session) => {
    if (session.header?.origin === 'subagent') return false;
    if (ctx.agents.roots().some(agent => agent.session === session)) {
      knownRoots.add(session);
      return true;
    }
    return false;
  };
  const report = (session, kind, time = Date.now()) => {
    if (!kind || typeof session.id !== 'string' || !Number.isFinite(time)) return;
    const payload = { client_type: 'deepseek_desktop', root_session: true,
      session_id: session.id, kind, time };
    writes = writes.then(() => new Promise(resolve => {
      const child = spawn(config.hookBinary, ['--deepseek'], {
        env: { ...process.env, CHAR_HOOK_EVENTS: config.eventsFile },
        stdio: ['pipe', 'ignore', 'ignore'], timeout: 5000
      });
      child.on('error', () => { ctx.logger.warn('Char observation hook could not start'); resolve(); });
      child.on('exit', code => { if (code) ctx.logger.warn('Char observation hook failed'); resolve(); });
      child.stdin.on('error', () => {});
      child.stdin.end(JSON.stringify(payload));
    }));
  };
  ctx.on('session/event', (session, event) => {
    if (!root(session)) return;
    const pending = pendingQuestions.get(session);
    if (event.type === 'user/message' && event.data?.source?.kind === 'user-question-reply') {
      pending?.delete(event.data.source.callId);
      report(session, 'running', event.time);
      return;
    }
    const kind = classify(event);
    if (kind === 'turnEnded' && pending?.size) return;
    report(session, kind, event.time);
  });
  ctx.on('session/disposed', session => {
    if (knownRoots.has(session)) report(session, 'closed');
  });
  ctx.on('user-questions/request', async (request, next) => {
    if (!request.agent || !root(request.agent.session)) return next();
    const session = request.agent.session;
    const callID = request.wait?.callId ?? Symbol('question');
    const pending = pendingQuestions.get(session) ?? new Set();
    pending.add(callID);
    pendingQuestions.set(session, pending);
    report(session, 'question');
    try {
      const result = await next();
      pending.delete(callID);
      report(session, 'running');
      return result;
    } catch (error) {
      if (error?.code !== 'ASK_TIMED_OUT') {
        pending.delete(callID);
        report(session, 'running');
      }
      throw error;
    }
  });
  ctx.effect(() => async () => { await writes; });
}
