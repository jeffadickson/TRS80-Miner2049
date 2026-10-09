"""Automated playtester, part 3: the regression suite.  python3 regress.py [--full]

Builds the game, then checks, all through the real code running in the M3 harness:
  ladders     every ladder can be climbed from its foot to its top and back down
  slides      every slide (chain) carries Bob to somewhere he can stand, alive
  specials    transporter, platforms, waste box, lift, pulverizers, cannon
  frames      no frame of play overruns the 1/30 s tick (random play, every station)
  stations    clearing a station leads to the next, station 10 to zone 2
  cheats      I (invincible), U (land to claim), N (next station); the death flash
  items       picking up a block item and a character item
  --full      also the explorer (everything reachable and claimable) on every station,
              on all cores (-j N to limit)
"""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys, os, re, random, subprocess, time
os.chdir(os.path.dirname(os.path.abspath(__file__)))

results = []
def check(name, ok, detail=''):
    results.append((name, bool(ok), detail))
    print('%-4s %-34s %s' % ('ok' if ok else 'FAIL', name, detail), flush=True)

# ---- build ---------------------------------------------------------------------------
# station data is regenerated only where its sources (the Atari ROM's decoded stations) are
# present; the game is reassembled only if zmac is installed; otherwise the tests run on
# build/miner3.cmd as it is.  --no-build skips both.
# the game is reassembled first if zmac is installed (make); otherwise the tests run on
# build/miner3.cmd as it is.  --no-build skips it.
import shutil
if '--no-build' not in sys.argv and shutil.which('zmac'):
    r = subprocess.run('make -s -C .. build/miner3.cmd', shell=True, capture_output=True, text=True)
    check('build', r.returncode == 0, (r.stdout + r.stderr).strip()[-80:])
else:
    print('     build skipped: testing build/miner3.cmd as it is')

from explore import Game, Explorer, S
from prof3 import busy
DATA = open('../src/data.asm').read()
def table(st, name):
    body = re.search(r'ST%d_%s:[^\n]*\n(.*?)\tdb\t\$FF' % (st, name), DATA, re.S).group(1)
    return [tuple(map(int, m.split(','))) for m in re.findall(r'db\t([\d,]+)', body)]

def game(st, **kw):
    g = Game(st, **kw)
    return g

# ---- ladders -------------------------------------------------------------------------
bad = []; n = 0
for st in range(1, 11):
    for lx, top, bot in table(st, 'LAD'):
        n += 1
        g = game(st); m = g.h.mem
        m[S['BOBX']] = lx - 1; m[S['BOBY']] = bot - 6; m[S['BOBSTATE']] = 0
        g.frame(); g.frame()
        if g.v('BOBSTATE') != 0: continue          # a ladder hanging in mid-air (station 8)
        for i in range(400):
            if g.frame(['UP']) == 0 and i > 2: break
        t = g.v('BOBY') + 6
        g.frame(); g.frame()
        for i in range(400):
            if g.frame(['DOWN']) == 0 and i > 2: break
        b = g.v('BOBY') + 6
        if abs(t - top) > 1 or abs(b - bot) > 1: bad.append((st, lx, top, bot, t, b))
check('ladders', not bad, '%d ladders%s' % (n, '; ' + str(bad) if bad else ''))

# ---- slides --------------------------------------------------------------------------
bad = []; n = 0
for st in range(1, 11):
    for x0, y0, x1, y1 in table(st, 'SLI'):
        n += 1
        g = game(st); m = g.h.mem
        started = False
        for sx, d in ((x0 - 1, 'RIGHT'), (x0 + 1, 'LEFT')):   # walk onto its top from either side
            g = game(st); m = g.h.mem
            m[S['BOBX']] = sx; m[S['BOBY']] = y0 - 6; m[S['BOBSTATE']] = 0
            for i in range(4):
                if g.frame([d]) == 4: started = True; break
            if started: break
        if g.v('BOBSTATE') != 4: bad.append((st, x0, y0, 'did not start')); continue
        s = g.settle(600)
        if s != 0: bad.append((st, x0, y0, 'ended in state %d' % s))
check('slides', not bad, '%d slides%s' % (n, '; ' + str(bad) if bad else ''))

# ---- specials ------------------------------------------------------------------------
# transporter: booth 1 to booth 3 on station 3
g = game(3)
for i in range(60):
    if 55 <= g.v('BOBX') <= 58: break
    g.frame(['LEFT'])
g.frame(); g.frame(['3']); g.frame(['3']); g.settle()
check('transporter', g.v('BOBY') + 6 == 24, 'arrived on feet row %d' % (g.v('BOBY') + 6))
# platform carries Bob (station 5)
g = game(5); m = g.h.mem; P = S['PLATTAB']
m[S['BOBX']] = m[P] + 2; m[S['BOBY']] = m[P + 1] - 6; m[S['BOBSTATE']] = 0
x0 = g.v('BOBX')
for i in range(40): g.frame()
check('platform', g.v('BOBX') != x0 and g.v('BOBSTATE') == 0, 'moved %d blocks' % (g.v('BOBX') - x0))
# waste box blocks walking (station 6)
g = game(6)
for i in range(60): g.frame(['RIGHT'])
check('waste wall', g.v('BOBX') < 16 and g.v('BOBSTATE') == 0, 'stopped at x %d' % g.v('BOBX'))
# lift: ENTER takes it, up moves it with Bob, SPACE jumps off it
g = game(8)
for i in range(12): g.frame(['LEFT'])
g.frame(); g.frame(['ENTER']); g.frame()
row = g.v('LIFTROW')
for i in range(40): g.frame(['UP'])
up = g.v('LIFTROW') < row and g.v('BOBY') + 6 == g.v('LIFTROW')
g.frame(['ENTER']); g.frame(); g.frame(['SPACE'])
check('lift', up and g.v('BOBSTATE') == 1, 'rose to row %d, then jumped' % g.v('LIFTROW'))
# pulverizer crushes (station 9)
g = game(9); m = g.h.mem
m[S['BOBX']] = 56; m[S['BOBY']] = 41
for i in range(300):
    m[S['BOBX']] = 56
    if g.frame() == 5: break
check('pulverizer', g.v('BOBSTATE') == 5, 'crushed after %d frames' % i)
# cannon: 1 ton lands on row 29 (station 10)
g = game(10); g.setv('TNT', 1)
for i in range(60):
    if g.frame(['LEFT']) == 7: break
g.frame(); g.frame(['SPACE']); s = g.settle()
check('cannon', s == 0 and g.v('BOBY') + 6 == 29, 'landed on row %d' % (g.v('BOBY') + 6))

# ---- frame budget --------------------------------------------------------------------
random.seed(7); worst = {}
keysets = [[], ['LEFT'], ['RIGHT'], ['UP'], ['DOWN'], ['SPACE'], ['LEFT', 'SPACE'], ['RIGHT', 'SPACE'], ['ENTER']]
for st in range(1, 11):
    g = game(st, mutants=True, freeze=True); mx = 0
    for seg in range(20):
        k = random.choice(keysets)
        for b in busy(g.h, 3, k):
            if b < 300000: mx = max(mx, b)         # (a death rebuilds the station: not a frame)
        if g.v('BOBSTATE') == 5:
            g = game(st, mutants=True, freeze=True)
    worst[st] = mx
check('frame budget', max(worst.values()) < 67584, 'worst %d of 67584 T (%s)' % (max(worst.values()), ', '.join('%d:%dK' % (s, w // 1000) for s, w in worst.items())))

# ---- station and zone changes --------------------------------------------------------
g = game(1); g.setv('INVULN', 1); seen = []
for st in range(10):
    g.frame(['N']); g.frame()
    for i in range(500):
        g.frame()
        if g.v('STATION') != seen[-1:] and g.v('BOBSTATE') == 0 and g.v('NOVRAM') == 0: pass
    seen.append((g.v('STATION'), g.v('ZONE')))
check('stations', seen[-1] == (1, 2) and [s for s, z in seen[:9]] == list(range(2, 11)), str(seen))

# ---- cheats --------------------------------------------------------------------------
g = game(1)
g.frame(['U']); g.frame()
no_u = bytes(g.h.mem[0x3C00:0x3C05]) == b'SCORE'
g.setv('INVULN', 1)
g.frame(['U']); g.frame(['U'])
for i in range(8): g.frame(['U'])
u_view = b'SECTIONS' in bytes(g.h.mem[0x3C00:0x3C40])
for i in range(10): g.frame()
u_back = bytes(g.h.mem[0x3C00:0x3C05]) == b'SCORE'
check('cheat U', no_u and u_view and u_back, 'ignored without I, shows, restores')
g = game(1); g.setv('INVULN', 1); m = g.h.mem; M = S['MUTTAB']
m[M] = g.v('BOBX'); m[M + 1] = g.v('BOBY') + 6; m[M + 7] = 1; m[M + 5] = 0
lit = []
for i in range(4): g.frame(); lit.append(sum(1 for b in m[0x3C40:0x4000] if b == 191))
check('death flash', max(lit) > 900 and g.v('LIVES') == 3 and g.v('BOBSTATE') != 5, 'lit %s' % lit)

# ---- items ---------------------------------------------------------------------------
g = game(5); m = g.h.mem
cell = 0x3C00 + 64 + 32
m[S['BOBX']] = 56; m[S['BOBY']] = 2; m[S['BOBSTATE']] = 0
before = m[cell]
for i in range(14): g.frame(['RIGHT'])
check('character item', before == 36 and m[cell + 0x6000] == 128 and g.v('EDIBLE') > 0, 'the $ on station 5')
g = game(1); m = g.h.mem; it = S['ITEMTAB']
m[S['BOBX']] = max(0, m[it] - 1); m[S['BOBY']] = m[it + 1] + m[it + 3] - 6; m[S['BOBSTATE']] = 0
g.frame(); g.frame()
check('block item', m[it + 8] == 0, 'first item on station 1')

# ---- the explorer --------------------------------------------------------------------
if '--full' in sys.argv:
    import parallel
    from explore import explore_station
    reports = dict(parallel.each(explore_station, list(range(1, 11)), parallel.jobs()))
    for st in range(1, 11):
        r = reports[st]
        missed = [i for i in r['items_missed'] if not (st == 5 and i[2] == 33)]   # the poisoned goblet
        check('reachable station %d' % st, not r['unclaimed'] and not missed,
              '%d sections, %d unclaimable, items missed %s, %d nodes, %ds' % (r['sections'], len(r['unclaimed']), missed, r['nodes'], r['seconds']))

print('\n%d checks, %d failed' % (len(results), sum(1 for r in results if not r[1])))
sys.exit(1 if any(not r[1] for r in results) else 0)
