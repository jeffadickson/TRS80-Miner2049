import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys; from figs import bob_layers
import numpy as np
ROM=open(_os.path.join(REPO, 'rom/atari_miner.rom'),'rb').read()
rb=lambda a: ROM[a-0x8000]
def bob_mask(f):
    rows=bob_layers(f); a=np.zeros((23,8),int)
    for r in range(0x1F,0x36):
        b=rows.get(r,[0,0,0])
        for x in range(8):
            if (b[0]|b[1]|b[2])&(0x80>>x): a[r-0x1F,x]=1
    return a
def down(a,W,H,th=0.34):
    h,w=a.shape; out=np.zeros((H,W),int)
    for y in range(H):
        for x in range(W):
            blk=a[int(y*h/H):int((y+1)*h/H), int(x*w/W):max(int(x*w/W)+1,int((x+1)*w/W))]
            out[y,x]=1 if blk.mean()>=th else 0
    return out
def show(a): return '\n'.join(''.join('#' if v else '.' for v in r) for r in a)
for f in (1,2,3,7,11):
    print('frame',f); print(show(down(bob_mask(f),6,6))); print()
for st in (0,1,4):
    a=np.array([[ (rb(0x8591+12*st+y)>>(7-x))&1 for x in range(8)] for y in range(10)])
    print('mut',st); print(show(down(a,6,3,0.3)))
