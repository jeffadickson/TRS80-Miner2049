"""Run one job per station on several cores.  jobs(argv) reads -j N (default: all cores;
-j 1 runs in this process); each(fn, stations, n) yields (station, result) as they finish."""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import os, sys
from multiprocessing import Pool

def jobs(argv=sys.argv):
    for i, a in enumerate(argv):
        if a == '-j' and i + 1 < len(argv): return max(1, int(argv[i + 1]))
        if a.startswith('-j') and a[2:].isdigit(): return max(1, int(a[2:]))
    return os.cpu_count() or 1

def stations(argv=sys.argv):
    """station numbers from the command line (the number after -j is not one)"""
    out, skip = [], False
    for a in argv[1:]:
        if skip: skip = False; continue
        if a == '-j': skip = True; continue
        if a.isdigit(): out.append(int(a))
    return out

def _call(arg):
    fn, st = arg
    return st, fn(st)

def each(fn, sts, n):
    if n <= 1 or len(sts) <= 1:
        for st in sts: yield st, fn(st)
        return
    with Pool(min(n, len(sts)), maxtasksperchild=1) as p:      # a fresh process per station
        for r in p.imap_unordered(_call, [(fn, st) for st in sts]):
            yield r
