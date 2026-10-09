import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from dump import *
from m3 import M3
import sys
def start(st, frames=70):
    h=M3(); h.load_cmd('../build/miner3.cmd')
    def run(n,keys=()):
        h.keys=set(keys)
        for i in range(n): h.run_frame()
    run(20); run(3,[str(st%10)]); run(3); run(3,['SPACE']); run(frames)
    return h,run
if __name__=='__main__':
    for st in map(int,sys.argv[1:]):
        h,run=start(st)
        big(h,'/tmp/st%d.png'%st)
        print(st,'state',var(h,'BOBSTATE'),'bob',var(h,'BOBX'),var(h,'BOBY'),'lives',var(h,'LIVES'))
