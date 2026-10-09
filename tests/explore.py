"""Automated playtester, part 1: what can Bob reach on a station, using only key presses?

Breadth-first search over the real game running in the M3 harness.  Every node is a
complete machine snapshot (memory + CPU, 65,580 bytes) taken at a frame boundary with Bob
standing (or loaded in the cannon); every edge is a macro of real key presses:
walk left / right (one run records every block it passes), jump left / right / up, climb
up / down, wait, and the specials (transporter digits, lift driving, cannon rolling and
firing).  Mutants are switched off and the bonus is frozen, so the question is only "can he
get there"; deadly scenery still kills, and a death prunes the branch.

Claims are permanent, so the union of the sections claimed in any branch is what can be
claimed; items likewise.  Results: reachable standing positions, sections never claimed,
items never collected.
"""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys, os, time, zlib
from collections import deque
from m3 import M3
from syms import syms

HERE = os.path.dirname(os.path.abspath(__file__))
CMD = os.path.join(HERE, '..', 'build', 'miner3.cmd')
S = syms(os.path.join(HERE, '..', 'build', 'miner3.lst'))
S_GROUND, S_JUMP, S_FALL, S_LADDER, S_SLIDE, S_DYING, S_TRANS, S_CANNON, S_FLY = range(9)


class Snap:
    """A machine snapshot, stored small: the machine image (65,580 bytes: CPU state, then
    memory from offset 44) XORed with a reference image taken when the station started, then
    zlib-compressed.  Nearly all of memory (code, tables, the parts of the screen that never
    change) XORs to zero, so a snapshot is about 0.5 KB.  The few variables the search asks
    about all the time are kept beside it uncompressed.  snap[0] still gives the full
    image, snap[1] the RTC flag, snap[2] the frame count."""
    __slots__ = ('z', 'rtc', 'frames', 'ref', 'meta')
    META = ('STATION', 'SECTIONS', 'BOBX', 'BOBY', 'BOBSTATE')

    def __init__(self, img, rtc, frames, ref):
        self.ref = ref; self.rtc = rtc; self.frames = frames
        self.z = zlib.compress((int.from_bytes(img, 'little') ^ ref[1]).to_bytes(len(img), 'little'), 1)
        o = 44
        self.meta = {n: img[o + S[n]] for n in self.META}
        self.meta['SECTIONS'] |= img[o + S['SECTIONS'] + 1] << 8

    def image(self):
        return (int.from_bytes(zlib.decompress(self.z), 'little') ^ self.ref[1]).to_bytes(len(self.ref[0]), 'little')

    def peek(self, addr):
        return self.image()[44 + addr]

    def __getitem__(self, i):
        if i == 0: return self.image()
        return (None, self.rtc, self.frames)[i]

    def __len__(self): return 3

    def size(self): return len(self.z) + 120


class Game:
    def __init__(self, st, cmd=CMD, mutants=False, freeze=None):
        self.h = h = M3()
        h.audio = None                             # (no sound log: it grows without end)
        self.ref = None                            # reference image for compact snapshots
        h.load_cmd(cmd)
        self.st = st
        self.run(20); self.run(3, [str(st % 10)]); self.run(3); self.run(3, ['SPACE'])
        self.run(80)                               # the prepare screen, then play
        self.freeze = (not mutants) if freeze is None else freeze
        if not mutants: self.quiet()
        if self.freeze: self.setv('BONUS', 0x99)
        self.frames = 0; self.total = 0

    # memory helpers
    def v(self, n): return self.h.mem[S[n]]
    def setv(self, n, x): self.h.mem[S[n]] = x & 255
    def quiet(self):
        """mutants off, bonus frozen"""
        m = self.h.mem
        for k in range(8): m[S['MUTTAB'] + k * 10 + 7] = 0

    def run(self, n, keys=()):
        self.h.keys = set(keys)
        for i in range(n): self.h.run_frame()

    def frame(self, keys=()):
        self.h.keys = set(keys)
        self.h.run_frame()
        self.frames += 1; self.total += 1
        if self.freeze: self.setv('BONUSTMR', 0)
        return self.v('BOBSTATE')

    def snap(self):
        img = bytes(self.h.m._image)
        if self.ref is None: self.ref = (img, int.from_bytes(img, 'little'))
        return Snap(img, self.h.rtc, self.frames, self.ref)
    def restore(self, s):
        self.h.m._image[:] = s[0]; self.h.rtc = s[1]; self.frames = s[2]

    def pos(self): return (self.v('BOBX'), self.v('BOBY') + 6, self.v('BOBSTATE'))

    def onlift(self):
        if not self.v('LIFTON') or self.v('BOBSTATE') != 0: return False
        x, feet, _ = self.pos(); lx = self.v('LIFTX')
        return feet == self.v('LIFTROW') and x + 3 >= lx and x < lx + 14

    def key(self, mutants=True):
        x, feet, s = self.pos()
        k = (x, feet, s)
        if self.st == 10: k += (self.v('TNT'), self.v('CANX') if s == S_CANNON else 0)
        if self.onlift():                          # on the lift: where it is, coarsely, and
            lx = self.v('LIFTX')                   #   where on it Bob stands
            k = (x - lx, feet, s, 'lift', lx // 4, self.v('LIFTROW'))
        m = self.h.mem; P = S['PLATTAB']
        for i in range(self.v('NPLAT')):           # riding a platform: where it is and which way
            px, row, w, d = m[P + i * 11], m[P + i * 11 + 1], m[P + i * 11 + 2], m[P + i * 11 + 5]
            if s == S_GROUND and feet == row and x + 3 >= px and x + 2 < px + w:
                k += ('plat', i, px, d)
        # live mutants on his floor or the next ones (within 12 rows), coarsely: where they
        # are (8-block steps) and which way they walk.  Without this, waiting for one to pass
        # brings Bob back to a place already seen and the search throws it away
        M = S['MUTTAB']
        for i in range(8 if mutants else 0):
            if m[M + i * 10 + 7] and abs(m[M + i * 10 + 1] - feet) <= 12:
                k += ('mut', i, m[M + i * 10] // 8, m[M + i * 10 + 4])
        return k

    def settle(self, limit=300):
        """no keys until Bob stands, is loaded in the cannon or dies"""
        for i in range(limit):
            s = self.v('BOBSTATE')
            if s in (S_GROUND, S_CANNON, S_DYING) and i > 0: return s
            self.frame()
        return self.v('BOBSTATE')


def gaps_of(g):
    tm = g.h.mem
    return [0xA000 + i for i in range(128 * 48) if tm[0xA000 + i] == 5]


def items_of(g):
    n = g.v('NITEMS'); base = S['ITEMTAB']
    return [base + k * 9 for k in range(n)]


class Explorer:
    def __init__(self, st, max_nodes=20000, verbose=False, game=None, root=None):
        self.g = g = game or Game(st)
        self.root = root
        if root: g.restore(root)
        self.st = st
        self.gaps = gaps_of(g)
        self.items = items_of(g)
        self.claimed = set(); self.collected = set()
        self.open_gaps = list(self.gaps); self.open_items = list(self.items)
        self._mem_off = 44                  # where memory starts in a machine snapshot
        self.nodes = {}                     # key -> (snapshot, parent key, action)
        self.queue = deque()
        self.done = {}                      # key -> set of walk directions already covered
        self.max_nodes = max_nodes
        self.deaths = 0
        self.verbose = verbose
        self.positions = set()
        self.edges = set()
        self.cleared = None
        self._items_cache = {}

    def note(self):
        """what this branch has claimed / collected so far"""
        m = self.g.h.mem
        if self.open_gaps:
            got = [a for a in self.open_gaps if m[a] != 5]
            if got:
                self.claimed.update(got)
                self.open_gaps = [a for a in self.open_gaps if a not in self.claimed]
        if self.open_items:
            got = [a for a in self.open_items if m[a + 8] == 0]
            if got:
                self.collected.update(got)
                self.open_items = [a for a in self.open_items if a not in self.collected]

    def add(self, parent, action, walked=None):
        g = self.g
        if g.v('STATION') != self.st:       # the station was cleared on the way: the game has
            if self.cleared is None:        #   moved on to the next one
                self.cleared = (g.snap(), parent, action)
            return None
        s = g.v('BOBSTATE')
        if s == S_DYING: self.deaths += 1; return None
        if s not in (S_GROUND, S_CANNON): self.note(); return None
        k = g.key()
        self.positions.add(k[:2])
        if parent is not None: self.edges.add((parent, k))
        self.note()                         # claims made on the way count even if we have been here
        if k in self.nodes:
            if walked: self.done.setdefault(k, set()).update(walked)
            return k
        if len(self.nodes) >= self.max_nodes: return None
        self.nodes[k] = (g.snap(), parent, action)
        if walked: self.done.setdefault(k, set()).update(walked)
        self.queue.append(k)
        self.note()
        return k

    def items_here(self, k):
        """True if the items still present now are the ones present at node k"""
        if k not in self._items_cache:             # (decoding a snapshot costs ~0.2 ms: once per node)
            img = self.nodes[k][0][0]
            self._items_cache[k] = tuple(img[44 + a + 8] != 0 for a in self.items)
        snap_items = self._items_cache[k]
        m = self.g.h.mem
        return all(s == (m[a + 8] != 0) for s, a in zip(snap_items, self.items))

    # ---- actions ------------------------------------------------------------------------
    def walk(self, k, d):
        g = self.g; g.restore(self.nodes[k][0])
        other = 'LEFT' if d == 'RIGHT' else 'RIGHT'
        lastx, still = g.v('BOBX'), 0
        for i in range(300):
            s = g.frame([d])
            if s == S_DYING: self.deaths += 1; return
            if s == S_GROUND:
                x = g.v('BOBX')
                if x == lastx:
                    still += 1
                    if still >= 4: break
                else:
                    still = 0; lastx = x
                    # positions passed on the way need no walks of their own, unless the walk
                    # changed something besides where he is (picked up TNT, say)
                    same = g.key()[3:] == k[3:] and self.items_here(k)
                    self.add(k, ('walk', d, i + 1), walked={d, other} if same else None)
            else:
                g.settle(); self.add(k, ('walk', d, i + 1)); return
        self.note()

    def jump(self, k, d):
        g = self.g; g.restore(self.nodes[k][0])
        keys = [d] if d else []
        g.frame(keys + ['SPACE'])
        for i in range(120):
            s = g.frame(keys)
            if s in (S_GROUND, S_CANNON, S_DYING, S_SLIDE, S_LADDER): break
        if g.v('BOBSTATE') == S_SLIDE: g.settle()
        self.add(k, ('jump', d))

    def climb(self, k, d):
        g = self.g; g.restore(self.nodes[k][0])
        if g.frame([d]) != S_LADDER: return
        for i in range(400):
            if g.frame([d]) != S_LADDER: break
        g.settle(); self.add(k, ('climb', d))

    def wait(self, k, n=20):
        g = self.g; g.restore(self.nodes[k][0])
        for i in range(n):
            if g.frame() != S_GROUND: break
        g.settle(); self.add(k, ('wait', n))

    def transport(self, k):
        g = self.g
        for d in '1234':
            g.restore(self.nodes[k][0])
            for i in range(60):                    # let the transporter recharge
                if g.v('TRLOCK') == 0: break
                g.frame()
            g.frame([d]); g.frame([d])
            if g.v('BOBSTATE') != S_TRANS: continue  # not in a booth, or it is this booth
            g.settle(); self.add(k, ('trans', d))

    def drive(self, k):
        g = self.g
        for d, n in (('LEFT', 8), ('RIGHT', 8), ('UP', 24), ('DOWN', 12)):
            g.restore(self.nodes[k][0])
            g.frame(['ENTER']); g.frame()
            if not g.v('LIFTDRV'): return
            for i in range(n): g.frame([d])
            g.frame(); g.frame(['ENTER']); g.frame()
            g.settle(); self.add(k, ('drive', d, n))

    def cannon(self, k):
        g = self.g
        g.restore(self.nodes[k][0]); g.frame(['SPACE'])
        g.settle(); self.add(k, ('fire',))
        for d in ('LEFT', 'RIGHT'):
            g.restore(self.nodes[k][0])
            for i in range(8): g.frame([d])
            g.frame(); self.add(k, ('roll', d))

    # ---- search -------------------------------------------------------------------------
    def explore(self):
        t0 = time.time()
        if self.root: self.g.restore(self.root)
        else: self.g.frame()
        self.add(None, ('start',))
        # waiting is a move wherever something moves on its own: platforms, pulverizers, and
        # live mutants (to let one pass the top of a ladder before climbing into its path)
        M = S['MUTTAB']
        mutants = any(self.g.h.mem[M + k * 10 + 7] for k in range(8))
        platforms = self.g.v('NPLAT') > 0 or self.g.v('PULVON') or mutants
        while self.queue:
            k = self.queue.popleft()
            s = k[2]
            if s == S_CANNON:
                self.cannon(k); continue
            done = self.done.get(k, set())
            for d in ('LEFT', 'RIGHT'):
                if d not in done: self.walk(k, d)
            for d in ('LEFT', 'RIGHT', None): self.jump(k, d)
            for d in ('UP', 'DOWN'): self.climb(k, d)
            if platforms: self.wait(k)
            if self.g.v('TRANSON'): self.transport(k)
            if len(k) > 3 and 'lift' in k: self.drive(k)
            if self.verbose and len(self.nodes) % 500 == 0:
                print('  nodes', len(self.nodes), 'queue', len(self.queue), 'claimed', len(self.claimed), '/', len(self.gaps))
        self.time = time.time() - t0
        return self

    def safe_set(self):
        """nodes from which Bob can get back to where he started"""
        start = next(iter(self.nodes))
        back = {}
        for a, b in self.edges: back.setdefault(b, []).append(a)
        safe, todo = {start}, [start]
        while todo:
            k = todo.pop()
            for a in back.get(k, []):
                if a not in safe: safe.add(a); todo.append(a)
        return safe

    def report(self):
        left = sorted(((a - 0xA000) % 128, (a - 0xA000) // 128) for a in self.gaps if a not in self.claimed)
        items_left = []
        for a in self.items:
            if a not in self.collected:
                items_left.append((self.g.h.mem[a], self.g.h.mem[a + 1], self.g.h.mem[a + 5] & 0x7F))
        return {'station': self.st, 'nodes': len(self.nodes), 'frames': self.g.total,
                'seconds': round(self.time, 1), 'sections': len(self.gaps),
                'unclaimed': left, 'items': len(self.items), 'items_missed': items_left,
                'deaths': self.deaths}


def replay(g, act, frame=None):
    """do one action of a path on the live game, exactly as the search did it (the search ran
    it from a snapshot of the same state, and the game is deterministic); frame(g) is called
    after every frame, to record"""
    def f(keys=()):
        s = g.frame(keys)
        if frame: frame(g)
        return s
    def settle(limit=300):
        for i in range(limit):
            s = g.v('BOBSTATE')
            if s in (S_GROUND, S_CANNON, S_DYING) and i > 0: return s
            f()
        return g.v('BOBSTATE')
    a = act[0]
    if a == 'walk':
        d, n = act[1], act[2]
        for i in range(n): s = f([d])
        if s != S_GROUND: settle()
    elif a == 'jump':
        keys = [act[1]] if act[1] else []
        f(keys + ['SPACE'])
        for i in range(120):
            if f(keys) in (S_GROUND, S_CANNON, S_DYING, S_SLIDE, S_LADDER): break
        if g.v('BOBSTATE') == S_SLIDE: settle()
    elif a == 'climb':
        d = act[1]; f([d])
        for i in range(400):
            if f([d]) != S_LADDER: break
        settle()
    elif a == 'wait':
        for i in range(act[1]):
            if f() != S_GROUND: break
        settle()
    elif a == 'trans':
        for i in range(60):
            if g.v('TRLOCK') == 0: break
            f()
        f([act[1]]); f([act[1]]); settle()
    elif a == 'drive':
        f(['ENTER']); f()
        for i in range(act[2]): f([act[1]])
        f(); f(['ENTER']); f(); settle()
    elif a == 'fire':
        f(['SPACE']); settle()
    elif a == 'roll':
        for i in range(8): f([act[1]])
        f()


def explore_station(st):
    """the explorer on one station, as a plain dict (for running stations in parallel)"""
    return Explorer(st).explore().report()


if __name__ == '__main__':
    # python3 explore.py 1 5 8 [-j N]: stations in parallel, N at a time (default: all cores)
    import parallel
    sts = parallel.stations() or list(range(1, 11))
    for st, r in parallel.each(explore_station, sts, parallel.jobs()):
        print('station %d: %d nodes, %d frames in %.1fs; sections %d, unclaimed %d %s; items %d, missed %s; deaths pruned %d'
              % (st, r['nodes'], r['frames'], r['seconds'], r['sections'], len(r['unclaimed']), r['unclaimed'][:40],
                 r['items'], r['items_missed'], r['deaths']), flush=True)
