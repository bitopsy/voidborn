#!/usr/bin/env python3
"""Pictures of the docked HUD column (tooltip, build menu, radars, census, minimap) from the mock engine.
   python3 tools/render_hud.py [outdir]     needs: pip install lupa pillow"""
import os, sys, glob, tempfile, lupa
from PIL import Image, ImageDraw, ImageFont
try:
    from lupa import lua51 as _L
except ImportError:
    _L = lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(root, "docs")
os.makedirs(out, exist_ok=True)
tmp = tempfile.mkdtemp()
rt = _L.LuaRuntime(); g = rt.globals(); g.ROOT = root; g.DUMP_DIR = tmp
g.UNIT_FILES = rt.table_from(sorted(glob.glob(os.path.join(root, "game/units/*.lua"))))
rt.execute(open(os.path.join(root, "tools/test_dock.lua")).read())

def font(size):
    for f in ("DejaVuSans-Bold.ttf", "DejaVuSans.ttf", "LiberationSans-Regular.ttf"):
        for d in ("/usr/share/fonts/truetype/dejavu/", "/usr/share/fonts/truetype/liberation/"):
            if os.path.exists(d + f): return ImageFont.truetype(d + f, max(6, int(size)))
    return ImageFont.load_default()

for name in ("default", "selected", "small"):
    lines = open(os.path.join(tmp, name + ".txt"), encoding="utf-8").read().split("\n")
    W, H = map(int, lines[0].split()[1:3])
    im = Image.new("RGB", (W, H), (22, 30, 24))
    d = ImageDraw.Draw(im, "RGBA")
    # a stand-in for the game world
    for i in range(0, W, 120): d.line([(i, 0), (i, H)], fill=(34, 46, 36, 255))
    for i in range(0, H, 120): d.line([(0, i), (W, i)], fill=(34, 46, 36, 255))
    for ln in lines[1:]:
        if not ln: continue
        k = ln[0]
        if k == "M":
            x, y, w, h = map(int, ln.split()[1:5])
            ty = y   # the command counts y from the top of the screen
            d.rectangle([x, ty, x + w, ty + h], fill=(40, 70, 90, 255)); d.line([(x, ty), (x + w, ty + h)], fill=(90, 140, 170, 255)); d.line([(x + w, ty), (x, ty + h)], fill=(90, 140, 170, 255))
        elif k == "R":
            r, gg, b, a, x1, y1, x2, y2 = map(float, ln.split()[1:9])
            d.rectangle([min(x1, x2), H - max(y1, y2), max(x1, x2) - 1, H - min(y1, y2) - 1], fill=(int(r*255), int(gg*255), int(b*255), int(a*255)))
        elif k == "P":
            parts = ln.split()
            r, gg, b, a = map(float, parts[1:5]); mode = parts[5]; w = float(parts[6]); v = list(map(float, parts[7:]))
            pts = [(v[i], H - v[i+1]) for i in range(0, len(v) - 1, 2)]
            col = (int(r*255), int(gg*255), int(b*255), int(a*255))
            if len(pts) < 2: continue
            if mode in ("LINE_LOOP", "LINE_STRIP"): d.line(pts + ([pts[0]] if mode == "LINE_LOOP" else []), fill=col, width=max(1, int(w)))
            elif mode == "LINES":
                for i in range(0, len(pts) - 1, 2): d.line(pts[i:i+2], fill=col, width=max(1, int(w)))
            elif mode == "TRIANGLE_FAN":
                for i in range(1, len(pts) - 1): d.polygon([pts[0], pts[i], pts[i+1]], fill=col)
            elif mode == "TRIANGLES":
                for i in range(0, len(pts) - 2, 3): d.polygon(pts[i:i+3], fill=col)
            elif mode == "TRIANGLE_STRIP":
                for i in range(len(pts) - 2): d.polygon(pts[i:i+3], fill=col)
        elif k == "T":
            head, s = ln.split("\t", 1)
            p = head.split(); r, gg, b, a, x, y, size = map(float, p[1:8]); opts = p[8] if len(p) > 8 else "-"
            f = font(size * 0.85); col = (int(r*255), int(gg*255), int(b*255), int(a*255))
            tw = d.textlength(s, font=f)
            if "c" in opts: x -= tw / 2
            elif "r" in opts: x -= tw
            d.text((x, H - y - size * 1.0), s, font=f, fill=col)
    path = os.path.join(out, f"hud_dock_{name}.png")
    im.convert("RGB").save(path); print(path)
