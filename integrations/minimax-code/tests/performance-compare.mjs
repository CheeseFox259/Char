import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {cpSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {AdapterProcess,cliPackage,desktopPackage,isolatedEnvironment,spoolDirectory,appendRecord,hookRecord,sleep,workspace} from './harness.mjs';
import {digestDirectory} from '../adapter/lib/client.mjs';

const environments=[], adapters=[];
const reports=join(workspace,'reports');mkdirSync(reports,{recursive:true});
const output=join(reports,'performance-optimized.json');
try {
  for (const [label,packageRoot,reference] of [['node-reference',cliPackage,true],['native-cli',cliPackage,false],['native-desktop',desktopPackage,false]]) {
    const env=isolatedEnvironment('minimax-performance'); environments.push(env);
    const manifest=JSON.parse(readFileSync(join(packageRoot,'manifest.json'),'utf8'));
    mkdirSync(spoolDirectory(env),{recursive:true});writeFileSync(env.spool,'');
    cpSync(join(packageRoot,'native-plugin'),env.pluginDir,{recursive:true});
    writeFileSync(env.marker,JSON.stringify({owners:{[manifest.id]:'1.0.0'},pluginVersion:'1.0.0',contentDigest:digestDirectory(env.pluginDir)}));
    const adapter=new AdapterProcess(packageRoot,env,{reference});adapters.push({label,adapter,env,manifest});
    await adapter.call('hello'); assert.equal((await adapter.call('inspect')).status,'ready'); await adapter.call('start');
  }
  await sleep(2000);
  const binary=join(workspace,'native-adapter/build/usage-sample');
  execFileSync('swiftc',['-O',join(workspace,'tests/usage-sample.swift'),'-o',binary]);
  const raw=execFileSync(binary,adapters.map(x=>String(x.adapter.child.pid)),{encoding:'utf8',timeout:30000});
  writeFileSync(join(reports,'performance-optimized-raw.jsonl'),raw);
  const samples=raw.trim().split('\n').map(JSON.parse);
  const results=[];
  for(const entry of adapters) {
    const rows=samples.filter(x=>x.pid===entry.adapter.child.pid);
    const summary={};
    for(const key of ['rssMiB','footprintMiB','cpuPercent']) {
      const values=rows.map(x=>x[key]).filter(x=>typeof x==='number');
      summary[key]={mean:values.reduce((a,b)=>a+b,0)/values.length,min:Math.min(...values),max:Math.max(...values)};
    }
    const latency=[];
    for(let i=0;i<20;i++) {
      const before=entry.adapter.events.length, started=performance.now();
      appendRecord(entry.env,hookRecord({sid:'performance-sequence',surface:entry.manifest.adapter.configuration.surface}));
      while(entry.adapter.events.length===before && performance.now()-started<2000) await sleep(1);
      assert.equal(entry.adapter.events.length,before+1,'no event loss');latency.push(performance.now()-started);
    }
    latency.sort((a,b)=>a-b);
    summary.appendToStdoutMs={samples:20,median:latency[10],p95:latency[18],max:latency[19]};
    if(entry.label.startsWith('native')) {assert.ok(summary.rssMiB.mean<25);assert.ok(summary.cpuPercent.mean<0.5);assert.ok(latency[18]<100);}
    results.push({label:entry.label,pid:entry.adapter.child.pid,...summary});
  }
  const report={conditions:{node:process.version,system:process.platform+' '+process.arch,warmupSeconds:2,samples:21,intervalSeconds:1,cpu:'native cumulative user+system delta, 100% per core',memory:'native RSS and physical footprint, not unique RAM',latency:'append -> adapter frame observed by test reader, includes <=1ms reader wakeup',nodeReference:'same package/behavior, Node entry retained as reference; current lazy imports',UI:'not measured',nativeHook:'unchanged 1.0.0; no client/model requests'},results};
  writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
} finally {
  for(const {adapter} of adapters) await adapter.stop();
  for(const env of environments) env.cleanup();
}
