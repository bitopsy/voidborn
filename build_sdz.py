#!/usr/bin/env python3
"""Build dist/voidborn.sdz from the game/ folder.

Usage (run from the repo root, the folder that CONTAINS game/):
    python3 build_sdz.py            # builds ./dist/voidborn.sdz
    python3 build_sdz.py /path/repo # or point at another checkout

An .sdz is just a zip whose ROOT holds modinfo.lua, so the CONTENTS of game/ are zipped, not the folder itself.
Every Lua file is syntax-checked first when the optional 'lupa' package is installed (pip install lupa).
Copy the result to your games/ folder as voidborn.sdz.
"""
import os, sys, zipfile

repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
game = os.path.join(repo, "game")
if not os.path.isfile(os.path.join(game, "modinfo.lua")):
    sys.exit(f"ERROR: {game}/modinfo.lua not found - run this from the folder that contains game/")

# stale file from an old patch: it rewrites FontFile in the global config
stale = os.path.join(game, "LuaUI", "Widgets", "vb_fontconfig.lua")
if os.path.exists(stale):
    os.remove(stale); print("removed stale", stale)

# optional Lua syntax check
try:
    import lupa
    rt = lupa.lua51.LuaRuntime() if hasattr(lupa, "lua51") else lupa.LuaRuntime()
    check = rt.eval("function(s, n) local f, e = (loadstring or load)(s, n) return e end")
    bad = 0
    for root, _, files in os.walk(game):
        for f in files:
            if f.endswith(".lua"):
                p = os.path.join(root, f)
                err = check(open(p, encoding="utf-8", errors="replace").read(), os.path.relpath(p, game))
                if err: print("SYNTAX ERROR:", err); bad += 1
    if bad: sys.exit(f"{bad} Lua file(s) have syntax errors - not building")
    print("lua syntax: all files OK")
except ImportError:
    print("(lupa not installed - skipping the Lua syntax check)")

out = os.path.join(repo, "dist", "voidborn.sdz")
os.makedirs(os.path.dirname(out), exist_ok=True)
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(game):
        dirs.sort()
        for f in sorted(files):
            if f in (".DS_Store", "Thumbs.db"): continue
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, game).replace(os.sep, "/")); n += 1
print(f"built {out}: {n} files, {os.path.getsize(out)} bytes")
