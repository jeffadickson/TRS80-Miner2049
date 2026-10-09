import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from shots import *
from prof3 import busy
h,run=start(6)
run(60,['RIGHT']); print('6 walk right ->',var(h,'BOBX'),var(h,'BOBSTATE'),var(h,'LIVES'))
h,run=start(8)
for i in range(40):
    run(1,['LEFT'])
    if var(h,'BOBX')<=92: break
run(2); run(2,['SPACE']); run(2)
print('8 drv',var(h,'LIFTDRV'))
run(30,['LEFT']); print(' after left: lift',var(h,'LIFTX'),'bob',var(h,'BOBX'))
h.keys={'LEFT'}; print(' busy moving',busy(h,3,['LEFT']))
run(40,['UP']); print(' after up: lift row',var(h,'LIFTROW'),'boby',var(h,'BOBY'),'state',var(h,'BOBSTATE'))
big(h,'/tmp/l8.png')
run(2,['SPACE']); run(2); print(' drv off',var(h,'LIFTDRV'))
run(20,['LEFT']); print(' walked',var(h,'BOBX'),var(h,'BOBY'),var(h,'BOBSTATE'))
h,run=start(8)
for i in range(40):
    run(1,['LEFT'])
    if var(h,'BOBX')<=92: break
run(2); run(2,['SPACE']); run(30,['DOWN']); print('8 down: row',var(h,'LIFTROW'),'state',var(h,'BOBSTATE'))
h,run=start(9)
h.mem[S['BOBX']]=56; h.mem[S['BOBY']]=41
for i in range(300):
    run(1)
    if var(h,'BOBSTATE')==5: break
print('9 died after',i,'frames; heads',[h.mem[S['PULVTAB']+4*k+1] for k in range(4)])
h,run=start(9); print(' busy 9 over time',[busy(h,1)[0] for i in range(40)])
h,run=start(10)
h.mem[S['TNT']]=1
for i in range(60):
    run(1,['LEFT'])
    if var(h,'BOBSTATE')==7: break
print('10 in cannon',var(h,'BOBSTATE'),var(h,'BOBX'),'canx',var(h,'CANX'))
run(10,['LEFT']); print(' rolled',var(h,'CANX'),var(h,'BOBX'))
run(10,['RIGHT']); print(' rolled',var(h,'CANX'),var(h,'BOBX'))
big(h,'/tmp/c10a.png')
run(1,['SPACE'])
for i in range(40):
    run(1)
    if var(h,'BOBSTATE')!=8: break
print(' landed state',var(h,'BOBSTATE'),'feet',var(h,'BOBY')+6,'x',var(h,'BOBX'))
run(20); print(' later',var(h,'BOBSTATE'),var(h,'BOBY')+6,'canx',var(h,'CANX'))
big(h,'/tmp/c10.png')
