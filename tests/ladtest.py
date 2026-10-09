import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

from shots import *
import re
src=open('../src/data.asm').read()
fails=[]; n=0
for st in range(1,11):
    lad=re.search(r'ST%d_LAD:[^\n]*\n(.*?)\tdb\t\$FF'%st,src,re.S).group(1)
    L=[tuple(map(int,m.split(','))) for m in re.findall(r'db\t([\d,]+)',lad)]
    for lx,top,bot in L:
        n+=1
        h,run=start(st,80)
        M=S['MUTTAB']
        def nomut():
            for k in range(8): h.mem[M+k*10+7]=0
            h.mem[S['HAZON']]=0; h.mem[S['PULVON']]=0
        nomut()
        h.mem[S['BOBX']]=lx-1; h.mem[S['BOBY']]=bot-6; h.mem[S['BOBSTATE']]=0
        run(3); nomut()
        for i in range(140):
            run(1,['UP']); nomut()
            if var(h,'BOBSTATE')==0 and i>2: break
        topfeet=var(h,'BOBY')+6
        run(3); nomut()
        for i in range(140):
            run(1,['DOWN']); nomut()
            if var(h,'BOBSTATE')==0 and i>2: break
        botfeet=var(h,'BOBY')+6
        if not (abs(topfeet-top)<=1 and abs(botfeet-bot)<=1): fails.append((st,lx,top,bot,topfeet,botfeet))
print(n,'ladders; fails',fails)
