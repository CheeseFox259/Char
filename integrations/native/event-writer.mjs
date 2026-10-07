import { mkdirSync, openSync, writeSync, closeSync } from 'node:fs';
import { dirname, isAbsolute } from 'node:path';

// The existing Swift Codable stream uses Apple's 2001 reference epoch.
const referenceEpoch = 978307200000;
export function observation(workEnd, nativeID, target, milliseconds, kind) {
  if (typeof nativeID !== 'string' || !nativeID || !Number.isFinite(milliseconds) || milliseconds < 0) return null;
  const state = kind === 'running' || kind === 'closed' ? { [kind]: {} }
    : ['question', 'approval', 'turnEnded', 'failure', 'rateLimit', 'contextExhausted', 'unclassified'].includes(kind)
      ? { stopped: { _0: kind } } : null;
  return state ? { key: { workEnd, nativeID }, target, timestamp: (milliseconds-referenceEpoch)/1000, state, isChild: false } : null;
}

/** Small local metadata only: no daemon, subprocess, timer, retained fd or write queue. */
export function appendObservation(destination, event) {
  if (!event) return;
  if (!isAbsolute(destination)) throw new Error('Event destination must be absolute');
  const line = Buffer.from(JSON.stringify(event) + '\n');
  if (line.length > 16 * 1024) throw new Error('Observation metadata exceeds 16 KiB');
  mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
  const descriptor = openSync(destination, 'a', 0o600);
  try {
    // A single O_APPEND write keeps concurrent small records together. Reopening
    // on each event follows rotation and avoids stale descriptors after reload.
    if (writeSync(descriptor, line) !== line.length) throw new Error('Incomplete observation append');
  } finally { closeSync(descriptor); }
}
