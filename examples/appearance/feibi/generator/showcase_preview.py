#!/usr/bin/env python3
"""Offline native-contract composites; never launches or installs Char."""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from showcase import ROOT,P,RECT,affine
from art import resize_premultiplied
M=json.loads((P/'manifest.json').read_text()); OUT=ROOT/'preview'; OUT.mkdir(exist_ok=True)

def resolve(theme,edge):
    p={**M,'tracking':M['features']['tracking'],'rotation':0,'mirrorX':False,'clips':dict(M['clips'])}
    for v in [M['features']['variants'].get(edge,{}),M['features']['themes'][theme],M['features']['themes'][theme].get('variants',{}).get(edge,{})]:
        p['clips'].update(v.get('clips',{}));p.update({k:v[k] for k in ['tracking','rotation','mirrorX','anchor'] if k in v})
    return p

def frame(theme,edge,clip,i,gaze=(0,0)):
    p=resolve(theme,edge);c=p['clips'][clip];i=min(i,len(c['frames'])-1);out=Image.open(P/c['frames'][i]).convert('RGBA')
    f=c.get('trackingFrames',[{}]*len(c['frames']))[i]; tracking=p['tracking']; state=tracking.get('states',{}).get(f.get('state'),tracking)
    layer=Image.new('RGBA',out.size)
    head=state.get('head');gx,gy=gaze
    if head:
        direction=('n' if gy<-.25 else 's' if gy>.25 else '')+('e' if gx>.25 else 'w' if gx<-.25 else '')
        layer.alpha_composite(Image.open(P/head['poses'].get(direction or 'center',head['poses']['center'])))
    for eye in state.get('eyes',[]):
        moved=Image.new('RGBA',out.size)
        moved.alpha_composite(Image.open(P/eye['image']),(round(gx*eye.get('travelX',.025)*192),round(gy*eye.get('travelY',.025)*192)))
        if 'clipRegion' in eye:
            r=eye['clipRegion'];mask=Image.new('L',out.size)
            ImageDraw.Draw(mask).ellipse((r['x']*192,r['y']*192,(r['x']+r['width'])*192,(r['y']+r['height'])*192),fill=255)
            moved.putalpha(Image.fromarray(np.minimum(np.array(moved.getchannel('A')),np.array(mask))))
        layer.alpha_composite(moved)
    t=f.get('transform',[1,0,0,1,0,0]); a,b,c,d,tx,ty=t
    mat=np.array([[a,c,tx*192],[b,d,ty*192],[0,0,1]])
    layer=affine(layer,mat);layer.putalpha(layer.getchannel('A').point(lambda a:round(a*f.get('opacity',1))))
    out.alpha_composite(layer);return out

def placed(image,p,size,edge):
    # Match host anchor: manifest anchor and author regions both use top-down coordinates.
    canvas=Image.new('RGBA',(size*3,size*3));scaled=resize_premultiplied(image,(size,size))
    anchor=p['anchor'];x=round(size*1.5-anchor['x']*size);y=round(size*1.5-anchor['y']*size)
    canvas.alpha_composite(scaled,(x,y))
    center=size*1.5
    if p.get('mirrorX'):canvas=canvas.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas=canvas.rotate(p.get('rotation',0),resample=Image.Resampling.BICUBIC,center=(center,center))
    if edge!='desktop':
        # Stable center follows the package's pet-size-relative usable-edge inset.
        inset=size*M['features']['behavior'].get('edgeInset',8/size)
        mask=Image.new('L',canvas.size);d=ImageDraw.Draw(mask)
        boxes={'left':(center-inset,0,size*3,size*3),'right':(0,0,center+inset,size*3),'top':(0,center-inset,size*3,size*3),'bottom':(0,0,size*3,center+inset)}
        d.rectangle(boxes[edge],fill=255);canvas.putalpha(Image.composite(canvas.getchannel('A'),Image.new('L',canvas.size),mask))
    return canvas

def main():
    # Baseline and exact matching frames are visible on both light and dark backgrounds.
    board=Image.new('RGB',(1280,780),'#F5F6FA');d=ImageDraw.Draw(board)
    for ti,theme in enumerate(['day','night']):
        for bg in range(2):
            y=40+ti*370+bg*180;d.rounded_rectangle((15,y,1265,y+170),18,fill='#222532' if bg else '#FFFFFF')
            d.text((30,y+10),theme+' / '+('dark' if bg else 'light'),fill='#A3ADC3')
            for ci,edge in enumerate(['desktop','left','right','top','bottom']):
                p=resolve(theme,edge);pic=placed(frame(theme,edge,'idle',0),p,88,edge)
                board.paste(pic,(25+ci*245,y-10),pic);d.text((110+ci*245,y+146),edge,fill='#8F98AB')
    board.save(OUT/'themes-edges.png')
    sheet=Image.new('RGB',(1200,420),'#F4F6FA');d=ImageDraw.Draw(sheet)
    for row,theme in enumerate(['day','night']):
        for col,size in enumerate([36,48,88]):
            for i,g in enumerate([(0,0),(-1,0),(1,0)]):
                pic=frame(theme,'desktop','idle',0,g).resize((size,size),Image.Resampling.LANCZOS)
                x=col*400+i*120+40;y=row*200+80;sheet.paste(pic,(x,y),pic);d.text((x,y+size+8),f'{theme} {size}pt',fill='#68738B')
    sheet.save(OUT/'sizes-tracking.png')
    for theme in ['day','night']:
        for clip in M['clips']:
            p=resolve(theme,'desktop');frames=[]
            for i in range(len(p['clips'][clip]['frames'])):
                pic=frame(theme,'desktop',clip,i).resize((384,384),Image.Resampling.LANCZOS)
                bg=Image.new('RGBA',pic.size,'#F4F6FA');bg.alpha_composite(pic);frames.append(bg.convert('RGB'))
            frames[0].save(OUT/f'{theme}-{clip}.webp',save_all=True,append_images=frames[1:],duration=round(1000/30),loop=0,lossless=False,quality=85)
    # Edge settle seam, blink, and transparent migration endpoints.
    for edge in ['left','right','top','bottom']:
        peek=frame('day',edge,'edgePeek',20);rest=frame('day',edge,'idle',0)
        assert np.max(np.abs(np.array(peek).astype(int)-np.array(rest).astype(int)))<=1,edge
    for theme in ['day','night']:
        for edge in ['desktop','left','right','top','bottom']:
            for clip,i in [('depart',13),('arrive',0),('edgeHide',17),('edgePeek',0)]:
                assert frame(theme,edge,clip,i).getbbox() is None,(theme,edge,clip,i)
    print('Preview: both themes, five placements, 36/48/88pt, gaze, seams and transparent endpoints passed')
if __name__=='__main__':main()
