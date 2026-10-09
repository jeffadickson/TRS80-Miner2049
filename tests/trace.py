"""python3 trace.py ST [frames]: a hash of the machine after each frame of a fixed key script,
the same script native/m3test trace presses; the two lists must match line for line."""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys
from explore import Game

KS = [[], ['LEFT'], ['RIGHT'], ['UP'], ['DOWN'], ['SPACE'], ['LEFT', 'SPACE'], ['RIGHT', 'SPACE'], ['ENTER']]
def script_keys(f): return KS[(f // 17 * 7 + f // 5) % 9]

def fnv(data, h=1469598103934665603):
    for b in data:
        h ^= b; h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return h

def machine_hash(m):
    regs = [m.af, m.bc, m.de, m.hl, m.ix, m.iy, m.sp, m.pc, m.r]
    return fnv(b''.join(r.to_bytes(2, 'little') for r in regs), fnv(bytes(m.memory)))

if __name__ == '__main__':
    st = int(sys.argv[1]); n = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
    g = Game(st, mutants=True, freeze=False)
    for f in range(n):
        g.frame(script_keys(f))
        print(f, '%016x' % machine_hash(g.h.m))
