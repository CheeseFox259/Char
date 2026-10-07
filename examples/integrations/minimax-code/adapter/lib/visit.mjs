// Application-level navigation for the MiniMax Code work ends.
// Neither client exposes a public interface that focuses one session, so a visit only
// activates the carrying application and is reported as a fallback, never as exact.
import {execFile} from 'node:child_process';

const OPEN_PATH = '/usr/bin/open';
const PS_PATH = '/bin/ps';

function run(binary, args, timeout) {
  return new Promise((resolve) => {
    execFile(binary, args, {timeout, env: process.env}, (error) => {
      if (!error) resolve({ok: true});
      else resolve({ok: false, code: error.code ?? null, killed: Boolean(error.killed)});
    });
  });
}

/** Is at least one MiniMax Code client process of this surface running? */
export async function clientRunning(surface) {
  const result = await new Promise((resolve) => {
    execFile(PS_PATH, ['-Ao', 'comm='], {timeout: 2000, maxBuffer: 8 * 1024 * 1024, env: process.env},
      (error, stdout) => resolve(error ? null : stdout));
  });
  if (typeof result !== 'string') return null;
  const names = result.split('\n').map((line) => line.trim()).filter(Boolean);
  if (surface === 'desktop') {
    return names.some((name) => name === 'MiniMax Code' || name.endsWith('/MiniMax Code'));
  }
  return names.some((name) => name === 'minimax-code');
}

/**
 * Visit a MiniMax Code session.
 * The client cannot be told to focus a specific session, so the result is `fallback`
 * when the carrying application is raised and `unavailable` when it is not running.
 */
export async function visitSession({surface, bundleIdentifier, nativeID, processID}) {
  if (typeof nativeID !== 'string' || !nativeID.trim()) {
    throw new Error('visit requires nativeID');
  }
  if (Number.isInteger(processID) && processID > 1) {
    try { process.kill(processID, 0); }
    catch (error) { if (error.code !== "EPERM") return {outcome: "unavailable", detail: "the requested client process exited"}; }
  }
  const running = await clientRunning(surface);
  if (running === null) {
    return {outcome: 'unavailable', detail: 'could not inspect running MiniMax Code processes'};
  }
  if (!running) {
    return {outcome: 'unavailable', detail: 'no running MiniMax Code client for this work end'};
  }
  const activation = await run(OPEN_PATH, ['-b', bundleIdentifier], 2500);
  if (!activation.ok) {
    return {outcome: 'unavailable', detail: `could not activate ${bundleIdentifier}`};
  }
  return {outcome: 'fallback', detail: `${bundleIdentifier} activated; the client exposes no session-focus interface`};
}