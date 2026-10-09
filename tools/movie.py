import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from m3 import M3
from PIL import Image
def record(script, path, every=2, scale=3, start_capture=0, debug=True):
    h=M3(); h.load_cmd('../build/miner3.cmd')
    frames=[]; f=0
    for n, keys in script:
        h.keys=set(keys)
        for i in range(n):
            h.run_frame(); f+=1
            if f>=start_capture and f%every==0: frames.append(h.screen(scale,debug=debug))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=1000//30*every, loop=0)
    return h
if __name__=='__main__':
    import sys
    record([(20,[]),(3,['SPACE']),(50,[]),(120,['RIGHT']),(4,['UP']),(60,['UP']),(40,['LEFT'])],_os.path.join(REPO, 'build/play1.gif'),every=3,scale=2,start_capture=70)
