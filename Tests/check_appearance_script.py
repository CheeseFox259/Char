#!/usr/bin/env python3
import json, subprocess, sys
process = subprocess.Popen([sys.argv[1]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
def request(id, **fields):
    process.stdin.write(json.dumps(dict(id=id,**fields))+'\n'); process.stdin.flush()
    reply=json.loads(process.stdout.readline()); assert reply['id']==id; return reply
try:
    source="let count=0; function onEvent(e){return [{type:'playClip',value:String(++count)}]}"
    assert request(1,method='init',source=source)['actions']==[]
    assert request(2,method='event',event={'name':'click'})['actions'][0]['value']=='1'
    assert request(3,method='event',event={'name':'click'})['actions'][0]['value']=='2'
    assert 'error' in request(4,method='init',source="throw new Error('intentional')")
    assert request(5,method='init',source="function onEvent(e){return [{type:'playClip',value:[typeof process,typeof require,typeof fetch,typeof ObjC].join(',')}]} ")['actions']==[]
    assert request(6,method='event',event={'name':'click'})['actions'][0]['value']=='undefined,undefined,undefined,undefined'
    process.stdin.close(); assert process.wait(timeout=3)==0
finally:
    if process.poll() is None: process.kill(); process.wait()
print('Appearance script: JSONL/state/exception/no OS bridge/EOF passed')
