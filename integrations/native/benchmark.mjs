// Optional isolated microbenchmark. No client launch, installation or model request.
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { observation, appendObservation } from './event-writer.mjs';
const binary=resolve(process.argv[2] || 'build/Char.app/Contents/MacOS/char-hook');
const directory=mkdtempSync(tmpdir()+'/char-native-benchmark-');
const summary=samples=>{samples.sort((a,b)=>a-b);return {medianMs:samples[Math.floor(samples.length/2)],p95Ms:samples[Math.ceil(samples.length*.95)-1],samples:samples.length};};
try {
  const results={};
  for(const end of ['pi','deepseekDesktop']) {
    const time=Date.now(),target={bundleIdentifier:end==='pi'?'dev.warp.Warp-Stable':'com.deepseek.dsh'};
    const payload=end==='pi'?{schema:1,session_id:'fixture',event:'running',timestamp:new Date(time).toISOString()}
      :{client_type:'deepseek_desktop',root_session:true,session_id:'fixture',kind:'running',time};
    const event=observation(end,'fixture',target,time,'running'), before=[],after=[];
    for(let n=0;n<65;n++) {
      let start=performance.now();execFileSync(binary,[end==='pi'?'--pi':'--deepseek'],{input:JSON.stringify(payload),env:{...process.env,CHAR_HOOK_EVENTS:directory+'/old'}});
      if(n>=5)before.push(performance.now()-start);
      start=performance.now();appendObservation(directory+'/new',event);if(n>=5)after.push(performance.now()-start);
    }
    results[end]={processPerEvent:summary(before),inRuntime:summary(after)};
  }
  console.log(JSON.stringify({scope:'local metadata append only; 5 warmup + 60 events per mode; excludes host polling, UI and external client',results},null,2));
} finally {rmSync(directory,{recursive:true,force:true});}
