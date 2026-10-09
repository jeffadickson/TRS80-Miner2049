"""busy(h, frames, keys): T-states of game work in each of the next frames (from the return
of WAITTICK to the next PLAYLOOP), i.e. how much of the 67,584 T-state tick a frame uses."""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import os
from syms import syms
S = syms(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'miner3.lst'))

def busy(h, frames=8, keys=()):
    m = h.m; res = []
    def run_until(a, limit=4 * 10**5):
        m.set_breakpoint(a); t = 0
        while t < limit:
            m.ticks_to_stop = 500
            m.run()
            t += 500 - m.ticks_to_stop
            if m.pc == a: break
        m.clear_breakpoint(a); return t
    h.keys = set(keys)
    for i in range(frames):
        h.rtc = 1; run_until(S['PLAYLOOP'] + 3)  # past the WAITTICK call
        res.append(run_until(S['PLAYLOOP']))
    return res
