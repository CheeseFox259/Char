import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { observation, appendObservation } from './event-writer.mjs';

const binary = resolve(process.argv[2]);
const root = mkdtempSync(join(tmpdir(), 'char-event-writer-'));
try {
  // Differential check against the actual Swift Codable/classifier boundary.
  for (const end of ['pi', 'deepseekDesktop']) {
    for (const kind of end === 'pi' ? ['running','question','turnEnded','failure','unclassified','closed']
      : ['running','question','approval','turnEnded','failure','rateLimit','contextExhausted','unclassified','closed']) {
      const time = 1791331200123;
      const payload = end === 'pi' ? { schema:1, session_id:'parity', event:['running','question','closed'].includes(kind) ? kind : 'settled', reason:kind,
        timestamp:new Date(time).toISOString(), tmux_pane:'%1', process_id:123, session_file:'/fixture/session' }
        : { client_type:'deepseek_desktop', root_session:true, session_id:'parity', kind, time };
      const file = join(root, `${end}-${kind}`);
      execFileSync(binary,[end === 'pi' ? '--pi' : '--deepseek'],{input:JSON.stringify(payload),env:{...process.env,CHAR_HOOK_EVENTS:file}});
      const target = end === 'pi' ? {bundleIdentifier:'dev.warp.Warp-Stable',tmuxPaneID:'%1',processID:123,sourcePath:'/fixture/session'}
        : {bundleIdentifier:'com.deepseek.dsh'};
      const actual=observation(end,'parity',target,time,kind), expected=JSON.parse(readFileSync(file,'utf8'));
      assert(Math.abs(actual.timestamp-expected.timestamp)<0.000001, 'Timestamp changed beyond floating point rounding');
      actual.timestamp=expected.timestamp; assert.deepEqual(actual,expected);
    }
  }
  const events=join(root,'concurrent/events');
  const module=JSON.stringify(new URL('./event-writer.mjs',import.meta.url).href);
  const jobs=[];
  for(let n=0;n<3;n++) {
    const code=`import {appendObservation,observation} from ${module}; for(let i=0;i<50;i++) appendObservation(${JSON.stringify(events)},observation('pi','worker-${n}-'+i,{bundleIdentifier:'fixture'},Date.now(),'running'));`;
    const child=spawn(process.execPath,['--input-type=module','-e',code],{stdio:'ignore'});
    jobs.push(new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(new Error('Writer failed')));}));
  }
  // The old executable writer and the new in-runtime writer may share one stream.
  for(let n=0;n<10;n++) execFileSync(binary,['--pi'],{input:JSON.stringify({schema:1,session_id:`hook-${n}`,event:'running',timestamp:new Date().toISOString()}),env:{...process.env,CHAR_HOOK_EVENTS:events}});
  await Promise.all(jobs);
  const records=readFileSync(events,'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(records.length,160); assert.equal(new Set(records.map(r=>r.key.nativeID)).size,160);
  assert.equal(statSync(events).mode & 0o777,0o600);
  assert.throws(()=>appendObservation(events,observation('pi','x'.repeat(17000),{},Date.now(),'running')),/16 KiB/);
  assert.equal(readFileSync(events,'utf8').trim().split('\n').length,160);
  console.log('Native writer: Swift event parity, concurrent/mixed append, private permissions and bounded metadata passed');
} finally { rmSync(root,{recursive:true,force:true}); }
