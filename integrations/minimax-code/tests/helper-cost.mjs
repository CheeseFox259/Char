// One isolated on-demand inspect: lifetime high-water RSS and total request time.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {AdapterProcess,cliPackage,isolatedEnvironment,workspace} from './harness.mjs';
const environment=isolatedEnvironment('minimax-helper-cost');
const adapter=new AdapterProcess(cliPackage,environment);
try {
  await adapter.call('hello');
  const started=performance.now();
  const result=await adapter.call('inspect');
  const totalMs=performance.now()-started;
  assert.equal(result.status,'notInstalled');
  assert.equal(spawnSync('/usr/bin/pgrep',['-P',String(adapter.child.pid)],{encoding:'utf8'}).status,1,'no resident helper after response');
  const manifest=JSON.parse(readFileSync(join(cliPackage,'manifest.json'),'utf8'));
  // /usr/bin/time reports lifetime high-water resident bytes on macOS.
  const measured=spawnSync('/usr/bin/time',['-l',process.execPath,join(cliPackage,'adapter/adapter.mjs')],{
    env:{...process.env,HOME:join(environment.root,'home'),MINIMAX_DATA_DIR:environment.dataDir,CHAR_SUPPORT_DIRECTORY:environment.supportDir,CHAR_PLUGIN_DIRECTORY:cliPackage,CHAR_PLUGIN_ID:manifest.id,CHAR_PLUGIN_VERSION:manifest.version,CHAR_WORK_END:manifest.workEnd,CHAR_PLUGIN_CONFIG:JSON.stringify(manifest.adapter.configuration)},
    input:JSON.stringify({version:1,id:'measure-helper',method:'inspect',params:{}})+'\n',encoding:'utf8',timeout:3000,
  });
  assert.equal(measured.status,0,measured.stderr);
  assert.equal(JSON.parse(measured.stdout.trim()).result.status,'notInstalled');
  const bytes=Number(measured.stderr.match(/(\d+)\s+maximum resident set size/)[1]);
  const report={operation:'isolated notInstalled inspect; no real client writes or model requests',adapterVersion:manifest.version,node:process.version,nativeTotalRequestMs:totalMs,helperLifetimePeakRSSMiB:bytes/1048576,helperMeasurement:'same delegated Node command measured separately via macOS time -l; peak excludes native parent',childrenAfterResponse:0,maintenanceAndVisitPeaks:'not measured',raw:measured.stderr};
  assert.ok(totalMs<3000);
  mkdirSync(join(workspace,'reports'),{recursive:true});
  writeFileSync(join(workspace,'reports','performance-helper.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
} finally { await adapter.stop(); environment.cleanup(); }
