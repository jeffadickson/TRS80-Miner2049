import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys
from m3 import M3
def session(script, shots, cmd='../build/miner3.cmd'):
    h=M3(); h.load_cmd(cmd)
    f=0; out=[]
    for frames, keys in script:
        h.keys=set(keys)
        for i in range(frames):
            h.run_frame(); f+=1
            if f in shots: h.screen(2).save(_os.path.join(REPO, 'build/s_%04d.png')%f); out.append(f)
    return h,out
if __name__=='__main__':
    h,o=session([(20,[]),(3,['SPACE']),(80,[]),(40,['RIGHT']),(10,['SPACE','RIGHT']),(40,['RIGHT'])],{20,30,110,140,170,190})
    print(o, 'pc %04x'%h.m.pc)
