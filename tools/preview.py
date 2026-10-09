import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import json, base64, numpy as np
from PIL import Image
S=json.load(open('../build/atari_stations.json'))
def atari_px(bm):
    b=np.frombuffer(bm,np.uint8).reshape(184,40)
    return np.stack([(b>>6)&3,(b>>4)&3,(b>>2)&3,b&3],2).reshape(184,160)
def m3_render(px, scale=4):
    # px: 48x128 values 0..3 ; draw TRS-80 look: blocks 1 wide x 2 tall aspect
    img=np.zeros((48*2*scale,128*scale,3),np.uint8)
    col={1:(255,255,255),2:(255,255,255),3:(255,255,255)}
    for y in range(48):
        for x in range(128):
            v=px[y,x]
            if v: img[y*2*scale:(y+1)*2*scale-1, x*scale:(x+1)*scale-1]=(235,240,255)
    return Image.fromarray(img)
tiles=[]
for s in range(1,11):
    a=atari_px(base64.b64decode(S[str(s)]['bitmap']))
    m=np.zeros((48,128),np.uint8)
    for y in range(3,48):
        y0=int((y-3)*184/45); y1=int((y-2)*184/45)
        for x in range(128):
            x0=int(x*160/128); x1=max(x0+1,int((x+1)*160/128))
            m[y,x]=a[y0:y1,x0:x1].max()
    tiles.append(m3_render(m,2))
W=Image.new('RGB',(tiles[0].width*2+10,(tiles[0].height+10)*5),(60,60,60))
for i,t in enumerate(tiles): W.paste(t,((i%2)*(t.width+10),(i//2)*(t.height+10)))
W.save(_os.path.join(REPO, 'build/m3prev.png')); print(W.size)
