#!/usr/bin/env python3
"""Small deterministic SDK capability fixture; no image generator or user environment writes."""
import json, math, struct, sys, wave, zlib
from pathlib import Path
root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)
def png(name, size, pixel):
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rows = b''.join(b'\0'+bytes(channel for x in range(size) for channel in pixel(x,y)) for y in range(size))
    data = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
    (root/name).write_bytes(data)
for name, color in [('body.png',(250,218,130,255)),('alternate.png',(128,201,239,255))]:
    png(name,128,lambda x,y,c=color: c if 20<x<108 and 18<y<118 else (0,0,0,0))
png('eyes.png',32,lambda x,y: (35,40,70,255) if (7<x<12 or 20<x<25) and 8<y<24 else (0,0,0,0))
png('head.png',32,lambda x,y: (230,105,142,255) if (x-16)**2+(y-16)**2<100 else (0,0,0,0))
png('shell.png',64,lambda x,y: (90,166,210,90) if 26<math.hypot(x-32,y-32)<31 else (0,0,0,0))
png('cli.png',32,lambda x,y: (80,40,125,255) if 2<x<30 and 2<y<30 else (0,0,0,0))
png('icon.png',128,lambda x,y: (250,218,130,255) if 10<x<100 and 20<y<110 else (0,0,0,0))
with wave.open(str(root/'tone.wav'),'wb') as audio:
    audio.setparams((1,2,8000,0,'NONE','not compressed'))
    audio.writeframes(b''.join(struct.pack('<h',int(1000*math.sin(i*math.pi/12))) for i in range(800)))
(root/'behavior.js').write_text('let visits = 0; function onEvent(event) { visits++; return event.name === "attention" ? [{type:"playClip",value:"celebrate"}] : []; }\n')
clip = lambda file: {'frames':[file,file],'fps':12}
clips = {name:clip('body.png') for name in ['idle','press','return','depart','arrive','edgePeek','edgeHide','celebrate']}
region = {'x':0.2,'y':0.2,'width':0.6,'height':0.6,'shape':'rect'}
features = {
 'variants':{'top':{'rotation':0,'anchor':{'x':0.5,'y':0.3},'clips':{'idle':clip('alternate.png')}},'left':{'mirrorX':True}},
 'tracking':{'eyes':[{'image':'eyes.png','rect':{'x':0.25,'y':0.35,'width':0.5,'height':0.2},'travelX':0.06,'travelY':0.04}], 'head':{'rect':{'x':0.4,'y':0.15,'width':0.2,'height':0.2},'poses':{'center':'head.png','e':'cli.png'}}},
 'bubbles':{'shell':'shell.png','cliBadge':'cli.png','statusColors':{'running':'#7354AA','ended':'#2A8760'},'fontName':'Menlo','fontSize':11,'hoverColor':'#778899','hoverGlow':0.12,'hoverAmplitude':0.12,'hoverDuration':1.4,'shatterDivisions':4,'shatterDuration':0.55,'shatterTravel':22,'orbitDuration':0.4,'orbitCurve':'smooth'},
 'themes':{'day':{'name':'Day'},'night':{'name':'Night','clips':{'idle':clip('alternate.png')},'appIcon':'icon.png','bubbles':{'shell':'shell.png','orbitDuration':0.35,'orbitCurve':'spring'}}},'defaultTheme':'day',
 'sounds':{'click':{'file':'tone.wav','volume':0.3,'cooldown':0.5}},'bindings':{'hoverEnter':[{'type':'playClip','value':'celebrate'}]},
 'behavior':{'click':'settings','bubbleClick':'visit','followFocus':True,'returnPolicy':'user','collision':'clamp','bubbleDistance':24,'edgeSnapDistance':50,'bubbleCapacity':4,'bubbleArcDegrees':120,'bubbleStartDegrees':70,'bubbleClockwise':True},
 'hitRegions':[region], 'script':'behavior.js','loopingClips':['idle']}
manifest={'schemaVersion':2,'id':'char.sdk-capabilities','name':'SDK capabilities','canvasSize':{'width':128,'height':128},'anchor':{'x':0.5,'y':0.5},'clips':clips,'appIcon':'icon.png','features':features}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(root)
