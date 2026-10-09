import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from shots import *
from collections import Counter
inv={v:k for k,v in S.items()}
def frame_count(h, keys=()):
    m=h.m; h.keys=set(keys); h.rtc=1
    c=Counter(); n_ins=0
    m.ticks_to_stop=1; m.run()
    while n_ins<200000:
        pc=m.pc
        if pc in inv:
            n=inv[pc]
            if n=='PLAYLOOP': break
            c[n]+=1
        m.ticks_to_stop=1; m.run(); n_ins+=1
    return c
