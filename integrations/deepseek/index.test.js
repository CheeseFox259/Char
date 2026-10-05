import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { apply, observe, classify, isDesktopHostRuntime } from './index.js';

function context(root) {
  const handlers = new Map();
  const effects = [];
  return { handlers, effects, agents: { roots: () => [{ session: root }] }, logger: { warn() {} },
    on(name, fn) { handlers.set(name, fn); }, effect(fn) { effects.push(fn()); } };
}

test('Desktop host provenance rejects CLI and Web profiles', () => {
  const desktop = { argv:['node','/image/node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js'], connected:true, send(){} };
  assert.equal(isDesktopHostRuntime(desktop), true);
  assert.equal(isDesktopHostRuntime({...desktop, argv:['node','/image/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js']}), false);
  assert.equal(isDesktopHostRuntime({...desktop, connected:false}), false);
  assert.equal(isDesktopHostRuntime({...desktop, send:undefined}), false);
  assert.throws(() => apply({},{}), /native Desktop IPC host/);
});

test('structured lifecycle reasons only', () => {
  for (const [reason, result] of [['completed','turnEnded'], ['aborted','unclassified'], ['max-tokens','unclassified']]) {
    assert.equal(classify({ type:'turn/end', data:{ reason:{kind:reason} } }), result);
  }
  for (const [code,result] of [['RATE_LIMIT','rateLimit'], ['CONTEXT_WINDOW_EXCEEDED','contextExhausted'], ['UNKNOWN','failure']]) {
    assert.equal(classify({ type:'turn/end', data:{reason:{kind:'error',error:{code}}} }), result);
  }
  assert.equal(classify({type:'assistant/message',data:{text:'rate limit'}}),null);
  assert.equal(classify({type:'turn/end',data:{}}),null);
});

test('root-only native subscriptions, actual question, pending timeout and private metadata', async () => {
  const dir = mkdtempSync(join(tmpdir(),'char-deepseek-'));
  try {
    const output = join(dir,'output.jsonl');
    const binary = join(dir,'hook');
    writeFileSync(binary, '#!/usr/bin/env python3\nimport os,sys\nfd=os.open(os.environ["CHAR_HOOK_EVENTS"],os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)\nos.write(fd,sys.stdin.buffer.read()+b"\\n")\nos.close(fd)\n');
    chmodSync(binary,0o700);
    const root = {id:'root',header:{}};
    const ctx = context(root);
    observe(ctx,{hookBinary:binary,eventsFile:output});
    ctx.handlers.get('session/event')({id:'child',header:{origin:'subagent'}},{type:'turn/end',time:100,data:{reason:{kind:'completed'}}});
    ctx.handlers.get('session/event')(root,{type:'approval/asked',time:101,data:{secret:'do not store'}});
    const reason = Object.assign(new Error('timeout'),{code:'ASK_TIMED_OUT'});
    await assert.rejects(ctx.handlers.get('user-questions/request')({agent:{session:root},wait:{callId:'q'}},async()=>{throw reason;}), reason);
    ctx.handlers.get('session/event')(root,{type:'turn/end',time:102,data:{reason:{kind:'completed'}}});
    ctx.handlers.get('session/event')(root,{type:'user/message',time:103,data:{source:{kind:'user-question-reply',callId:'q'}}});
    ctx.handlers.get('session/event')(root,{type:'turn/end',time:104,data:{reason:{kind:'completed'}}});
    ctx.handlers.get('session/disposed')(root);
    await ctx.effects[0]();
    const text = readFileSync(output,'utf8');
    const events = text.trim().split('\n').map(JSON.parse);
    assert.equal(events.length,5);
    assert.equal(events.filter(e=>e.kind==='turnEnded').length,1);
    assert.ok(events.every(e=>e.session_id==='root' && e.client_type==='deepseek_desktop'));
    assert.ok(!text.includes('secret') && !text.includes('child') && !text.includes('timeout'));
    assert.ok(events.some(e=>e.kind==='question') && events.some(e=>e.kind==='closed'));
  } finally { rmSync(dir,{recursive:true,force:true}); }
});
