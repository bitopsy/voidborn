#!/usr/bin/env python3
"""Build voidborn.sdz from a repo checkout.  Usage:  python3 build_sdz.py [path/to/repo]   (default: current dir)
Run it in the folder that CONTAINS game/ (the one with README.md). Output: dist/voidborn.sdz (map archive untouched)."""
import hashlib, os, sys, zipfile

repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
game = os.path.join(repo, "game")
if not os.path.isfile(os.path.join(game, "modinfo.lua")):
    sys.exit(f"ERROR: {game}/modinfo.lua not found - run this from the repo root (the folder containing game/)")

# 1. stale file from my earlier patch: it rewrites FontFile in your global config, remove it
stale = os.path.join(game, "LuaUI", "Widgets", "vb_fontconfig.lua")
if os.path.exists(stale):
    os.remove(stale); print("removed stale", stale)

# 2. check the six patched files against the known-good hashes
manifest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "MANIFEST.sha256")
bad = 0
for line in open(manifest):
    h, rel = line.split()
    p = os.path.join(game, rel)
    if not os.path.isfile(p):
        print("MISSING :", rel); bad += 1
    elif hashlib.sha256(open(p, "rb").read()).hexdigest() != h:
        print("DIFFERS :", rel, "(your copy is not the patched version)"); bad += 1
    else:
        print("ok      :", rel)
if bad: sys.exit(f"\n{bad} file(s) wrong - copy them from voidborn_changed_files.zip over game/ and rerun")

# 3. zip the CONTENTS of game/ (modinfo.lua must sit at the archive root), forward slashes, no junk
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
print(f"\nbuilt {out}: {n} files")
