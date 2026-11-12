import os
from designs_a import *
from designs_b import MAW
from textures import build
from render import render
from PIL import Image
tex = build('maw', '/home/claude/vb/out')
sheet = Image.new('RGB', (4*256, 4*256))
for i, n in enumerate(MAW):
    sheet.paste(render(MAW[n](), tex, 256), ((i % 4) * 256, (i // 4) * 256))
sheet.save('/home/claude/vb/out/prev/maw_sheet.png'); print('ok')
