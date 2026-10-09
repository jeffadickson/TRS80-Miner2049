"""Automated playtester, part 2: play each station through with key presses.

Greedy with backtracking.  From the live game a bounded breadth-first search (the
explorer's macros, run for real from a snapshot) lists the action sequences that claim
something, best first (most sections per frame).  The best becomes the live game; if
later nothing more can be claimed from there (Bob has dropped somewhere he cannot climb
back from, say, or left the lift on the wrong side), the search backs up and tries the
next best choice.  The bonus is NOT frozen; with mutants on (-m) they move and kill for
real (a branch where Bob dies is simply not taken).
"""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys, time
from explore import Game, Explorer, S

def sections(snap):
    """sections left to claim (0 once the game has moved on to the next station)"""
    if snap.meta['STATION'] != CUR_ST: return 0
    return snap.meta['SECTIONS']

def path_to(e, k):
    acts = []
    while k is not None:
        snap, parent, act = e.nodes[k][:3]
        acts.append(act); k = parent
    return list(reversed(acts))[1:]

SAFE = None
VERBOSE = False
CUR_ST = 0
DUMP = 0
LAST_ACTS = None

def candidates(st, g, root, budget, top=128, keep=4):
    """claiming moves from root, best first: [(score, snapshot, actions)]; the search
    widens (budget x 4) until it finds some, up to top x the budget"""
    base = sections(root); f0 = root[2]; b = budget
    while b <= budget * top:
        e = Explorer(st, max_nodes=b, game=g, root=root)
        e.explore()
        if e.cleared:                               # a move that finishes the station
            snap, parent, act = e.cleared
            return [(1e9, snap, path_to(e, parent) + [act])]
        c = []
        for k, node in e.nodes.items():
            gain = base - sections(node[0])
            if gain > 0 and not overloaded(st, g, node[0]):
                c.append((gain / max(1, node[0][2] - f0), node[0], path_to(e, k)))
        if c:
            def safe(snap):
                if SAFE is None: return True
                g.restore(snap); return g.key(mutants=False) in SAFE
            # moves after which Bob can still get back to the start come first: one-way
            # places (a drop he cannot climb back from) are left until nothing else is left
            c = [(sc, snap, acts, safe(snap)) for sc, snap, acts in c]
            c.sort(key=lambda x: (not x[3], -x[0]))
            c = [x[:3] for x in c]
            # keep the best few, and only one per distinct result
            out, seen = [], set()
            for sc, snap, acts in c:
                sig = (sections(snap), snap.meta['BOBX'], snap.meta['BOBY'])
                if sig not in seen:
                    seen.add(sig); out.append((sc, snap, acts))
                if len(out) >= keep: break
            return out
        b *= 4
    return []

def overloaded(st, g, snap):
    """station 10's dead ends: the cannon needs exactly 1, 2 or 3 tons to reach the lowest,
    middle or top platforms.  Dead if, for a platform row with sections still to claim, no
    load of exactly its tons can be made any more (from what he carries, or from the TNT
    bundles left in the store), or if he carries more than 3 tons while any remain."""
    if st != 10: return False
    m = snap[0]; off = 44
    rows = [tons for row, tons in ((30, 1), (20, 2), (10, 3))
            if any(m[off + 0xA000 + row * 128 + x] == 5 for x in range(128))]
    if not rows: return False
    carried = m[off + S['TNT']]
    if carried > 3: return True
    left = []                               # tons of each bundle still in the store
    base = S['ITEMTAB']
    for k in range(m[off + S['NITEMS']]):
        rec = off + base + k * 9
        if m[rec + 8] and 34 <= (m[rec + 5] & 0x7F) <= 36: left.append(m[rec + 4])
    sums = {0}
    for v in left: sums |= {s + v for s in sums}
    return any(not (carried == tons or tons in sums) for tons in rows)

def viable(st, g, snap, cap=150):
    """False if from snap Bob is shut in somewhere that does not hold everything still to
    claim: a small search runs out of places to go before claiming it all"""
    if overloaded(st, g, snap): return False
    e = Explorer(st, max_nodes=cap, game=g, root=snap)
    e.g.freeze = True                       # (the question is where, not how soon)
    e.explore()
    e.g.freeze = False
    if len(e.nodes) >= cap: return True     # plenty of room: no dead end
    if e.open_gaps and VERBOSE:
        g.restore(snap)
        print('    dead end at', g.pos(), 'reachable', len(e.nodes), 'unclaimable from there', len(e.open_gaps))
    return not e.open_gaps                  # shut in: fine only if all that is left is in here

def play(st, mutants=False, budget=100, verbose=False, max_backtracks=60, frozen=False):
    global VERBOSE, SAFE, CUR_ST
    VERBOSE = verbose; CUR_ST = st
    t0 = time.time()
    # a map first: positions from which Bob can get back to where he started (with the
    # dead-end test, this keeps the greedy choices away from one-way drops until last)
    ex = Explorer(st).explore()
    SAFE = ex.safe_set(); del ex
    g = Game(st, mutants=mutants, freeze=frozen)
    root = g.snap()
    stack = [[root, candidates(st, g, root, budget), [], budget]]   # state, choices left, actions, search size
    backtracks = 0
    while True:
        state, choices, acts, b = stack[-1]
        if sections(state) == 0: break
        if not choices and b < budget * 1024:    # (nodes are ~1 KB compact snapshots: ~100 MB at the widest)
            # every move found leads into a dead end: look further afield before backing up
            b = stack[-1][3] = b * 4
            seen = set()
            stack[-1][1] = [c for c in candidates(st, g, state, b, top=1, keep=40)]
            if verbose: print('  wider search (%d): %d moves' % (b, len(stack[-1][1])))
            continue
        if not choices:
            stack.pop(); backtracks += 1
            if not stack or backtracks > max_backtracks:
                g.restore(state)
                img = state[0]
                left = [((a - 0xA000) % 128, (a - 0xA000) // 128) for a in range(0xA000, 0xB800) if img[44 + a] == 5]
                return {'station': st, 'cleared': False, 'left': sections(state), 'gaps': left[:20], 'backtracks': backtracks,
                        'where': g.pos(), 'game_seconds': round(state[2] / 30, 1), 'seconds': round(time.time() - t0)}
            if verbose: print('  back up: sections left', sections(stack[-1][0]))
            continue
        sc, snap, path = choices.pop(0)
        if DUMP and sections(snap) <= DUMP:
            import pickle; pickle.dump(snap, open('st%d_snap.pkl' % st, 'wb'))
            return {'station': st, 'dumped': sections(snap)}
        if sections(snap) and not viable(st, g, snap):
            if verbose: print('  skip a move into a dead end')
            continue
        if verbose: print('  sections left', sections(snap), 'game time %.1fs' % (snap[2] / 30))
        stack.append([snap, candidates(st, g, snap, budget) if sections(snap) else [], acts + path, budget])
    state, _, acts, _ = stack[-1]
    global LAST_ACTS; LAST_ACTS = acts            # the winning path, for replay()
    g.restore(state)
    bonus = g.v('BONUS')
    for i in range(400):                            # the tally, and on to the next station
        g.frame()
        if g.v('STATION') != st: break
    return {'station': st, 'cleared': g.v('STATION') != st, 'actions': len(acts), 'backtracks': backtracks,
            'game_seconds': round(state[2] / 30, 1), 'bonus_left': '%02X00' % bonus,
            'next_station': g.v('STATION'), 'seconds': round(time.time() - t0)}

OPTS = {}
def play_station(st):
    return play(st, **OPTS)

if __name__ == '__main__':
    # python3 playthrough.py 3 4 5 [-m] [-v] [-f] [-j N]: stations in parallel, N at a time
    # (default: all cores; -v output from parallel runs interleaves, so -v implies -j 1
    # unless -j is given)
    import parallel
    if '-d' in sys.argv: DUMP = 3
    OPTS = dict(mutants='-m' in sys.argv, verbose='-v' in sys.argv, frozen='-f' in sys.argv)
    sts = parallel.stations() or list(range(1, 11))
    n = parallel.jobs() if ('-j' in ' '.join(sys.argv) or not OPTS['verbose']) else 1
    for st, r in parallel.each(play_station, sts, n):
        print(r, flush=True)
