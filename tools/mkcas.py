"""Make SYSTEM-format cassette images (.CAS) of a /CMD file for the Model III.
   low speed (500 baud):   256 x $00, $A5, then the SYSTEM records
   high speed (1500 baud): 256 x $55, $7F, then the same records
   SYSTEM records: $55, 6-character name; blocks of $3C, count (0 = 256), address lo, hi,
   data, checksum (address bytes + data, mod 256); $78, entry lo, hi."""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys
def segments(cmd):
    d = open(cmd, 'rb').read(); i = 0; segs = []; entry = None
    while i < len(d):
        typ, ln = d[i], d[i + 1]; i += 2
        if typ == 1:
            n = ln if ln > 2 else ln + 256
            addr = d[i] | d[i + 1] << 8
            segs.append((addr, d[i + 2:i + n])); i += n
        elif typ == 2:
            entry = d[i] | d[i + 1] << 8; break
        else:
            i += ln
    return segs, entry
def system_records(segs, entry, name):
    out = bytearray([0x55]) + name.upper().ljust(6)[:6].encode()
    for addr, data in segs:
        for k in range(0, len(data), 256):
            blk = data[k:k + 256]; a = addr + k
            out += bytes([0x3C, len(blk) & 255, a & 255, a >> 8]) + blk
            out.append((a & 255) + (a >> 8) + sum(blk) & 255)
    out += bytes([0x78, entry & 255, entry >> 8])
    return out
if __name__ == '__main__':
    cmd, base, name = sys.argv[1], sys.argv[2], sys.argv[3]
    segs, entry = segments(cmd)
    rec = system_records(segs, entry, name)
    open(base + 'L.CAS', 'wb').write(bytes(256) + b'\xA5' + rec)
    open(base + 'H.CAS', 'wb').write(b'\x55' * 256 + b'\x7F' + rec)
    print('segments', [(hex(a), len(d)) for a, d in segs], 'entry', hex(entry), 'bytes', len(rec))
