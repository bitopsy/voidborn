#!/usr/bin/env python3
"""One-step installer + builder.
Run from the repo root (the folder that contains game/ and README.md):
    python3 install_and_build.py /path/to/voidborn_full_source.zip
It copies every file from the zip's game/ folder into ./game (overwriting), removes the stale
vb_fontconfig.lua, verifies the six patched files, and builds dist/voidborn.sdz."""
import hashlib, os, sys, zipfile

if len(sys.argv) < 2:
    sys.exit("usage: python3 install_and_build.py /path/to/voidborn_full_source.zip")
src = os.path.abspath(os.path.expanduser(sys.argv[1]))
repo = os.getcwd()
game = os.path.join(repo, "game")
print("repo root :", repo)
print("zip       :", src)
if not os.path.isfile(src):
    sys.exit(f"ERROR: zip not found at {src}")
if not os.path.isdir(game):
    sys.exit(f"ERROR: {game} does not exist - cd into the folder that contains game/ first")
if os.path.isdir(os.path.join(game, "game")):
    print("WARNING: found a nested game/game folder (a bad earlier unzip). It is ignored; you can delete it.")

z = zipfile.ZipFile(src)
names = z.namelist()
# 1. install every file under game/ from the zip
count = 0
for n in names:
    if not n.startswith("game/") or n.endswith("/"):
        continue
    dest = os.path.join(repo, *n.split("/"))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(z.read(n))
    count += 1
print(f"installed : {count} files into {game}")

# 2. remove stale file from the earlier patch
stale = os.path.join(game, "LuaUI", "Widgets", "vb_fontconfig.lua")
if os.path.exists(stale):
    os.remove(stale); print("removed   :", stale)

# 3. verify the six patched files against the manifest inside the zip
bad = 0
for line in z.read("MANIFEST.sha256").decode().splitlines():
    if not line.strip(): continue
    h, rel = line.split()
    p = os.path.join(game, *rel.split("/"))
    ok = os.path.isfile(p) and hashlib.sha256(open(p, "rb").read()).hexdigest() == h
    print(("ok      : " if ok else "BAD     : ") + rel)
    bad += not ok
if bad: sys.exit(f"\n{bad} file(s) wrong after install - something is blocking writes to {game}")
if not os.path.isfile(os.path.join(game, "modinfo.lua")):
    sys.exit("ERROR: game/modinfo.lua missing")

# 4. build: zip the CONTENTS of game/ (modinfo.lua at archive root), forward slashes
out = os.path.join(repo, "dist", "voidborn.sdz")
os.makedirs(os.path.dirname(out), exist_ok=True)
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zo:
    for root, dirs, files in os.walk(game):
        if os.path.abspath(root) == game and "game" in dirs: dirs.remove("game")  # skip bad nested folder
        dirs.sort()
        for f in sorted(files):
            if f in (".DS_Store", "Thumbs.db"): continue
            full = os.path.join(root, f)
            zo.write(full, os.path.relpath(full, game).replace(os.sep, "/")); n += 1
print(f"\nbuilt {out} ({n} files, {os.path.getsize(out)} bytes)")
print("copy it to your games/ folder as voidborn.sdz")
