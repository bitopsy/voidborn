#!/usr/bin/env python3
"""Contact sheet of the models of one faction (or of a list of unit names), rendered with the software renderer.

    python3 tools/preview_factions.py tympan            -> out/prev/tympan_sheet.png
    python3 tools/preview_factions.py miasma ty_auditor ...   (only those units)
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw
from textures import build
from render import render
import gen_assets_tables as T

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

def main(argv):
    fac = argv[0]; only = argv[1:]
    table = T.TABLES[fac]
    os.makedirs(ROOT + '/out/prev', exist_ok=True)
    tex = build(fac, ROOT + '/out/prev')
    names = [n for n in table if (not only or n in only)]
    cols = 4; cell = 300
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell, rows * cell), (10, 8, 18))
    for i, n in enumerate(names):
        M = table[n]()
        bg = T.BG[fac]
        im = render(M, tex, cell - 20, yaw=30, pitch=18, bg=bg)
        d = ImageDraw.Draw(sheet)
        x, y = (i % cols) * cell, (i // cols) * cell
        sheet.paste(im, (x + 10, y + 10)); d.text((x + 14, y + 12), n, fill=(255, 255, 255))
    out = ROOT + f'/out/prev/{fac}_sheet.png'
    sheet.save(out); print(out, len(names), 'models')

if __name__ == '__main__':
    main(sys.argv[1:])
