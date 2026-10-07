#!/usr/bin/env node
/**
 * Char observer hook for MiniMax Code (CLI TUI, headless exec and Desktop).
 *
 * MiniMax Code calls this script once per native Plugin Hook event with exactly one
 * JSON object on stdin. The script appends one whitelisted JSON line to the host-owned
 * plugin data spool and exits 0. It never writes to stdout, never prints client text,
 * and never lets an error reach the client TUI.
 *
 * Native payload fields used: hook_event_name, session_id, cwd, tool_name, agent_id.
 * Everything else (prompt, tool input/output, assistant message, model, permission mode)
 * is deliberately ignored.
 */
import {appendFileSync, mkdirSync, readFileSync, renameSync, statSync} from 'node:fs';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';

const SPOOL_NAME = 'events.ndjson';
const SPOOL_MAX_BYTES = 2 * 1024 * 1024;
const ANCESTRY_DEPTH = 12;
const QUESTION_TOOL = 'ask_user';

/** Map a native Hook event to a whitelisted Char signal, or null when we ignore it. */
function classify(event, payload) {
  switch (event) {
    case 'SessionStart':
      return {signal: 'context', state: null, child: false};
    case 'SessionEnd':
      return {signal: 'closed', state: 'closed', child: false};
    case 'UserPromptSubmit':
      return {signal: 'running', state: 'running', child: false};
    case 'PermissionRequest':
      return {signal: 'approval', state: 'stopped', child: false};
    case 'PreToolUse':
      return payload.tool_name === QUESTION_TOOL
        ? {signal: 'question', state: 'stopped', child: false}
        : {signal: 'running', state: 'running', child: false};
    case 'PostToolUse':
      return {signal: 'running', state: 'running', child: false};
    case 'Stop':
      return {signal: 'turnEnded', state: 'stopped', child: false};
    case 'SubagentStart':
      return {signal: 'childStarted', state: 'running', child: true};
    case 'SubagentStop':
      return {signal: 'childStopped', state: 'stopped', child: true};
    default:
      return null;
  }
}

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

/**
 * Walk the owning client process from the hook's parent upward.
 * Returns {surface, processID} using only verified client identities:
 * - Desktop: the Electron main executable inside "MiniMax Code.app".
 * - CLI: the node client process published as "minimax-code" (or launched from
 *   the @minimax-ai/code package directory).
 * Command lines are inspected in memory only; nothing is written but the result.
 */
function locateClient() {
  let pid = process.ppid;
  let cli = null;
  for (let depth = 0; depth < ANCESTRY_DEPTH && Number.isInteger(pid) && pid > 1; depth += 1) {
    let line;
    try {
      line = execFileSync('/bin/ps', ['-o', 'pid=,ppid=,args=', '-p', String(pid)], {
        encoding: 'utf8',
        timeout: 1000,
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
    } catch {
      break;
    }
    if (!line) break;
    const match = /^\s*(\d+)\s+(\d+)\s+(.*)$/.exec(line);
    if (!match) break;
    const [, current, parent, args] = match;
    if (args.includes('/MiniMax Code.app/Contents/MacOS/MiniMax Code')) {
      return {surface: 'desktop', processID: Number(current)};
    }
    if (!cli && (args.trim() === 'minimax-code' || args.includes('/.minimax-code/') || args.includes('@minimax-ai/code/'))) {
      cli = {surface: 'cli', processID: Number(current)};
    }
    pid = Number(parent);
  }
  return cli ?? {surface: 'unknown', processID: null};
}

function rotateIfNeeded(path) {
  try {
    if (statSync(path).size < SPOOL_MAX_BYTES) return;
  } catch {
    return;
  }
  try {
    renameSync(path, `${path}.1`);
  } catch {
    /* A concurrent writer rotated it first. */
  }
}

function main() {
  const input = readStdin();
  if (!input.trim()) return;
  let payload;
  try {
    payload = JSON.parse(input);
  } catch {
    return;
  }
  if (!payload || typeof payload !== 'object') return;
  const event = typeof payload.hook_event_name === 'string' ? payload.hook_event_name : '';
  const classified = classify(event, payload);
  if (!classified) return;
  const sessionID = typeof payload.session_id === 'string' ? payload.session_id.trim() : '';
  if (!sessionID) return;

  const client = locateClient();
  const record = {
    v: 1,
    ts: new Date().toISOString(),
    ev: event,
    signal: classified.signal,
    state: classified.state,
    sid: sessionID,
    cwd: typeof payload.cwd === 'string' ? payload.cwd : '',
    surface: client.surface,
    pid: client.processID,
  };
  if (classified.child) {
    record.agent = typeof payload.agent_id === 'string' ? payload.agent_id : '';
    record.agentType = typeof payload.agent_type === 'string' ? payload.agent_type : '';
  }

  const dataDir = process.env.PLUGIN_DATA;
  if (!dataDir) return;
  const spool = join(dataDir, SPOOL_NAME);
  try {
    mkdirSync(dataDir, {recursive: true});
    rotateIfNeeded(spool);
    appendFileSync(spool, `${JSON.stringify(record)}\n`);
  } catch {
    /* Never block or pollute the client when the spool cannot be written. */
  }
}

main();