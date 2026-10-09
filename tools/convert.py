"""Convert the Atari stations (decoded from the ROM) to Model III block-graphics layouts.

Coordinates: Model III screen 128 x 48 blocks. Row 0-2 = status line (text row 0).
Mine rows 3..47.  Atari pixel x (0-159) -> X = x * 4 // 5.  Atari bitmap line y (8-191) -> Ym(y).
Output: build/m3_stations.json and src/stations.asm
"""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import json, base64
import numpy as np

S = json.load(open(_os.path.join(REPO, 'tools/data/atari_stations.json')))
ROM = open(_os.path.join(REPO, 'rom/atari_miner.rom'), 'rb').read()
rb = lambda a: ROM[a - 0x8000]
rw = lambda a: rb(a) | rb(a + 1) << 8

def X(px): return (px * 4) // 5
def Ym(y): return 3 + int(round((y - 8) * 44 / 183))

def atari_px(bm):
    b = np.frombuffer(bm, np.uint8).reshape(184, 40)
    return np.stack([(b >> 6) & 3, (b >> 4) & 3, (b >> 2) & 3, b & 3], 2).reshape(184, 160)

def top_line(a, x, y):
    # first colour-3 line at column x (0-159) near bitmap y (game coordinate)
    for yy in range(max(8, y - 7), min(191, y + 8)):
        if a[yy - 8, x] == 3:
            return yy
    return y

def top_line2(a, x, y):
    # nearest girder top to y at column x: a colour-3 pixel with no colour 3 one and two lines above
    best = None
    for yy in range(max(9, y - 4), min(191, y + 5)):
        if a[yy - 8, x] == 3 and a[yy - 9, x] != 3 and (yy < 10 or a[yy - 10, x] != 3):
            if best is None or abs(yy - y) < abs(best - y): best = yy
    return best if best is not None else y

def item_shape(i):
    p = rw(0x84C5 + 2 * i); w, h, pts = rb(p), rb(p + 1), rb(p + 2); nb = ((w - 1) >> 2) + 1
    pix = np.zeros((h, nb * 4), int)
    for r in range(h):
        for b in range(nb):
            v = rb(p + 3 + r * nb + b)
            for k in range(4): pix[r, b * 4 + k] = (v >> (6 - 2 * k)) & 3
    return w, h, pts, pix

def convert(s):
    st = S[str(s)]
    a = atari_px(base64.b64decode(st['bitmap']))
    surf = {}   # x -> set of rows
    runs = []
    for n, x, y, slope in st['girders']:
        prev = y
        for i in range(n):
            sx = x + 4 * i
            if sx > 159: break
            t = top_line2(a, min(159, sx + 1), prev)
            prev = t
            for mx in range(X(sx), X(min(160, sx + 4))):
                surf.setdefault(mx, set()).add(Ym(t))
    # Bob's floor at the bottom of every station: Atari BOB_Y $AA -> feet line $BF? use the bottom line
    pts = sorted((x, r) for x, rs in surf.items() for r in rs)
    # runs of the same row
    for r in sorted({r for _, r in pts}):
        xs = sorted(x for x, rr in pts if rr == r)
        i = 0
        while i < len(xs):
            j = i
            while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1: j += 1
            runs.append((xs[i], xs[j] - xs[i] + 1, r)); i = j + 1
    ladders = []
    for h, x, y, style in st['ladders']:
        px = x - 0x30
        top = y - 5 if style & 0x80 else y
        ladders.append((X(px) + 1, Ym(top), Ym(y + h)))
    slides = []
    for rows, x, y, step in st['slides']:
        sx = step - 256 if step > 127 else step
        x0 = X(x - 0x30) ; y0 = Ym(y + 0x15)
        x1 = X(x - 0x30 + sx * rows); y1 = Ym(y + 0x15 + rows)
        slides.append((x0, y0, x1, y1))
    items = []
    for shape, y, x in st['items']:
        sh = shape & 0x7F
        w, h, ptsv, pix = item_shape(sh)
        W = max(2, (w * 4 + 4) // 5); H = max(1, Ym(y + h) - Ym(y))
        H = min(H, 3)
        img = np.zeros((H, W), int)
        for yy in range(H):
            for xx in range(W):
                blk = pix[int(yy * h / H):max(int(yy * h / H) + 1, int((yy + 1) * h / H)), int(xx * w / W):max(int(xx * w / W) + 1, int((xx + 1) * w / W))]
                img[yy, xx] = 1 if (blk > 0).mean() >= 0.3 else 0
        bottom = Ym(y + h) - 1
        items.append({'shape': sh, 'x': X(x), 'y': bottom - H + 1, 'w': W, 'h': H, 'pts': ptsv, 'img': img.tolist()})
    muts = []
    for r in st['mutants']:
        if r[0] == 0: continue
        x, y = r[0] - 0x30, r[1]
        dx = 1 if r[7] < 128 else -1
        muts.append({'x': X(x), 'feet': Ym(y + 9 + 1), 'patrol': max(2, (r[6] * 4) // 5), 'dx': dx, 'delay': r[8], 'state': r[2]})
    bx, by = st['bob']
    bob = {'x': X(bx - 0x30), 'feet': Ym(by + 0x15)}
    return {'runs': runs, 'ladders': ladders, 'slides': slides, 'items': items, 'mutants': muts, 'bob': bob,
            'bonus': st['bonus'], 'trans': st['trans'], 'platforms': st['platforms']}

if __name__ == '__main__':
    out = {s: convert(s) for s in range(1, 11)}
    json.dump(out, open(_os.path.join(REPO, 'tools/data/m3_stations.json'), 'w'))
    for s in out: print(s, 'runs', len(out[s]['runs']), 'lad', len(out[s]['ladders']), 'items', len(out[s]['items']), 'muts', len(out[s]['mutants']), 'bob', out[s]['bob'])
