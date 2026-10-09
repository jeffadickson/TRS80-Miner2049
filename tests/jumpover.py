"""Find where the tester's own playthrough (mutants on) jumps Bob over a mutant, and save the
frames as an image strip.  python3 jumpover.py [station]"""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys
import playthrough
from explore import Game, S, replay, S_JUMP, S_FALL

st = int(sys.argv[1]) if len(sys.argv) > 1 else 1
r = playthrough.play(st, mutants=True)
print(r)
acts = playthrough.LAST_ACTS
g = Game(st, mutants=True, freeze=False)
log = []                                       # per frame: Bob, the mutants, the screen
def rec(g):
    m = g.h.mem; M = S['MUTTAB']
    muts = {k: (m[M + k * 10], m[M + k * 10 + 1]) for k in range(8) if m[M + k * 10 + 7]}
    log.append((g.total, g.v('BOBX'), g.v('BOBY') + 6, g.v('BOBSTATE'), muts, bytes(m[0x3C00:0x4000])))
for a in acts:
    replay(g, a, rec)
# a jump over a mutant: Bob leaves the ground, a mutant on the row he took off from is on
# one side of him then and on the other side when he lands, and he lands alive
events = []
for i in range(1, len(log)):
    if log[i][3] != S_JUMP or log[i - 1][3] == S_JUMP: continue
    j = i
    while j < len(log) and log[j][3] in (S_JUMP, S_FALL): j += 1
    if j >= len(log) or log[j][3] != 0: continue
    t0, x0, feet0, _, m0, _ = log[i - 1]; x1, m1 = log[j][1], log[j][4]
    for k, (mx, mf) in m0.items():
        if mf == feet0 and k in m1 and m1[k][1] == feet0 and (mx - x0) * (m1[k][0] - x1) < 0:
            events.append((i - 1, j)); break
print('jumps over a mutant on the winning path:', len(events), [(log[i][0], log[i][1], log[i][2]) for i, j in events])
if events:
    from m3 import M3
    from PIL import Image
    i, j = events[0]
    pick = list(range(max(0, i - 4), min(len(log), j + 4), 2))
    shots = []
    for k in pick:
        g.h.mem[0x3C00:0x4000] = log[k][5]
        shots.append(g.h.screen(scale=3))
    w, h = shots[0].size
    cols = 4; rows = (len(shots) + cols - 1) // cols
    sheet = Image.new('RGB', (w * cols, h * rows))
    for n, im in enumerate(shots): sheet.paste(im, ((n % cols) * w, (n // cols) * h))
    sheet.save('jumpover_st%d.png' % st)
    print('saved jumpover_st%d.png' % st, len(shots), 'frames')
