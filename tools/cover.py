import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from shots import *
import json, sys
D=json.load(open('../build/m3_stations.json'))
def cover(st):
    h,run=start(st,80)
    M=S['MUTTAB']
    def nomut():
        for k in range(8): h.mem[M+k*10+7]=0
    nomut()
    runs=sorted(D[str(st)]['runs'],key=lambda r:r[2])
    for x0,n,r in runs:
        if r>=47: continue
        for d,start_x in (('RIGHT',max(0,x0-3)),('LEFT',min(122,x0+n-3))):
            h.mem[S['BOBX']]=start_x; h.mem[S['BOBY']]=r-6; h.mem[S['BOBSTATE']]=0; h.mem[S['HAZON']]=0
            for i in range(int(n/0.8)+6):
                run(1,[d]); nomut()
                if var(h,'BOBSTATE')!=0 or var(h,'STATION')!=st: break
            if var(h,'STATION')!=st: return 'cleared'
    tm=bytes(h.mem[0xA000:0xA000+0x1800])
    return [(i%128,i//128) for i,b in enumerate(tm) if b==5]
for st in map(int,sys.argv[1:]): r=cover(st); print(st, len(r) if isinstance(r,list) else r, r if isinstance(r,list) else '')
