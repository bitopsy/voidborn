import sys, os
from designs_a import *
from textures import build
from render import render
from PIL import Image
os.makedirs('/home/claude/vb/out/prev', exist_ok=True)
tex = build('choir', '/home/claude/vb/out')
names = list(CHOIR)
sheet = Image.new('RGB', (4*256, 4*256))
for i, n in enumerate(names):
    M = CHOIR[n]()
    sheet.paste(render(M, tex, 256), ((i % 4) * 256, (i // 4) * 256))
sheet.save('/home/claude/vb/out/prev/choir_sheet.png')
print('ok')
