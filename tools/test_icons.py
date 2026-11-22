#!/usr/bin/env python3
"""Checks the zoomed-out unit icons: every unit def points at an icon type that exists, the PNGs exist, a role has the SAME
icon in every faction, and different roles have different pictures.   pip install lupa pillow"""
import glob, hashlib, os, sys
import lupa
try:
    from lupa import lua51 as _L
except ImportError:
    _L = lupa
from PIL import Image

root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
game = os.path.join(root, "game")
rt = _L.LuaRuntime()
fails = 0
def check(n, ok, info=None):
    global fails
    print(("ok    " if ok else "FAIL  ") + n + (f"  ({info})" if info is not None else ""))
    if not ok: fails += 1

icontypes = rt.execute(open(os.path.join(game, "gamedata", "icontypes.lua")).read())
types = {k: dict(v.items()) for k, v in icontypes.items()}
check("icontypes.lua defines a 'default' icon", "default" in types)

missing, sizes, hashes = [], [], {}
for name, t in types.items():
    p = os.path.join(game, t["bitmap"])
    if not os.path.isfile(p): missing.append(t["bitmap"]); continue
    im = Image.open(p)
    if im.mode != "RGBA" or im.size != (128, 128): sizes.append(f"{t['bitmap']} {im.mode} {im.size}")
    if name != "default": hashes[name] = hashlib.sha256(im.tobytes()).hexdigest()
check("every icon type has its PNG", not missing, ", ".join(missing))
check("icons are 128x128 RGBA (white glyph, transparent background)", not sizes, ", ".join(sizes))
check("every role has its own picture", len(set(hashes.values())) == len(hashes), f"{len(hashes)} roles")

by_kind, bad = {}, []
for f in sorted(glob.glob(os.path.join(game, "units", "*.lua"))):
    defs = rt.execute(open(f, encoding="utf-8").read())
    for uname, d in defs.items():
        icon, cp = d["iconType"], d["customParams"]
        kind, fac = cp["kind"], cp["faction"]
        if kind in ("fac2", "raider2", "assault2", "art2", "support2", "heavy2", "fac3", "heavy3"): kind = kind[:-1]   # tier 2 and 3 share the role icon
        if icon not in types: bad.append(f"{uname}: unknown iconType '{icon}'")
        if kind == "combat": continue                       # internal weapon carriers
        if icon != "vb_" + kind: bad.append(f"{uname}: kind '{kind}' but iconType '{icon}'")
        by_kind.setdefault(kind, {})[fac] = icon
check("every unit def points at an existing icon type for its role", not bad, "; ".join(bad[:5]))
nfac = len({f for v in by_kind.values() for f in v})
shared = all(len(v) == nfac and len(set(v.values())) == 1 for v in by_kind.values())
check("each role has a unit in every faction and they share one icon", shared, f"{len(by_kind)} roles, {nfac} factions")
check("every role icon is used", set("vb_" + k for k in by_kind) == set(types) - {"default"})
print("\nALL PASSED" if fails == 0 else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
