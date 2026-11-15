import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
import sys, os
from designs_a import *
from textures import build
from render import render
from PIL import Image
os.makedirs(ROOT + '/out/prev', exist_ok=True)
tex = build('choir', ROOT + '/out')
names = list(CHOIR)
sheet = Image.new('RGB', (4*256, 4*256))
for i, n in enumerate(names):
    M = CHOIR[n]()
    sheet.paste(render(M, tex, 256), ((i % 4) * 256, (i // 4) * 256))
sheet.save(ROOT + '/out/prev/choir_sheet.png')
print('ok')
