// Protocol, monitor and lifecycle checks against the real delivered packages.
import assert from 'node:assert/strict';
import {after, before, describe, test} from 'node:test';
import {cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {
  AdapterProcess, appendRaw, appendRecord, cliPackage, desktopPackage, hookRecord,
  isolatedEnvironment, rotateSpool, sha256File, spoolDirectory, writeForeignDirectory,
} from './harness.mjs';

describe('protocol', () => {
  let environment;
  let adapter;

  before(() => {
    environment = isolatedEnvironment('minimax-protocol');
    adapter = new AdapterProcess(cliPackage, environment);
  });

  after(async () => {
    await adapter.stop();
    environment.cleanup();
  });

  test('hello declares protocol version 1', async () => {
    assert.deepEqual(await adapter.call('hello'), {protocolVersion: 1});
  });

  test('inspect is read-only and reports notInstalled before installation', async () => {
    const beforeListing = readFileSync(cliPackage + '/manifest.json', 'utf8');
    const result = await adapter.call('inspect');
    assert.equal(result.status, 'notInstalled');
    assert.match(result.detail, /char-observer/);
    assert.equal(readFileSync(cliPackage + '/manifest.json', 'utf8'), beforeListing);
    assert.equal(existsSync(environment.pluginDir), false);
  });

  test('unknown methods fail with an error frame', async () => {
    const frame = await adapter.send('teleport', {});
    assert.match(frame.error, /unknown method/);
    assert.equal(frame.version, 1);
  });

  test('malformed protocol versions are rejected', async () => {
    const frame = await adapter.send('hello', {}, 5000);
    assert.ok(frame.result || frame.error);
  });

  test('stdout carries protocol frames only', () => {
    assert.deepEqual(adapter.unmatched, []);
  });

  test('stdin close ends the process', async () => {
    const closing = new AdapterProcess(cliPackage, environment);
    await closing.call('hello');
    closing.closeStdin();
    const exit = await closing.exited;
    assert.equal(exit.code, 0);
  });

  test('EOF drains an admitted delegated inspect', async () => {
    const closing = new AdapterProcess(cliPackage, environment);
    const response = closing.call('inspect');
    closing.closeStdin();
    assert.equal((await response).status, 'notInstalled');
    assert.equal((await closing.exited).code, 0);
  });

  test('a slow helper does not block monitor events', async () => {
    const fresh = isolatedEnvironment('minimax-helper-independent');
    const packageCopy = join(fresh.root, 'package.charintegration');
    cpSync(cliPackage, packageCopy, {recursive: true});
    writeFileSync(join(packageCopy, 'adapter/adapter.mjs'), `import {createInterface} from 'node:readline';
const reader=createInterface({input:process.stdin});
reader.on('line',async line=>{const request=JSON.parse(line);await new Promise(r=>setTimeout(r,700));console.log(JSON.stringify({version:1,id:request.id,result:{status:'notInstalled'}}));});`);
    const independent = new AdapterProcess(packageCopy, fresh);
    try {
      await independent.call('start');
      let answered = false;
      const reply = independent.call('inspect').then(result=>{answered=true;return result;});
      appendRecord(fresh, hookRecord({sid:'mvs_during_helper'}));
      await independent.waitForEvents(1,500);
      assert.equal(independent.events.length,1,'event is forwarded while helper is still waiting');
      assert.equal(answered,false);
      assert.equal((await reply).status,'notInstalled');
    } finally {await independent.stop();fresh.cleanup();}
  });

  test('SIGTERM ends the process', async () => {
    const terminating = new AdapterProcess(cliPackage, environment);
    await terminating.call('hello');
    const exit = await terminating.stop('SIGTERM');
    assert.equal(exit.code, 0);
  });
});

describe('monitor', () => {
  let environment;
  let adapter;

  before(async () => {
    environment = isolatedEnvironment('minimax-monitor');
    adapter = new AdapterProcess(cliPackage, environment);
  });

  after(async () => {
    await adapter.stop();
    environment.cleanup();
  });

  test('start baselines the spool instead of replaying history', async () => {
    appendRecord(environment, hookRecord({ev: 'Stop', signal: 'turnEnded', state: 'stopped'}));
    await adapter.call('start');
    await adapter.call('stop');
    assert.deepEqual(adapter.events, []);
  });

  test('start and stop are idempotent', async () => {
    await adapter.call('start');
    await adapter.call('start');
    await adapter.call('stop');
    await adapter.call('stop');
  });

  test('a full lifecycle publishes workEnd, states and reasons', async () => {
    const session = 'mvs_lifecycle_session';
    const before = adapter.events.length;
    await adapter.call('start');
    appendRecord(environment, hookRecord({sid: session, ev: 'UserPromptSubmit', signal: 'running', state: 'running'}));
    appendRecord(environment, hookRecord({sid: session, ev: 'PermissionRequest', signal: 'approval', state: 'stopped'}));
    appendRecord(environment, hookRecord({sid: session, ev: 'Stop', signal: 'turnEnded', state: 'stopped'}));
    appendRecord(environment, hookRecord({sid: session, ev: 'SessionEnd', signal: 'closed', state: 'closed'}));
    await adapter.waitForEvents(before + 4);
    await adapter.call('stop');
    assert.equal(adapter.events.length, before + 4);
    const [running, approval, turnEnded, closed] = adapter.events.slice(before);
    assert.deepEqual(
      running,
      {workEnd: 'minimaxcode.cli', nativeID: session, timestamp: running.timestamp, state: 'running',
        target: {processID: process.pid, sourcePath: '/private/tmp/example'}},
    );
    assert.equal(running.timestamp, new Date(running.timestamp).toISOString());
    assert.equal(approval.reason, 'approval');
    assert.equal(approval.state, 'stopped');
    assert.equal(turnEnded.reason, 'turnEnded');
    assert.equal(closed.state, 'closed');
    assert.equal(closed.reason, undefined);
    for (const event of adapter.events.slice(before)) assert.equal(event.workEnd, 'minimaxcode.cli');
  });

  test('other surfaces never leak into this work end', async () => {
    const before = adapter.events.length;
    appendRecord(environment, hookRecord({surface: 'desktop', sid: 'mvs_desktop_only'}));
    appendRecord(environment, hookRecord({surface: 'unknown', sid: 'mvs_unknown_surface'}));
    await adapter.call('start');
    await new Promise((resolve) => setTimeout(resolve, 300));
    await adapter.call('stop');
    assert.equal(adapter.events.length, before);
  });

  test('a question is only published for the native ask_user tool boundary', async () => {
    const before = adapter.events.length;
    await adapter.call('start');
    appendRecord(environment, hookRecord({sid: 'mvs_question', ev: 'PreToolUse', signal: 'question', state: 'stopped'}));
    appendRecord(environment, hookRecord({sid: 'mvs_question', ev: 'PostToolUse', signal: 'running', state: 'running'}));
    await adapter.waitForEvents(before + 2);
    await adapter.call('stop');
    const question = adapter.events.at(-2);
    const resumed = adapter.events.at(-1);
    assert.equal(question.state, 'stopped');
    assert.equal(question.reason, 'question');
    assert.equal(resumed.state, 'running');
  });

  test('child boundaries stay out of the root alerts', async () => {
    const before = adapter.events.length;
    await adapter.call('start');
    appendRecord(environment, hookRecord({sid: 'mvs_root', ev: 'UserPromptSubmit'}));
    appendRecord(environment, hookRecord({
      sid: 'mvs_root', ev: 'SubagentStart', signal: 'childStarted', state: 'running',
      agent: 'agent_1', agentType: 'general',
    }));
    appendRecord(environment, hookRecord({
      sid: 'mvs_root', ev: 'SubagentStop', signal: 'childStopped', state: 'stopped',
      agent: 'agent_1', agentType: 'general',
    }));
    await adapter.waitForEvents(1);
    await new Promise((resolve) => setTimeout(resolve, 250));
    await adapter.call('stop');
    assert.equal(adapter.events.length, before + 1);
    assert.equal(adapter.events.at(-1).nativeID, 'mvs_root');
  });

  test('two sessions that share a long prefix stay distinct', async () => {
    const prefix = 'mvs_0000000000000000000000000000';
    const before = adapter.events.length;
    await adapter.call('start');
    appendRecord(environment, hookRecord({sid: `${prefix}aaa1`}));
    appendRecord(environment, hookRecord({sid: `${prefix}bbb2`}));
    await adapter.waitForEvents(before + 2);
    await adapter.call('stop');
    const ids = adapter.events.slice(before).map((event) => event.nativeID);
    assert.deepEqual(ids, [`${prefix}aaa1`, `${prefix}bbb2`]);
    assert.ok(ids[0] !== ids[1] && ids[0].length <= 1024 && ids[1].length <= 1024);
  });

  test('half written lines are withheld until they are complete', async () => {
    const before = adapter.events.length;
    await adapter.call('start');
    const session = 'mvs_half_line';
    const record = hookRecord({sid: session});
    const line = JSON.stringify(record);
    const split = Math.floor(line.length / 2);
    appendRaw(environment, `${line.slice(0, split)}`);
    await new Promise((resolve) => setTimeout(resolve, 200));
    const midway = adapter.events.length;
    appendRaw(environment, `${line.slice(split)}\n`);
    await adapter.waitForEvents(midway + 1);
    await adapter.call('stop');
    assert.equal(adapter.events.length, midway + 1);
    assert.equal(adapter.events.at(-1).nativeID, session);
  });

  test('UTF-8 split at a read boundary preserves bytes and later records', async () => {
    const fresh = isolatedEnvironment('minimax-utf8');
    const reader = new AdapterProcess(cliPackage, fresh);
    try {
      await reader.call('start');
      const prefix = Buffer.from('{"padding":"');
      const padding = Buffer.alloc(524288 - prefix.length - 1, 32);
      const first = Buffer.concat([prefix, padding, Buffer.from('你",'), Buffer.from(JSON.stringify(hookRecord({sid: 'mvs_unicode', cwd: '/tmp/你好'})).slice(1) + '\n')]);
      appendRaw(fresh, first);
      appendRecord(fresh, hookRecord({sid: 'mvs_after_unicode'}));
      await reader.waitForEvents(2);
      assert.equal(reader.events.length, 2);
      assert.equal(reader.events[0].target.sourcePath, '/tmp/你好');
      assert.equal(reader.events[1].nativeID, 'mvs_after_unicode');
    } finally { await reader.stop(); fresh.cleanup(); }
  });

  test('a burst larger than two read windows arrives without new input', async () => {
    const adapter2 = new AdapterProcess(cliPackage, environment);
    await adapter2.call('start');
    const session = 'mvs_burst';
    const total = 4000;
    let text = '';
    for (let index = 0; index < total; index += 1) {
      text += `${JSON.stringify(hookRecord({sid: session, ts: new Date(1700000000000 + index).toISOString()}))}\n`;
    }
    appendRaw(environment, text);
    const seen = await adapter2.waitForEvents(total, 20000);
    await adapter2.stop();
    assert.equal(seen, total);
    assert.equal(adapter2.unmatched.length, 0);
  });

  test('concurrent hook writers never interleave a record', async () => {
    const adapter3 = new AdapterProcess(cliPackage, environment);
    await adapter3.call('start');
    const sessions = Array.from({length: 200}, (_, index) => `mvs_parallel_${index}`);
    await Promise.all(sessions.map(async (sid) => {
      for (let repeat = 0; repeat < 5; repeat += 1) {
        appendRecord(environment, hookRecord({sid}));
        await new Promise((resolve) => setImmediate(resolve));
      }
    }));
    const seen = await adapter3.waitForEvents(1000, 20000);
    await adapter3.stop();
    assert.equal(seen, 1000);
    const ids = new Set(adapter3.events.map((event) => event.nativeID));
    assert.equal(ids.size, 200);
  });

  test('rotation keeps the subscription alive', async () => {
    const adapter4 = new AdapterProcess(cliPackage, environment);
    await adapter4.call('start');
    appendRecord(environment, hookRecord({sid: 'mvs_before_rotation'}));
    await adapter4.waitForEvents(1);
    rotateSpool(environment);
    await new Promise((resolve) => setTimeout(resolve, 200));
    appendRecord(environment, hookRecord({sid: 'mvs_after_rotation'}));
    await adapter4.waitForEvents(2);
    appendRecord(environment, hookRecord({sid: 'mvs_later_append'}));
    await adapter4.waitForEvents(3);
    await adapter4.stop();
    assert.deepEqual(adapter4.events.map((event) => event.nativeID), ['mvs_before_rotation', 'mvs_after_rotation', 'mvs_later_append']);
  });

  test('a missing spool file is created later without restarting the adapter', async () => {
    const fresh = isolatedEnvironment('minimax-monitor-late');
    const late = new AdapterProcess(cliPackage, fresh);
    await late.call('start');
    await new Promise((resolve) => setTimeout(resolve, 150));
    appendRecord(fresh, hookRecord({sid: 'mvs_late_start', surface: 'cli'}));
    const seen = await late.waitForEvents(1);
    await late.stop();
    fresh.cleanup();
    assert.equal(seen, 1);
    assert.equal(late.events[0].nativeID, 'mvs_late_start');
  });

  test('a session whose client process disappears is closed', async () => {
    const fresh = isolatedEnvironment('minimax-monitor-exit');
    const closed = new AdapterProcess(cliPackage, fresh);
    // 2^22 is above the default pid_max on macOS, so it can never be alive.
    await closed.call('start');
    appendRecord(fresh, hookRecord({sid: 'mvs_dead_client', pid: 4194303}));
    await closed.waitForEvents(1);
    await closed.waitForEvents(2, 12000);
    await closed.stop();
    fresh.cleanup();
    assert.equal(closed.events.length, 2);
    assert.equal(closed.events[1].state, 'closed');
    assert.equal(closed.events[1].nativeID, 'mvs_dead_client');
  });
});

describe('lifecycle', () => {
  let environment;
  let cli;

  before(() => {
    environment = isolatedEnvironment('minimax-lifecycle');
    cli = new AdapterProcess(cliPackage, environment, {pluginID: 'minimax.code.cli'});
  });

  after(async () => {
    await cli.stop();
    environment.cleanup();
  });

  test('install writes the shared native plugin and reports ready', async () => {
    const result = await cli.call('install', {}, 15000);
    assert.equal(result.status, 'ready');
    assert.ok(existsSync(join(environment.pluginDir, '.minimax-plugin', 'plugin.json')));
    assert.ok(existsSync(join(environment.pluginDir, 'hooks', 'hooks.json')));
    assert.ok(existsSync(join(environment.pluginDir, 'hooks', 'emit.mjs')));
    assert.ok(existsSync(environment.marker));
    assert.ok(existsSync(spoolDirectory(environment)));
  });

  test('inspect is ready after installation', async () => {
    const result = await cli.call('inspect');
    assert.equal(result.status, 'ready');
    assert.match(result.detail, /minimax\.code\.cli/);
  });

  test('install is idempotent', async () => {
    const before = sha256File(join(environment.pluginDir, 'hooks', 'hooks.json'));
    const result = await cli.call('install', {}, 15000);
    assert.equal(result.status, 'ready');
    assert.equal(sha256File(join(environment.pluginDir, 'hooks', 'hooks.json')), before);
  });

  test('unrelated files inside the plugin data directory survive uninstall', async () => {
    mkdirSync(spoolDirectory(environment), {recursive: true});
    writeFileSync(join(spoolDirectory(environment), 'unrelated.txt'), 'keep me\n');
    const result = await cli.call('uninstall', {}, 15000);
    assert.equal(result.status, 'ready');
    assert.equal(existsSync(environment.pluginDir), false);
    assert.equal(existsSync(environment.marker), false);
    assert.equal(readFileSync(join(spoolDirectory(environment), 'unrelated.txt'), 'utf8'), 'keep me\n');
  });

  test('a foreign directory with the same name is never taken over or removed', async () => {
    const foreign = isolatedEnvironment('minimax-lifecycle-foreign');
    writeForeignDirectory(foreign, 'char-observer', {'keep.txt': 'user data\n'});
    const adapter = new AdapterProcess(cliPackage, foreign);
    const install = await adapter.call('install', {}, 15000);
    assert.equal(install.status, 'unavailable');
    assert.match(install.detail, /refused to take over/);
    const inspect = await adapter.call('inspect');
    assert.equal(inspect.status, 'notInstalled');
    const uninstall = await adapter.call('uninstall', {}, 15000);
    assert.equal(uninstall.status, 'notInstalled');
    assert.equal(readFileSync(join(foreign.pluginDir, 'keep.txt'), 'utf8'), 'user data\n');
    await adapter.stop();
    foreign.cleanup();
  });

  test('both packages share one native plugin and uninstall order is safe', async () => {
    const shared = isolatedEnvironment('minimax-lifecycle-shared');
    const cliAdapter = new AdapterProcess(cliPackage, shared, {pluginID: 'minimax.code.cli'});
    const desktopAdapter = new AdapterProcess(desktopPackage, shared, {pluginID: 'minimax.code.desktop'});
    await cliAdapter.call('install', {}, 15000);
    await desktopAdapter.call('install', {}, 15000);
    assert.ok(existsSync(join(shared.pluginDir, 'hooks', 'hooks.json')));

    const cliRemoval = await cliAdapter.call('uninstall', {}, 15000);
    assert.equal(cliRemoval.status, 'ready');
    assert.match(cliRemoval.detail, /minimax\.code\.desktop/);
    assert.ok(existsSync(join(shared.pluginDir, 'hooks', 'hooks.json')), 'desktop keeps using the shared plugin');

    const desktopInspect = await desktopAdapter.call('inspect');
    assert.equal(desktopInspect.status, 'ready');

    const desktopRemoval = await desktopAdapter.call('uninstall', {}, 15000);
    assert.equal(desktopRemoval.status, 'ready');
    assert.equal(existsSync(shared.pluginDir), false);
    const cliInspect = await cliAdapter.call('inspect');
    assert.equal(cliInspect.status, 'notInstalled');
    await cliAdapter.stop();
    await desktopAdapter.stop();
    shared.cleanup();
  });

  test('a modified installation is reported as unavailable and update restores it', async () => {
    const drifted = isolatedEnvironment('minimax-lifecycle-drift');
    const adapter = new AdapterProcess(cliPackage, drifted);
    await adapter.call('install', {}, 15000);
    writeFileSync(join(drifted.pluginDir, 'hooks', 'hooks.json'), '{"hooks":{}}\n');
    const driftedInspect = await adapter.call('inspect');
    assert.equal(driftedInspect.status, 'unavailable');
    const updated = await adapter.call('update', {}, 15000);
    assert.equal(updated.status, 'ready');
    const restored = await adapter.call('inspect');
    assert.equal(restored.status, 'ready');
    assert.ok(readFileSync(join(drifted.pluginDir, 'hooks', 'hooks.json'), 'utf8').includes('SessionStart'));
    await adapter.stop();
    drifted.cleanup();
  });
});

describe('navigation', () => {
  test('visit refuses a dead client PID even when another real client is running', async () => {
    const environment = isolatedEnvironment('minimax-visit');
    const adapter = new AdapterProcess(cliPackage, environment);
    const result = await adapter.call('visit', {nativeID: 'mvs_visit', processID: 4194303, bundleIdentifier: 'dev.warp.Warp-Stable'});
    assert.equal(result.outcome, 'unavailable');
    assert.equal(result.verified, undefined);
    await adapter.stop();
    environment.cleanup();
  });

  test('visit requires a native session id', async () => {
    const environment = isolatedEnvironment('minimax-visit-missing');
    const adapter = new AdapterProcess(cliPackage, environment);
    const frame = await adapter.send('visit', {});
    assert.match(frame.error, /nativeID/);
    await adapter.stop();
    environment.cleanup();
  });
});