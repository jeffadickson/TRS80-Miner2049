import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import base64, json, sys
root=REPO + '/'
t=open(root+'web/player_template.html').read()
cmd=base64.b64encode(open(root+'build/miner3.cmd','rb').read()).decode()
font=open(root+'web/font.json').read()
v=sys.argv[1] if len(sys.argv)>1 else '0.1'
t=t.replace('__CMD__',cmd).replace('__FONT__',font).replace('__VERSION__',v)
open(root+'web/out/index.html','w').write(t); print('ok',len(t))
