# Miner 2049er for the TRS-80 Model III

A port of Bill Hogue's *Miner 2049er* (Big Five Software, 1982, Atari 400/800) to the
TRS-80 Model III, in Z80 assembly: all ten stations with their specials (transporters,
moving platforms, waste box, lift, pulverizers, cannon), 64×16 block graphics, 30 Hz,
1-bit sound through the cassette port. Plus an automated playtester that plays it
through the real code, in Python and in C++.

Repository: https://github.com/jeffadickson/TRS80-Miner2049

## Play

- `build/miner3.cmd`: load from TRSDOS/LDOS, or in an emulator (trs80gp, sdltrs).
- `build/MINER3H.CAS` / `MINER3L.CAS`: cassette, 1500 / 500 baud (SYSTEM, name MINER3).
- `web/out/index.html`: open in a browser.

Keys: arrows, SPACE jump, ENTER drive the lift, 1-4 transporter. On the title screen,
I toggles invincibility; with it on, U shows unclaimed land and N skips to the next station.

## Layout

| Path | Contents |
|---|---|
| `src/` | Z80 source (zmac): `miner3.asm`, `specials.asm`, generated `data.asm` and `tables.asm` |
| `build/` | the verified binaries (`make` rebuilds and checks them) |
| `tools/` | station data pipeline from the Atari cartridge (`extract`, `convert`, `gen_data`), cassette maker, web builder, screenshots; `data/` the extracted stations |
| `tests/` | the automated playtester: regression suite, explorer, playthrough |
| `emulator/` | Model III harness (`m3.py`) and the native C++ playtester (`native/`) |
| `web/` | browser-playable version: `out/index.html`, its template and font |
| `book/` | text and figures |
| `rom/` | where your own Atari cartridge dump goes, only for `make regen` (not distributed) |

## Build, verify, test

Needs [zmac](http://48k.ca/zmac.html) and Python 3; the tests need `pip install z80`.

    make            # assemble, make the cassettes, verify all three against their SHA-256
    make test       # ... then the regression suite (about 10 s)
    make test-full  # ... plus the explorer on every station
    make native     # the C++ playtester, ~7x faster: emulator/native/m3test explore | play
    make web        # rebuild the browser version

See `tests/README.txt` for the playtester (explorer, playthrough, mutants, parallel runs).

## Licence

Code: MIT (`LICENSE`). Book and art: all rights reserved (`book/LICENSE`).
Miner 2049er itself: see `NOTICE`.
