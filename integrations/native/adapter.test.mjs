import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, readFile, rm, access, realpath} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createInterface} from 'node:readline';
const root=await realpath(await mkdtemp(join(tmpdir(),'char-native-lifecycle-')));
const native=resolve('integrations'), binary=await realpath(resolve(process.argv[2]));
function connection(workEnd, configuration={}) {
  const child=spawn(process.execPath,[join(native,'native/adapter.mjs')], {env:{...process.env,HOME:root,KIMI_CODE_HOME:join(root,'.kimi-code'),CHAR_PLUGIN_ID:workEnd,CHAR_WORK_END:workEnd,CHAR_PLUGIN_CONFIG:JSON.stringify(configuration),CHAR_SUPPORT_DIRECTORY:root,CHAR_NATIVE_ROOT:native,CHAR_HOOK_BINARY:binary,CHAR_HOOK_EVENTS:join(root,'events.jsonl')},stdio:['pipe','pipe','pipe']});
  child.stderr.resume(); let n=0; const pending=new Map();
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line); const p=pending.get(r.id); pending.delete(r.id); if(r.error)p.reject(new Error(r.error));else p.resolve(r.result);});
  return {request(method,params={}) {const id=String(++n); return new Promise((resolve,reject)=>{pending.set(id,{resolve,reject});child.stdin.write(JSON.stringify({version:1,id,method,params})+'\n');});},end(){child.stdin.end();},close(){child.stdin.end();child.kill();}};
}
const connections=[];
try {
  const eof=connection('pi');connections.push(eof);
  const response=eof.request('inspect');eof.end();
  assert.equal((await Promise.race([response,new Promise((_,reject)=>{const t=setTimeout(()=>reject(new Error('EOF dropped inspect response')),3000);t.unref();})])).status,'notInstalled');
  const pi=connection('pi');connections.push(pi);
  assert.equal((await pi.request('inspect')).status,'notInstalled');
  assert.equal((await pi.request('install')).status,'reloadRequired');
  assert.equal((await pi.request('inspect')).status,'ready');
  const piDir=join(root,'.pi/agent/extensions/char');
  await writeFile(join(piDir,'unrelated.txt'),'user data');
  assert((await readFile(join(piDir,'index.js'),'utf8')).includes(JSON.stringify(binary)));
  await pi.request('update');await pi.request('uninstall');
  assert.equal(await readFile(join(piDir,'unrelated.txt'),'utf8'),'user data');
  assert.equal((await pi.request('inspect')).status,'notInstalled');
  const config=join(root,'.kimi-code/config.toml');await mkdir(join(root,'.kimi-code'),{recursive:true});
  const user='model = "user-model"\n\n[[hooks]]\nevent = "SessionStart"\ncommand = "echo user-hook"\n';
  await writeFile(config,user);
  const kimi=connection('kimiCLI');connections.push(kimi);
  await kimi.request('install');assert.equal((await kimi.request('inspect')).status,'ready');
  const installed=await readFile(config,'utf8');assert(installed.startsWith(user));
  await kimi.request('update');assert.equal(await readFile(config,'utf8'),installed);
  await kimi.request('uninstall',{retainSharedIntegration:true});assert.equal(await readFile(config,'utf8'),installed);
  await kimi.request('uninstall');assert.equal((await readFile(config,'utf8')).trim(),user.trim());
  assert.equal((await kimi.request('inspect')).status,'notInstalled');
  const profile=join(root,'.dsh/profiles/desktop/cordis.patch.yml');await mkdir(join(root,'.dsh/profiles/desktop'),{recursive:true});
  const original='- insert:\n    - id: user-plugin\n      name: user.module\n      config:\n        key: value\n';
  await writeFile(profile,original);
  const deep=connection('deepseekDesktop');connections.push(deep);
  await deep.request('install');assert.equal((await deep.request('inspect')).status,'ready');
  const deepInstalled=await readFile(profile,'utf8');assert(deepInstalled.startsWith(original));
  await deep.request('update');assert.equal(await readFile(profile,'utf8'),deepInstalled);
  await deep.request('uninstall');assert.equal((await readFile(profile,'utf8')).trim(),original.trim());
  // A Char mount shared with unrelated plugins must not consume their insert table.
  await writeFile(profile,'- insert:\n    - id: char-desktop-observer\n      name: old.path\n    - id: other\n      name: other.module\n');
  await deep.request('uninstall');assert.equal(await readFile(profile,'utf8'),'- insert:\n    - id: other\n      name: other.module\n');
  await access(join(root,'integration-backups'));
  console.log('Native lifecycle: temporary Pi/Kimi/DeepSeek inspect/install/update/uninstall, private backups and unrelated config preservation passed');
} finally {connections.forEach(c=>c.close());await rm(root,{recursive:true,force:true});}
