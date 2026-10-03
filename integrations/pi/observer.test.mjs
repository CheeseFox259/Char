import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, chmod, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { createCharExtension } from './observer.mjs';

const root = await mkdtemp(join(tmpdir(), 'char-pi-'));
const oldPane = process.env.TMUX_PANE;
try {
  const capture = join(root, 'capture.py');
  const stream = join(root, 'events.jsonl');
  await writeFile(capture, '#!/usr/bin/env python3\nimport os,sys\nassert sys.argv[1:]==["--pi"]\nwith open(os.environ["CHAR_HOOK_EVENTS"],"a") as f: f.write(sys.stdin.read()+"\\n")\n');
  await chmod(capture, 0o700);
  const extensionDir = join(root, 'extension');
  const installer = resolve('integrations/pi/install.py');
  const args = [installer, '--extension-dir', extensionDir, '--hook-binary', capture, '--events-file', stream];
  execFileSync('python3', args);
  const firstInstall = await readFile(join(extensionDir, 'index.js'), 'utf8');
  execFileSync('python3', args);
  assert.equal(await readFile(join(extensionDir, 'index.js'), 'utf8'), firstInstall);
  assert.equal((await stat(join(extensionDir, 'index.js'))).mode & 0o777, 0o600);
  const installed = (await import(pathToFileURL(join(extensionDir, 'index.js')))).default;
  const handlers = new Map();
  installed({ on: (name, handler) => handlers.set(name, handler) });
  const ctx = { sessionManager: { getSessionId: () => 'native-session', getSessionFile: () => '/private/session.jsonl' } };
  const emit = async (name, extra = {}) => handlers.get(name)?.({ type: name, ...extra }, ctx);
  delete process.env.TMUX_PANE;
  await emit('ui_prompt_start', { title: 'PRIVATE UI TEXT' }); // Idle prompts are not agent stops.
  await emit('agent_start');
  await emit('message_end', { message: { role: 'assistant', stopReason: 'error', errorMessage: 'PRIVATE ERROR', content: 'PRIVATE OUTPUT' } });
  assert.equal((await readFile(stream, 'utf8')).trim().split('\n').length, 1, 'transient error created a stop');
  await emit('message_end', { message: { role: 'assistant', stopReason: 'stop' } }); // Retry recovered.
  await emit('ui_prompt_start', { kind: 'confirm', title: 'PRIVATE CONFIRMATION' });
  await emit('ui_prompt_end', { kind: 'confirm' });
  await emit('agent_settled');
  process.env.TMUX_PANE = '%2';
  await emit('agent_start');
  await emit('message_end', { message: { role: 'assistant', stopReason: 'error' } });
  await emit('agent_settled');
  await emit('agent_start');
  await emit('message_end', { message: { role: 'assistant', stopReason: 'aborted' } });
  await emit('agent_settled');
  await emit('session_shutdown', { reason: 'quit' });
  const content = await readFile(stream, 'utf8');
  const records = content.trim().split('\n').map(JSON.parse);
  assert.deepEqual(records.map(r => r.event), ['running', 'question', 'running', 'settled', 'running', 'settled', 'running', 'settled', 'closed']);
  assert.equal(records[3].reason, 'turnEnded');
  assert.equal(records[5].reason, 'failure');
  assert.equal(records[7].reason, 'unclassified');
  assert.equal(records[0].tmux_pane, undefined);
  assert.equal(records[4].tmux_pane, '%2');
  assert(!content.includes('PRIVATE'), 'private event bodies persisted');
  assert(records.every(r => r.session_id === 'native-session' && r.process_id === process.pid));

  // Optional installed-Pi compatibility check: real loader and dispatch, with an in-memory session.
  if (process.env.CHAR_PI_PACKAGE) {
    const base = resolve(process.env.CHAR_PI_PACKAGE);
    const { loadExtensions } = await import(pathToFileURL(join(base, 'dist/core/extensions/loader.js')));
    const { ExtensionRunner } = await import(pathToFileURL(join(base, 'dist/core/extensions/runner.js')));
    const { SessionManager } = await import(pathToFileURL(join(base, 'dist/core/session-manager.js')));
    const loaded = await loadExtensions([join(extensionDir, 'index.js')], root);
    assert.equal(loaded.errors.length, 0, JSON.stringify(loaded.errors));
    const manager = SessionManager.inMemory(root);
    const runner = new ExtensionRunner(loaded.extensions, loaded.runtime, root, manager, {});
    const errors = [];
    runner.onError(e => errors.push(e));
    await runner.emit({ type: 'agent_start' });
    await runner.emitMessageEnd({ type: 'message_end', message: { role: 'assistant', stopReason: 'stop', content: [] } });
    await runner.emit({ type: 'agent_settled' });
    await runner.emit({ type: 'session_shutdown', reason: 'quit' });
    assert.equal(errors.length, 0, JSON.stringify(errors));
    const native = (await readFile(stream, 'utf8')).trim().split('\n').slice(records.length).map(JSON.parse);
    assert.deepEqual(native.map(r => r.event), ['running', 'settled', 'closed']);
    assert(native.every(r => r.session_id === manager.getSessionId()));
    assert.equal(native[1].reason, 'turnEnded');
    console.log('Pi native loader/runner contract passed');
  }
  console.log('Pi extension: direct Warp, tmux metadata, retry settlement, UI pause/resume, shutdown, privacy and explicit installer passed');
} finally {
  if (oldPane === undefined) delete process.env.TMUX_PANE; else process.env.TMUX_PANE = oldPane;
  await rm(root, { recursive: true, force: true });
}
