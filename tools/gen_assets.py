import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
import os, json, sys
sys.path.insert(0, os.path.dirname(__file__))
from designs_a import CHOIR
from designs_b import MAW
from designs_t2 import CHOIR_T2, MAW_T2
from mesh import write_s3o
from textures import build
from render import render
from PIL import Image, ImageDraw

G = ROOT + '/game'
meta = {}
texs = {}
for fac in ('choir', 'maw'):
    texs[fac] = build(fac, f'{G}/unittextures')
for fac, table in (('choir', {**CHOIR, **CHOIR_T2}), ('maw', {**MAW, **MAW_T2})):
    for name, fn in table.items():
        M = fn()
        info = write_s3o(M, f'{G}/objects3d/{name}.s3o', f'{fac}_tex1.png', f'{fac}_tex2.png')
        meta[name] = dict(radius=info['radius'], height=info['height'], mid=[float(x) for x in info['mid']],
                          lo=[float(x) for x in info['lo']], hi=[float(x) for x in info['hi']],
                          pieces=list(M.order), faction=fac)
        # build picture (64x64 with border)
        img = render(M, texs[fac], 128, yaw=30, pitch=18, bg=(20, 16, 34) if fac == 'choir' else (30, 14, 12))
        d = ImageDraw.Draw(img); d.rectangle([0, 0, 127, 127], outline=(220, 190, 90) if fac == 'choir' else (255, 120, 30), width=3)
        img.save(f'{G}/unitpics/{name}.png')
json.dump(meta, open(ROOT + '/out/meta.json', 'w'), indent=1)
print(len(meta), 'models written')
