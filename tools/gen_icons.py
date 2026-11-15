#!/usr/bin/env python3
"""Generates the zoomed-out unit icons: one icon per ROLE (customParams.kind), shared by both factions.
Writes game/icons/vb_<kind>.png (white glyph on transparent; the engine tints it with the team colour)
and game/gamedata/icontypes.lua.  Run from anywhere:  python3 tools/gen_icons.py
"""
import math, os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "game", "icons")
S, C = 512, 256                      # drawn at 512 px, shipped at 128 px (antialiased)
W, CLEAR = (255, 255, 255, 255), (0, 0, 0, 0)

def rot(pts, deg, cx=C, cy=C):
    a = math.radians(deg); ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]
def ngon(n, r, cx=C, cy=C, start=-90):
    return [(cx + r * math.cos(math.radians(start + 360 * i / n)), cy + r * math.sin(math.radians(start + 360 * i / n))) for i in range(n)]
def star(n, ro, ri, cx=C, cy=C):
    return [(cx + (ro if i % 2 == 0 else ri) * math.cos(math.radians(-90 + 180 * i / n)),
             cy + (ro if i % 2 == 0 else ri) * math.sin(math.radians(-90 + 180 * i / n))) for i in range(2 * n)]
def circle(d, r, cx=C, cy=C, fill=W): d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)
def ring(d, r, w, cx=C, cy=C):
    circle(d, r, cx, cy, W); circle(d, r - w, cx, cy, CLEAR)

def com(d):      # commander: star in a ring
    ring(d, 232, 26); d.polygon(star(5, 170, 70, C, C + 10), fill=W)
def con(d):      # builder: gear
    for i in range(8): d.polygon(rot([(C - 38, C - 200), (C + 38, C - 200), (C + 38, C - 110), (C - 38, C - 110)], 45 * i), fill=W)
    circle(d, 140); circle(d, 62, fill=CLEAR)
def scout(d):    # scout: fast arrowhead
    d.polygon([(C, 30), (410, 470), (C, 370), (102, 470)], fill=W)
def raider(d):   # raider: two chevrons
    for dy in (-70, 90): d.polygon([(40, C + 80 + dy), (C, C - 110 + dy), (472, C + 80 + dy), (472, C + 170 + dy), (C, C - 20 + dy), (40, C + 170 + dy)], fill=W)
def assault(d):  # assault: shield with a slash
    sh = lambda k: [(C - 190 * k, C - 200 * k), (C + 190 * k, C - 200 * k), (C + 190 * k, C + 40 * k), (C, C + 230 * k), (C - 190 * k, C + 40 * k)]
    d.polygon(sh(1), fill=W); d.polygon(sh(0.68), fill=CLEAR); d.polygon(sh(0.4), fill=W)
def art(d):      # artillery: crosshair
    ring(d, 165, 36)
    for a in range(4): d.polygon(rot([(C - 17, 12), (C + 17, 12), (C + 17, 150), (C - 17, 150)], 90 * a), fill=W)
    circle(d, 44)
def support(d):  # support: plus in a ring
    ring(d, 232, 24)
    d.rectangle([C - 48, C - 150, C + 48, C + 150], fill=W); d.rectangle([C - 150, C - 48, C + 150, C + 48], fill=W)
def heavy(d):    # heavy: nested hexagons
    d.polygon(ngon(6, 238, start=0), fill=W); d.polygon(ngon(6, 168, start=0), fill=CLEAR); d.polygon(ngon(6, 100, start=0), fill=W)
def fac(d):      # factory: sawtooth roof and chimney
    d.polygon([(40, 470), (40, 150), (190, 240), (190, 150), (340, 240), (340, 40), (470, 40), (470, 470)], fill=W)
    for x in (100, 215, 330): d.rectangle([x, 330, x + 80, 410], fill=CLEAR)
def mex(d):      # metal extractor: drill
    d.rectangle([50, 40, 462, 120], fill=W); d.polygon([(90, 150), (422, 150), (C, 480)], fill=W)
    d.polygon([(C - 90, 200), (C + 90, 200), (C, 330)], fill=CLEAR)
def solar(d):    # energy: sun
    circle(d, 118)
    for i in range(12): d.polygon(rot([(C - 22, 20), (C + 22, 20), (C + 22, 100), (C - 22, 100)], 30 * i), fill=W)
def heart(d):    # advanced energy: diamond with a bolt
    d.polygon([(C, 14), (498, C), (C, 498), (14, C)], fill=W)
    d.polygon([(300, 100), (160, 290), (240, 290), (205, 410), (352, 215), (272, 215)], fill=CLEAR)
def store(d):    # storage: cylinder
    d.ellipse([80, 40, 432, 170], fill=W); d.rectangle([80, 105, 432, 400], fill=W); d.ellipse([80, 340, 432, 470], fill=W)
    for y in (210, 300): d.rectangle([60, y, 452, y + 24], fill=CLEAR)
def radar(d):    # radar: dot with three arcs
    circle(d, 44, C, 400)
    for r in (115, 200, 285): d.arc([C - r, 400 - r, C + r, 400 + r], 215, 325, fill=W, width=38)
def def1(d):     # light defence: small tower
    d.polygon([(C, 30), (430, 300), (82, 300)], fill=W); d.rectangle([110, 335, 402, 450], fill=W); circle(d, 42, C, 215, CLEAR)
def def2(d):     # heavy defence: turret with a long barrel
    ring(d, 205, 52, C, 300); circle(d, 95, C, 300); d.rectangle([C - 40, 8, C + 40, 270], fill=W)

KINDS = {  # kind: (drawer, engine icon size)
    "com": (com, 1.5), "con": (con, 0.9), "scout": (scout, 0.7), "raider": (raider, 0.85), "assault": (assault, 1.0),
    "art": (art, 0.95), "support": (support, 0.9), "heavy": (heavy, 1.3), "fac": (fac, 1.3), "mex": (mex, 0.8),
    "solar": (solar, 0.9), "heart": (heart, 1.2), "store": (store, 1.0), "radar": (radar, 0.95), "def1": (def1, 0.9), "def2": (def2, 1.25),
}

def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, (fn, _) in KINDS.items():
        im = Image.new("RGBA", (S, S), CLEAR); fn(ImageDraw.Draw(im))
        im.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, f"vb_{kind}.png"))
    # the 'default' icon (units without a role, e.g. internal weapon carriers)
    im = Image.new("RGBA", (S, S), CLEAR); d = ImageDraw.Draw(im); circle(d, 150)
    im.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "vb_default.png"))
    lines = ["-- Generated by tools/gen_icons.py - do not edit by hand.",
             "-- One zoomed-out icon per unit ROLE (customParams.kind), shared by both factions; the engine tints it with the team colour.",
             "-- Units pick theirs with  iconType = \"vb_<kind>\"  (tools/gen_defs.py).", "local icontypes = {",
             "\tdefault = { bitmap = \"icons/vb_default.png\", size = 0.6, radiusadjust = false },"]
    for kind, (_, size) in KINDS.items():
        lines.append(f"\tvb_{kind} = {{ bitmap = \"icons/vb_{kind}.png\", size = {size}, radiusadjust = false }},")
    lines += ["}", "return icontypes", ""]
    open(os.path.join(ROOT, "game", "gamedata", "icontypes.lua"), "w").write("\n".join(lines))
    # contact sheet for a quick look
    sheet = Image.new("RGBA", (4 * 140, 4 * 140), (28, 30, 40, 255))
    for i, kind in enumerate(KINDS):
        sheet.alpha_composite(Image.open(os.path.join(OUT, f"vb_{kind}.png")), ((i % 4) * 140 + 6, (i // 4) * 140 + 6))
    os.makedirs(os.path.join(ROOT, "out"), exist_ok=True)
    sheet.save(os.path.join(ROOT, "out", "icons_sheet.png"))
    print(len(KINDS) + 1, "icons + gamedata/icontypes.lua written")

if __name__ == "__main__":
    main()
