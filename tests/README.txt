Miner 2049er for the TRS-80 Model III -- automated playtester
=============================================================

Two versions that play the game identically (same Z80 core, same timing; the native
one finds exactly the same nodes and makes exactly the same moves):

  tests/    Python. Needs Python 3.9+ and:  pip install z80
            (Pillow and numpy only for screenshots: jumpover.py)
  emulator/native/   C++, about 7x faster.  Needs a C++17 compiler and zlib:
            make native   (from the repo root)        (macOS: Xcode command line tools; Linux: g++ zlib1g-dev)

zmac is optional: `make` at the repo root rebuilds and verifies build/; the tests
run on build/miner3.cmd.

Python (cd tests)
  python3 regress.py              the regression suite, about 10 seconds
  python3 regress.py --full       plus the explorer on all 10 stations (all cores)
  python3 regress.py --no-build   don't reassemble even if zmac is installed
  python3 explore.py 1 5 8        what Bob can reach on those stations (mutants off)
  python3 playthrough.py 3        play station 3 to the end, mutants off
  python3 playthrough.py 3 -m     ... with mutants
  python3 jumpover.py 1           play station 1 with mutants, then find and draw the
                                  places on the winning path where Bob jumps a mutant
  -j N  runs N stations at once (default: all cores); -v prints the search as it goes
  (-v implies -j 1).  No station numbers = all ten.

Native (cd emulator/native)
  ./m3test explore 1 5 8          same as explore.py
  ./m3test play 3 [-m] [-v]       same as playthrough.py
  ./m3test check 20000            the idle skip against running the idle loop, byte for byte
  ./m3test trace 1 400            a hash per frame; python3 ../../tests/trace.py 1 400 must match
  -j N, -v as above; --no-skip runs WAITTICK's idle loop instead of jumping over it.

Output
  regress.py: one line per check ("ok" or "FAIL" plus detail); exit status 1 on failure.
  explore: per station the sections it could never claim (x, row) and the items it could
    never pick up.  Station 5's poisoned goblet always shows, since touching it kills.
  play: whether the station was cleared, moves used, backtracks, game time, bonus left.

Memory: snapshots are stored as an XOR against the station's starting image, compressed
(about 0.7 KB each instead of 64 KB); the largest searches stay under ~100 MB.
