#!/usr/bin/env python3
"""Reproducible layered Phoebe showcase. Run with Pillow + NumPy.
The master is the sole art source; motion is authored in normalized canvas space.
"""
from pathlib import Path
import json, math, hashlib, shutil, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from art import inpaint, resize_premultiplied, stroke_lid
from build import matrix, build_icon
ROOT = Path(__file__).resolve().parents[1]
SIZE, SS, FPS = 192, 3, 30
P = ROOT / 'packages/feibi.charpet'
RECT = dict(x=0,y=0,width=1,height=1)
REST = dict(sx=1.,sy=1.,rot=0.,skew=0.,dx=0.,dy=0.,alpha=1.)
DIRECTIONS = {'center':(0,0),'n':(0,-1),'ne':(1,-1),'e':(1,0),'se':(1,1),'s':(0,1),'sw':(-1,1),'w':(-1,0),'nw':(-1,-1)}

def save(image, directory, label):
    key = hashlib.sha256(image.tobytes()).hexdigest()[:16]
    name = f'{directory}/{label}-{key}.png'
    path=P/name; path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists(): image.save(path,optimize=True)
    return name

def affine(image, m, size=None):
    inverse=np.linalg.inv(m)
    return image.transform(size or image.size,Image.Transform.AFFINE,tuple(inverse[:2].flatten()),Image.Resampling.BICUBIC)

def theme(image, night):
    if not night:return image.copy()
    a=np.array(image).astype(float)
    # Cool rim light, with warm skin protected from a blue wash.
    rgb=a[:,:,:3]; warm=(rgb[:,:,0]>rgb[:,:,2]*1.15)&(rgb[:,:,0]>150)
    tinted=rgb*np.array([.88,.90,1.0])+np.array([6,7,17])
    rgb[:]=np.where(warm[:,:,None],rgb*.96+np.array([0,0,5]),tinted)
    return Image.fromarray(np.clip(a,0,255).astype('uint8'),'RGBA')

def layers():
    master=Image.open(ROOT/'art/master.png').convert('RGBA')
    box=master.getbbox(); cut=master.crop(box)
    h=SIZE*SS*.88; w=h*cut.width/cut.height
    placed=resize_premultiplied(cut,(round(w),round(h)))
    source=Image.new('RGBA',(SIZE*SS,SIZE*SS)); x=round((SIZE*SS-w)/2); y=round(SIZE*SS*.07)
    source.alpha_composite(placed,(x,y))
    # These reference coordinates are recorded against the immutable generated master.
    scale=h/cut.height
    def point(px,py):return (x+(px-box[0])*scale,y+(py-box[1])*scale)
    eye_boxes=[]
    for cx,cy,rx,ry in [(480,657,74,84),(744,657,76,86)]:
        l,t=point(cx-rx,cy-ry);r,b=point(cx+rx,cy+ry);eye_boxes.append((l,t,r,b))
    rgba=np.array(source); mask=Image.new('L',source.size)
    d=ImageDraw.Draw(mask)
    for l,t,r,b in eye_boxes:d.ellipse((l-2,t-2,r+2,b+2),fill=255)
    skin=inpaint(rgba[:,:,:3].astype(float),np.array(mask)>0,coarse=4,coarse_iters=600,fine_iters=100)
    cleaned=Image.fromarray(np.dstack([skin,rgba[:,:,3]]).clip(0,255).astype('uint8'),'RGBA')
    opened=cleaned.copy(); pupils=Image.new('RGBA',source.size)
    for l,t,r,b in eye_boxes:
        # Eye whites/lids stay on the head; iris and highlights are the native tracking layer.
        ImageDraw.Draw(opened).ellipse((l-1,t-1,r+1,b+1),fill=(255,250,247,255),outline=(37,15,21,255),width=4)
        iris_mask=Image.new('L',source.size);ImageDraw.Draw(iris_mask).ellipse((l+3,t+3,r-3,b-3),fill=255)
        pupils.alpha_composite(Image.composite(source,Image.new('RGBA',source.size),iris_mask))
    expressions={'open':opened}
    # Worried mouth replaces the smile; do not draw a second mouth over it.
    mouthmask=Image.new('L',source.size);ml,mt=point(575,719);mr,mb=point(634,754)
    ImageDraw.Draw(mouthmask).ellipse((ml,mt,mr,mb),fill=255)
    face=np.array(opened);filled=inpaint(face[:,:,:3].astype(float),np.array(mouthmask)>0,coarse=3,coarse_iters=400,fine_iters=80)
    concern=Image.fromarray(np.dstack([filled,face[:,:,3]]).clip(0,255).astype('uint8'),'RGBA')
    points=[(ml+(mr-ml)*(.2+.6*i/24),mt+(mb-mt)*(.65-.22*math.sin(math.pi*i/24))) for i in range(25)]
    ImageDraw.Draw(concern).line(points,fill=(170,94,122,255),width=3,joint='curve')
    expressions['concern']=concern
    for name,bow in [('blink',-.25),('happy',.28)]:
        image=cleaned.copy();draw=ImageDraw.Draw(image)
        for eye in eye_boxes:stroke_lid(draw,eye,(43,18,25,255),max(3,round((eye[3]-eye[1])*.09)),bow)
        expressions[name]=image
    # The face boundary is a continuous arc. Rear hair is kept on the body;
    # the front/head overlay hides its junction at the collar.
    headmask=Image.new('L',source.size); draw=ImageDraw.Draw(headmask)
    collar=point(640,791)[1]
    draw.rectangle((0,0,source.width,collar),fill=255)
    body=Image.composite(source,Image.new('RGBA',source.size),Image.eval(headmask,lambda v:255-v))
    heads={k:Image.composite(v,Image.new('RGBA',source.size),headmask) for k,v in expressions.items()}
    return source,body,heads,pupils,eye_boxes

def keyed(t, keys):
    for (a,va),(b,vb) in zip(keys,keys[1:]):
        if t<=b:
            x=max(0,min(1,(t-a)/(b-a)));e=x*x*(3-2*x)
            return va+(vb-va)*e
    return keys[-1][1]

def pose(t, clip):
    p=REST.copy(); state=None
    s=math.sin(2*math.pi*t)
    if clip in ('idle','focus','curious','concern','drag'):
        p.update(sx=1-.012*s,sy=1+.017*s,dy=-.45*s,rot=.55*math.sin(2*math.pi*t))
        if clip=='focus':p['rot']+=1.4;p['sy']*=1.018
        if clip=='curious':p['rot']+=3.5*math.sin(math.pi*t);p['dy']-=1.1*math.sin(math.pi*t)
        if clip=='concern':p['rot']-=2.7*math.sin(math.pi*t);state='concern'
        if clip=='drag':p['rot']+=3.4;p['sx']*=.985;p['sy']*=1.025
        if .73<t<.8:state='blink'
    elif clip=='press':
        a=keyed(t,[(0,0),(.12,-.14),(.32,1),(.57,-.3),(.78,.1),(1,0)]);p.update(sx=1+.085*a,sy=1-.095*a,dy=1.6*a,rot=-1.2*a);state='blink' if .12<t<.55 else None
    elif clip in ('return','celebrate'):
        a=math.sin(math.pi*t)**2;p.update(sx=1-.025*a,sy=1+.035*a,dy=-4*a,rot=1.9*math.sin(2*math.pi*t)*a);state='happy' if .15<t<.8 else None
    elif clip in ('depart','arrive'):
        f=t if clip=='depart' else 1-t;e=f*f*(3-2*f)
        # The host already scales the whole companion: local motion is subtle.
        p.update(sx=1-.055*e,sy=1-.025*e,dy=2*e,alpha=1-e)
        if clip=='arrive':
            rebound=keyed(t,[(0,0),(.65,0),(.8,.018),(.92,-.006),(1,0)])
            p['sx']+=rebound;p['sy']-=rebound
    return p,state

def metadata(p,state):
    m=matrix(p,1,(SIZE*.5,SIZE*.73));m[0,2]/=SIZE;m[1,2]/=SIZE
    f={'transform':[round(float(v),6) for v in (m[0,0],m[1,0],m[0,1],m[1,1],m[0,2],m[1,2])],'opacity':round(p['alpha'],6)}
    if state:f['state']=state
    return f

def main():
    if P.exists():shutil.rmtree(P)
    P.mkdir(parents=True)
    source,body,heads,pupils,eyes=layers()
    # Head states reuse the body, and closed expressions need no pupil image.
    tracks={}; icons={}
    for key,night in [('day',False),('night',True)]:
        hposes={}
        for direction,(gx,gy) in DIRECTIONS.items():
            m=matrix(dict(REST,rot=gx*.7,skew=gx*.003,dy=gy*.35),SS,(SIZE*.5,SIZE*.7))
            hposes[direction]=save(resize_premultiplied(affine(theme(heads['open'],night),m),(SIZE,SIZE)),'layers',key+'-'+direction)
        eye_layers=[]
        for index,(l,t,r,b) in enumerate(eyes):
            pupil=Image.new('RGBA',pupils.size);box=tuple(round(v) for v in (l,t,r,b))
            pupil.paste(pupils.crop(box),box[:2])
            iris=save(resize_premultiplied(theme(pupil,night),(SIZE,SIZE)),'layers',key+'-iris-'+str(index))
            clip={'x':l/(SIZE*SS),'y':t/(SIZE*SS),'width':(r-l)/(SIZE*SS),'height':(b-t)/(SIZE*SS),'shape':'ellipse'}
            eye_layers.append({'image':iris,'rect':RECT,'clipRegion':clip,'travelX':.022,'travelY':.020})
        track={'head':{'rect':RECT,'poses':hposes},'eyes':eye_layers,'states':{}}
        for expression in ['blink','happy','concern']:
            path=save(resize_premultiplied(theme(heads[expression],night),(SIZE,SIZE)),'layers',key+'-'+expression)
            track['states'][expression]={'head':{'rect':RECT,'poses':{'center':path}},'eyes':track['eyes'] if expression=='concern' else []}
        tracks[key]=track
        # Independent high-resolution icons use the original master rather than frame upsampling.
        icon=build_icon(theme(source,night),SIZE*SS,1024)
        if night:
            tile=np.array(icon).astype(float);tile[:,:,:3]=tile[:,:,:3]*[.86,.9,1]+[2,2,8];icon=Image.fromarray(tile.clip(0,255).astype('uint8'),'RGBA')
        icons[key]=save(icon,'icons',key)
    clips={}
    counts={'idle':45,'press':12,'return':18,'depart':14,'arrive':16,'curious':45,'focus':45,'concern':45,'celebrate':18,'drag':45}
    for name,n in counts.items():
        frames=[]; tf=[]
        # Supplemental expression loops share native body motion with idle.
        motion=name if name in ('idle','press','return','depart','arrive','celebrate') else 'idle'
        for i in range(n):
            t=i/n if motion=='idle' else i/(n-1)
            p,_=pose(t,motion); headpose,state=pose(t,name)
            if name=='celebrate':p,_=pose(t,'return')
            image=resize_premultiplied(affine(body,matrix(p,SS,(SIZE*.5,SIZE*.73))),(SIZE,SIZE))
            alpha=image.getchannel('A').point(lambda a:round(a*p['alpha']));image.putalpha(alpha)
            frames.append(save(image,'frames','body'));tf.append(metadata(headpose,state))
        clips[name]={'frames':frames,'fps':FPS,'trackingFrames':tf}
    variants={}
    # Each edge has an authored lean, anchor, timeline and mirrored stance.
    for edge,rot,lean,anchor,mirror in [('left',-90,-2.5,{'x':.5,'y':.64},False),('right',90,2.5,{'x':.5,'y':.64},True),('top',180,-1.2,{'x':.5,'y':.64},False),('bottom',0,1.2,{'x':.5,'y':.64},False)]:
        edgeclips={}
        for name,n in [('edgePeek',7),('edgeHide',6)]:
            frames=[]; tf=[]
            for i in range(n):
                t=i/n if name in ('idle','focus','curious','concern','drag') else i/(n-1)
                motion=name if name in ('idle','press','return','depart','arrive','celebrate') else 'idle'
                p,_=pose(t,motion); headpose,state=pose(t,name if name not in ('edgePeek','edgeHide') else 'idle')
                if name=='celebrate':p,_=pose(t,'return')
                if name in ('edgePeek','edgeHide'):
                    f=1-t if name=='edgePeek' else t;e=f*f*(3-2*f)
                    p.update(dy=SIZE*.70*e,alpha=1-e);headpose=dict(p);state=None
                image=resize_premultiplied(affine(body,matrix(p,SS,(SIZE*.5,SIZE*.73))),(SIZE,SIZE))
                image.putalpha(image.getchannel('A').point(lambda a:round(a*p['alpha'])))
                frames.append(save(image,'frames','body'));tf.append(metadata(headpose,state))
            edgeclips[name]={'frames':frames,'fps':FPS,'trackingFrames':tf}
        variants[edge]={'rotation':rot,'mirrorX':mirror,'anchor':anchor,'clips':edgeclips}
    # Base edge animation is available on desktop for format completeness.
    clips['edgePeek']=variants['bottom']['clips']['edgePeek'];clips['edgeHide']=variants['bottom']['clips']['edgeHide']
    bubble={}
    for key,color in [('day',(139,175,226)),('night',(167,148,227))]:
        shell=Image.new('RGBA',(192,192));d=ImageDraw.Draw(shell)
        d.ellipse((5,5,187,187),outline=(154,163,177,175),width=3)
        d.arc((9,9,183,183),195,255,fill=(*color,140),width=4)
        d.arc((13,13,179,179),220,265,fill=(255,255,255,125),width=2)
        shellpath=save(shell,'bubbles',key+'-shell')
        badge=Image.new('RGBA',(96,96));d=ImageDraw.Draw(badge)
        d.rounded_rectangle((7,12,89,82),radius=16,fill=(40,46,61,245),outline=(*color,255),width=4)
        d.line((26,32,39,45,26,57),fill=(250,252,255),width=6);d.line((48,59,69,59),fill=(250,252,255),width=5)
        badgepath=save(badge,'bubbles',key+'-terminal')
        bubble[key]={'shell':shellpath,'cliBadge':badgepath,'statusColors':{'pending':'#8B96C2','running':'#659ACB','issue':'#D78385','interaction':'#B291D2','ended':'#7CA99A'},'fontName':'HelveticaNeue-Medium','fontSize':10,'hoverColor':'#8E99AD','hoverGlow':.09,'hoverAmplitude':.105,'hoverDuration':1.7,'shatterDivisions':3,'shatterDuration':.46,'shatterTravel':17,'orbitDuration':.3,'orbitCurve':'spring'}
    (P/'audio').mkdir()
    for audio in sorted((ROOT/'audio').glob('*.mp3')):shutil.copyfile(audio,P/'audio'/audio.name)
    shutil.copyfile(ROOT/'generator/behavior.js',P/'behavior.js')
    manifest={'schemaVersion':2,'id':'feibi.pet','name':'菲比 · Phoebe','canvasSize':{'width':SIZE,'height':SIZE},'anchor':{'x':.5,'y':.5},'appIcon':icons['day'],'clips':clips,'features':{
        'variants':variants,'tracking':tracks['day'],'themes':{'day':{'name':'日光','appIcon':icons['day'],'bubbles':bubble['day']},'night':{'name':'月夜','appIcon':icons['night'],'tracking':tracks['night'],'bubbles':bubble['night']}},'defaultTheme':'day','bubbles':bubble['day'],
        'loopingClips':['focus','drag'], 'bindings':{'dragStart':[{'type':'playClip','value':'drag'}],'dragEnd':[{'type':'playClip','value':'press'}],'return':[{'type':'playClip','value':'return'}]},
        'sounds':{**{k:{'file':'audio/'+v+'.mp3','volume':.55,'cooldown':0} for k,v in [('needsAttention','phoebe_0'),('problem','phoeba_chubby_1'),('turnEnded','phoebe_chubby_4')]},'petInteraction':{'files':['audio/'+f.name for f in sorted((ROOT/'audio').glob('*.mp3')) if f.stem not in ['phoebe_0','phoeba_chubby_1','phoebe_chubby_4']],'volume':.55,'cooldown':0}},
        'soundBindings':{'interaction':'needsAttention','issue':'problem','ended':'turnEnded','petClick':'petInteraction'},
        'edgeBoundary':{'width':1.35,'thickness':1.4,'opacity':.58,'glowOpacity':.12,'glowRadius':4},
        'behavior':{'click':'default','bubbleClick':'visit','returnPolicy':'user','followFocus':True,'bubbleDistance':16,'bubbleCapacity':6,'bubbleArcDegrees':130,'collision':'free','edgeInset':.09},
        'hitRegions':[{'x':.16,'y':.07,'width':.68,'height':.62,'shape':'ellipse'},{'x':.22,'y':.68,'width':.57,'height':.27,'shape':'ellipse'}], 'script':'behavior.js'}}
    (P/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':'))+'\n')
    images=list(P.rglob('*.png'));pixels=sum(Image.open(f).width*Image.open(f).height for f in images)
    report={'unique_pngs':len(images),'rgba_mib':round(pixels*4/1048576,3),'manifest_bytes':(P/'manifest.json').stat().st_size,'fps':FPS,'canvas':SIZE,'themes':['day','night'],'frame_references':len(clips)*0+sum(len(c['frames']) for c in clips.values())+sum(sum(len(c['frames']) for c in v['clips'].values()) for v in variants.values())}
    assert pixels*4<=32*1048576,report
    (ROOT/'reports').mkdir(exist_ok=True);(ROOT/'reports/package-audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
