import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import sys
from explore import Explorer
from dump import big
from PIL import Image, ImageDraw
def reachmap(st, path):
    e = Explorer(st).explore()
    g = e.g
    g.restore(e.nodes[next(iter(e.nodes))][0])
    im = big(g.h, '/tmp/_x.png').convert('RGB')
    d = ImageDraw.Draw(im)
    for x, feet in e.positions:
        d.rectangle([x*4+8, (feet-1)*8+2, x*4+15, feet*8-2], outline=(0,200,0))
    for a in e.gaps:
        if a not in e.claimed:
            i = a - 0xA000; x, y = i % 128, i // 128
            d.rectangle([x*4, y*8, x*4+3, y*8+7], fill=(255,40,40))
    for a in e.items:
        if a not in e.collected:
            m = g.h.mem; x, y, w, h = m[a], m[a+1], m[a+2], m[a+3]
            d.rectangle([x*4, y*8, (x+w)*4, (y+h)*8], outline=(255,160,0), width=2)
    im.save(path)
    return e.report()
if __name__ == '__main__':
    for st in map(int, sys.argv[1:]):
        r = reachmap(st, '/tmp/reach%d.png' % st)
        print(st, len(r['unclaimed']), r['items_missed'])
