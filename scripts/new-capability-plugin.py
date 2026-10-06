#!/usr/bin/env python3
"""Create a v3 package skeleton. Does not install or modify client settings."""
import argparse
import json
import pathlib
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('directory', type=pathlib.Path)
p.add_argument('--id', required=True)
p.add_argument('--name', required=True)
p.add_argument('--bundle', required=True)
p.add_argument('--work-end')
p.add_argument('--interface', choices=['cli', 'desktop', 'application'], default='application')
p.add_argument('--capabilities', required=True, help='comma-separated monitor,visit,origin,lifecycle')
a = p.parse_args()
caps = a.capabilities.split(',')
if any(c not in ['monitor', 'visit', 'origin', 'lifecycle'] for c in caps) or len(caps) != len(set(caps)):
    p.error('choose unique supported capabilities')
if 'monitor' in caps and not a.work_end:
    p.error('monitor requires --work-end')
for value in [a.id] + ([a.work_end] if a.work_end else []):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', value):
        p.error('invalid namespaced identity')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+', a.bundle):
    p.error('invalid bundle identifier')
if not a.name.strip() or len(a.name) > 100:
    p.error('invalid name')
if a.directory.exists():
    p.error('output directory already exists')
a.directory.mkdir(parents=True)
manifest = dict(schemaVersion=3,id=a.id,name=a.name,bundleIdentifier=a.bundle,version='0.1.0',clientInterface=a.interface,
                adapter=dict(runtime='node',entrypoint='adapter.mjs',protocolVersion=1,capabilities=caps,configuration={}))
if a.work_end: manifest['workEnd'] = a.work_end
(a.directory/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(a.directory/'adapter.mjs').write_text('''import {createInterface} from 'node:readline';
// Implement only declared capabilities using the target client's documented APIs.
// stdout is protocol-only. Never claim ready/exact until verified.
async function handle(method, params) {
  if (method === 'hello') return {protocolVersion:1};
  if (method === 'inspect') return {status:'notInstalled',detail:'Adapter implementation is pending.'};
  throw new Error(`Unimplemented capability method: ${method}`);
}
let queue = Promise.resolve();
createInterface({input:process.stdin}).on('line',line=>{
  queue = queue.then(async()=>{
    let request;
    try {
      request=JSON.parse(line);
      if(request.version!==1) throw new Error('Unsupported protocol');
      const result=await handle(request.method,request.params||{});
      console.log(JSON.stringify({version:1,id:request.id,result}));
    } catch(error) {console.log(JSON.stringify({version:1,id:request?.id,error:error.message}));}
  });
});
''')
print(a.directory.resolve())
print('Skeleton only: implement declared capabilities before delivery. See docs/capability-adapter-protocol.md.')
