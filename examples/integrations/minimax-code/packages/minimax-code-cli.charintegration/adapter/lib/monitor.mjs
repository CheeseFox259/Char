// Translate native MiniMax Code Hook records into Char v1 observation events.
import {SpoolTail} from './spool.mjs';

const LIVENESS_INTERVAL_MS = 5000;

/** Records the client writes that never become an observation event. */
const CONTEXT_ONLY = new Set(['context']);

const STATE_BY_SIGNAL = {
  running: {state: 'running'},
  approval: {state: 'stopped', reason: 'approval'},
  question: {state: 'stopped', reason: 'question'},
  turnEnded: {state: 'stopped', reason: 'turnEnded'},
  closed: {state: 'closed'},
};

/**
 * Monitor one client surface. The Hook is shared by the CLI and the Desktop app, so
 * this class publishes only the records whose native surface matches its own package
 * and never publishes another package's workEnd events.
 */
export class Monitor {
  constructor({workEnd, surface, spool, directory, onEvent, onDiagnostic}) {
    this.workEnd = workEnd;
    this.surface = surface;
    this.spoolPath = spool;
    this.directory = directory;
    this.onEvent = onEvent;
    this.onDiagnostic = onDiagnostic ?? (() => {});
    this.sessions = new Map();
    this.childAgents = new Set();
    this.dropped = 0;
    this.published = 0;
    this.tail = new SpoolTail(spool, {onRecord: (line) => this.consume(line), onRotate: () => {}});
    this.timer = null;
    this.running = false;
  }

  start() {
    if (this.running) return;
    this.running = true;
    // A fresh tail per start: reading always begins at the current end of file.
    this.tail = new SpoolTail(this.spoolPath, {
      onRecord: (line) => this.consume(line),
      onRotate: () => this.onDiagnostic('observation spool rotated'),
    });
    this.tail.start(this.directory);
    this.timer = setInterval(() => this.sweep(), LIVENESS_INTERVAL_MS);
    this.timer.unref?.();
  }

  stop() {
    if (!this.running) return;
    this.running = false;
    this.tail.stop();
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  consume(line) {
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      this.dropped += 1;
      this.onDiagnostic('dropped a malformed spool line');
      return;
    }
    if (!record || typeof record !== 'object' || record.v !== 1) {
      this.dropped += 1;
      return;
    }
    if (record.surface !== this.surface) return;
    if (record.surface === 'unknown') {
      this.onDiagnostic('hook record had no identifiable client process');
      return;
    }
    const sessionID = typeof record.sid === 'string' ? record.sid.trim() : '';
    if (!sessionID) {
      this.dropped += 1;
      return;
    }
    const timestamp = typeof record.ts === 'string' && !Number.isNaN(Date.parse(record.ts))
      ? new Date(record.ts).toISOString()
      : new Date().toISOString();
    const session = this.sessions.get(sessionID) ?? {};
    session.pid = Number.isInteger(record.pid) && record.pid > 1 ? record.pid : session.pid ?? null;
    session.cwd = typeof record.cwd === 'string' && record.cwd ? record.cwd : session.cwd ?? '';
    session.closed = false;
    this.sessions.set(sessionID, session);

    if (record.ev === 'SubagentStart' && typeof record.agent === 'string' && record.agent) {
      this.childAgents.add(record.agent);
    }
    if (record.ev === 'SubagentStop' && typeof record.agent === 'string' && record.agent) {
      this.childAgents.delete(record.agent);
    }
    if (CONTEXT_ONLY.has(record.signal)) return;
    if (record.signal === 'childStarted' || record.signal === 'childStopped') return;
    const mapped = STATE_BY_SIGNAL[record.signal];
    if (!mapped) {
      this.dropped += 1;
      return;
    }
    const event = {
      workEnd: this.workEnd,
      nativeID: sessionID,
      timestamp,
      state: mapped.state,
    };
    if (mapped.reason) event.reason = mapped.reason;
    if (record.signal === 'closed') {
      event.state = 'closed';
      session.closed = true;
    }
    const target = {};
    if (Number.isInteger(record.pid) && record.pid > 1) target.processID = record.pid;
    if (session.cwd) target.sourcePath = session.cwd;
    if (Object.keys(target).length) event.target = target;
    this.published += 1;
    this.onEvent(event);
    if (event.state === 'closed') this.sessions.delete(sessionID);
  }

  /**
   * The client does not run SessionEnd on a normal process exit, so a session whose
   * owning client process disappeared is closed from observed process liveness.
   * This is an inferred boundary and is reported as such.
   */
  sweep() {
    if (!this.running) return;
    const now = new Date().toISOString();
    for (const [sessionID, session] of [...this.sessions]) {
      if (session.closed) continue;
      if (!Number.isInteger(session.pid) || session.pid <= 1) continue;
      if (isAlive(session.pid)) continue;
      const event = {
        workEnd: this.workEnd,
        nativeID: sessionID,
        timestamp: now,
        state: 'closed',
      };
      if (session.cwd) event.target = {processID: session.pid, sourcePath: session.cwd};
      this.published += 1;
      this.onDiagnostic(`closed session ${sessionID}: client process ${session.pid} is gone`);
      this.onEvent(event);
      this.sessions.delete(sessionID);
    }
  }
}

export function isAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 1) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === 'EPERM';
  }
}

/** Only used by tests: reset module-level timers between cases. */
export function livenessInterval() {
  return LIVENESS_INTERVAL_MS;
}