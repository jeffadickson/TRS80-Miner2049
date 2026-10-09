"""Extract Miner 2049er station definitions from the Atari ROM into JSON."""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import json, base64
ROM=open(_os.path.join(REPO, 'rom/atari_miner.rom'),'rb').read()
rb=lambda a: ROM[a-0x8000]
rw=lambda a: rb(a)|rb(a+1)<<8
ST=json.load(open(_os.path.join(REPO, '../BigFive-Miner2049/tools/analysis/stations.json')))
def lbl(name):
    for f in __import__('glob').glob(_os.path.join(REPO, '../BigFive-Miner2049/src/annot/*.txt')):
        for l in open(f):
            p=l.split()
            if len(p)==3 and p[0]=='L' and p[2]==name: return int(p[1],16)
    raise KeyError(name)
BSX,BSY,BON,TRC=lbl('BOB_START_X'),lbl('BOB_START_Y'),lbl('BONUS_BASE'),lbl('TRANS_COLUMN')
def readlist(a,n,term=True):
    out=[]
    while rb(a)!=0:
        out.append([rb(a+i) for i in range(n)]); a+=n
    return out,a+1
res={}
for s in range(1,11):
    e=0x8507+8*s
    lad,sli,plat,gir=rw(e),rw(e+2),rw(e+4),rw(e+6)
    L,_=readlist(lad,4); S,_=readlist(sli,4); P,_=readlist(plat,6)
    g=[];a=gir
    for slope in (3,5,0):
        lst,a=readlist(a,3); g+= [[n,x,y,slope] for n,x,y in lst]
    items,_=readlist(rw(0x8565+2*s),3)
    mut=[[rb(rw(0x857B+2*s)+11*k+i) for i in range(11)] for k in range(8)]
    bm=base64.b64decode(ST[str(s)]['bitmap'])
    res[s]={'ladders':L,'slides':S,'platforms':P,'girders':g,'items':items,'mutants':mut,
            'bob':[rb(BSX+s),rb(BSY+s)],'bonus':rb(BON+s),'trans':rb(TRC+s),
            'bitmap':base64.b64encode(bm).decode(),'sections':ST[str(s)]['sections']}
    print(s,'lad',len(L),'sli',len(S),'plat',len(P),'gir',len(g),'items',len(items),'bob',res[s]['bob'],'bonus',res[s]['bonus'])
json.dump(res,open('../build/atari_stations.json','w'))
