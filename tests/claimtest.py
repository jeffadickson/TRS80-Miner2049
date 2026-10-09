import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from shots import *
import sys
def test(st):
    h,run=start(st,80)
    M=S['MUTTAB']
    def nomut():
        for k in range(8): h.mem[M+k*10+7]=0
        h.mem[S['HAZON']]=0; h.mem[S['PULVON']]=0
    tm=bytes(h.mem[0xA000:0xA000+0x1800])
    gaps=[(i%128,i//128) for i,b in enumerate(tm) if b==5]
    bad=[]
    for gx,gy in gaps:
        if h.mem[0xA000+gy*128+gx]!=5: continue
        done=False
        for bx in range(max(0,gx-4),min(122,gx)+1) if gx<123 else [122]:
            h.mem[S['BOBX']]=bx; h.mem[S['BOBY']]=gy-1-6; h.mem[S['BOBSTATE']]=0; nomut()
            run(1); nomut()
            if h.mem[0xA000+gy*128+gx]!=5: done=True; break
        if not done: bad.append((gx,gy,var(h,'BOBY')+6,var(h,'BOBSTATE')))
    return len(gaps),bad
for st in map(int,sys.argv[1:]): n,b=test(st); print(st,n,'unclaimable',b)
