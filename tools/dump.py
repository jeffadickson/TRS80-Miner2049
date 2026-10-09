import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from run import session
from syms import syms
S=syms('../build/miner3.lst')
def grid(h,y0,y1,x0=0,x1=64):
    vr=bytes(h.mem[0x3C00:0x4000]); bg=bytes(h.mem[0x9C00:0xA000])
    for y in range(y0,y1):
        s='%2d '%y
        for x in range(x0,x1):
            c=(y//3)*64+x//2; v=vr[c]; b=bg[c]; k=(y%3)*2+(x&1)
            on = 128<=v<192 and v>>k&1; bon=128<=b<192 and b>>k&1
            s+= '#' if on and bon else ('o' if on else ('x' if bon else '.'))
        print(s)
def var(h,n): return h.mem[S[n]]
import json, numpy as np
from PIL import Image
_F=json.load(open(_os.path.join(REPO, 'web/font.json')))
def big(h, path, crop=None):
    vr=bytes(h.mem[0x3C00:0x4000]); img=np.zeros((384,512),np.uint8)
    for i,v in enumerate(vr):
        cx=(i&63)*8; cy=(i>>6)*24
        for y in range(24):
            row=0
            if 128<=v<192:
                b=v-128; k=y//8
                row=(0xF0 if b>>(2*k)&1 else 0)|(0x0F if b>>(2*k+1)&1 else 0)
            elif 32<v<128 or v>=192:
                g=_F[v] if isinstance(_F,list) else _F.get(str(v))
                row=(g[y>>1] if g and (y>>1)<len(g) else 0)
            for x in range(8):
                if row&(0x80>>x): img[cy+y,cx+x]=230
    im=Image.fromarray(img)
    if crop: im=im.crop(crop)
    im.save(path); return im
