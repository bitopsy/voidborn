import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
"""Writes ONLY the ten tier 3 models (five labs, five heavies) with their build pictures, and merges them into out/meta.json.
Nothing of the older models, textures or pictures is touched (gen_assets.py would rewrite every model of a faction).
usage: python3 tools/gen_assets_t3.py"""
import os, json, sys, tempfile
os.makedirs(ROOT + '/out', exist_ok=True)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_assets_tables import BG, BORDER
from designs_t3 import T3
from mesh import write_s3o
from textures import build
from render import render
from PIL import ImageDraw
G = ROOT + '/game'
meta_path = ROOT + '/out/meta.json'
meta = json.load(open(meta_path)) if _os.path.exists(meta_path) else {}      # out/meta.json is not in git; a fresh clone starts with only the T3 entries (enough for gen_t3.py)
tmp = tempfile.mkdtemp()                      # textures are rebuilt here only to render the build pictures; game/unittextures stays as it is
for fac, table in T3.items():
    tex = build(fac, tmp)
    for name, fn in table.items():
        M = fn()
        info = write_s3o(M, f'{G}/objects3d/{name}.s3o', f'{fac}_tex1.png', f'{fac}_tex2.png')
        meta[name] = dict(radius=info['radius'], height=info['height'], mid=[float(x) for x in info['mid']], lo=[float(x) for x in info['lo']],
                          hi=[float(x) for x in info['hi']], pieces=list(M.order), faction=fac)
        img = render(M, tex, 128, yaw=30, pitch=18, bg=BG[fac])
        d = ImageDraw.Draw(img); d.rectangle([0, 0, 127, 127], outline=BORDER[fac], width=3)
        img.save(f'{G}/unitpics/{name}.png')
        print(name, M.order, 'r=%d h=%d' % (info['radius'], info['height']))
json.dump(meta, open(meta_path, 'w'), indent=1)
