import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import json, numpy as np
from PIL import Image
D=json.load(open('../build/m3_stations.json'))
def build(st):
    T=np.zeros((48,128),int)   # 0 empty 1 item 2 ladder 3 surface 4 dash 5 gap 6 floor
    T[47,:]=6
    for x0,n,r in st['runs']:
        for x in range(x0,x0+n):
            if 0<=x<128 and r<47:
                T[r,x]=3
                if r+1<47: T[r+1,x]=4 if x%2==0 else 5
    for lx,top,bot in st['ladders']:
        for r in range(top-2,bot):
            for dx,on in ((0,1),(3,1),(1,(r-top)%2==0),(2,(r-top)%2==0)):
                if on and 0<=r<48 and T[r,lx+dx]==0: T[r,lx+dx]=2
    for x0,y0,x1,y1 in st['slides']:
        n=max(1,y1-y0)
        for k in range(n+1):
            x=x0+(x1-x0)*k//n; r=y0+k
            for dx in range(3):
                if 0<=r<48 and 0<=x+dx<128 and T[r,x+dx]==0: T[r,x+dx]=2
    for it in st['items']:
        for yy,row in enumerate(it['img']):
            for xx,v in enumerate(row):
                if v and 0<=it['y']+yy<48 and it['x']+xx<128: T[it['y']+yy,it['x']+xx]=1
    return T
MUT=[".####.","######","#.#.#."]
BOB=["..##..",".#####","..###.",".####.","..##..","..#.#."]
def render(st,T,scale=3):
    img=np.zeros((96*scale,128*scale,3),np.uint8)
    def put(x,y,c):
        if 0<=x<128 and 0<=y<48: img[y*2*scale:(y+1)*2*scale-1,x*scale:(x+1)*scale-1]=c
    for y in range(48):
        for x in range(128):
            if T[y,x] in (1,2,3,4,6): put(x,y,(225,235,255))
    for m in st['mutants']:
        for r,row in enumerate(MUT):
            for i,ch in enumerate(row):
                if ch=='#': put(m['x']+i,m['feet']-3+r,(255,170,120))
    b=st['bob']
    for r,row in enumerate(BOB):
        for i,ch in enumerate(row):
            if ch=='#': put(b['x']+i,b['feet']-6+r,(120,200,255))
    return Image.fromarray(img)
tiles=[render(D[str(s)],build(D[str(s)])) for s in range(1,11)]
W=Image.new('RGB',(tiles[0].width*2+10,(tiles[0].height+10)*5),(60,60,60))
for i,t in enumerate(tiles): W.paste(t,((i%2)*(t.width+10),(i//2)*(t.height+10)))
W.save(_os.path.join(REPO, 'build/m3lay.png'))
