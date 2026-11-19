import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
import os, json, sys
sys.path.insert(0, os.path.dirname(__file__))
from gen_assets_tables import TABLES, BG, BORDER, ORDER
from mesh import write_s3o
from textures import build
from render import render
from PIL import Image, ImageDraw

# usage:  python3 tools/gen_assets.py                 every faction (rewrites every model, texture and build picture)
#         python3 tools/gen_assets.py tympan miasma   only these factions; out/meta.json is merged, nothing else is touched
facs = [f for f in sys.argv[1:] if f in TABLES] or ORDER
G = ROOT + '/game'
meta_path = ROOT + '/out/meta.json'
meta = json.load(open(meta_path)) if (len(facs) < len(ORDER) and os.path.exists(meta_path)) else {}
texs = {}
for fac in facs:
    texs[fac] = build(fac, f'{G}/unittextures')
for fac in facs:
    for name, fn in TABLES[fac].items():
        M = fn()
        info = write_s3o(M, f'{G}/objects3d/{name}.s3o', f'{fac}_tex1.png', f'{fac}_tex2.png')
        meta[name] = dict(radius=info['radius'], height=info['height'], mid=[float(x) for x in info['mid']],
                          lo=[float(x) for x in info['lo']], hi=[float(x) for x in info['hi']],
                          pieces=list(M.order), faction=fac)
        # build picture (128x128 with border)
        img = render(M, texs[fac], 128, yaw=30, pitch=18, bg=BG[fac])
        d = ImageDraw.Draw(img); d.rectangle([0, 0, 127, 127], outline=BORDER[fac], width=3)
        img.save(f'{G}/unitpics/{name}.png')
json.dump(meta, open(meta_path, 'w'), indent=1)
print(len(meta), 'models in meta.json;', sum(len(TABLES[f]) for f in facs), 'written for', ', '.join(facs))
