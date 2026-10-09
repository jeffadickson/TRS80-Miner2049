import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import re
def syms(lst='../build/miner3.lst'):
    out={}
    for l in open(lst):
        m=re.search(r'\s([0-9A-F]{4})\s+(?:[0-9A-F]{2,8}\s*)?\t([A-Za-z_][A-Za-z0-9_]*):',l)
        if m: out[m.group(2)]=int(m.group(1),16)
    return out
