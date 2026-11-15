import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
import os
from designs_a import *
from designs_b import MAW
from textures import build
from render import render
from PIL import Image
tex = build('maw', ROOT + '/out')
sheet = Image.new('RGB', (4*256, 4*256))
for i, n in enumerate(MAW):
    sheet.paste(render(MAW[n](), tex, 256), ((i % 4) * 256, (i // 4) * 256))
sheet.save(ROOT + '/out/prev/maw_sheet.png'); print('ok')
