#!/usr/bin/env python3
"""Regenerates the Haptic Grasp defs without touching the older factions' files.
   gen_defs.py rewrites the Tympan and Miasma unit files too, and the committed ones carry `script = "<id>.lua"` lines that
   it does not write; so: run gen_defs, put the older files back, patch the script lines into the ha_ files, add the sounds.
   python3 tools/regen_017.py     (from the repo root; needs out/meta.json: python3 tools/gen_assets.py tympan miasma haptic)"""
import glob, os, re, shutil, subprocess, sys
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
U = os.path.join(root, "game", "units"); keep = {}
for f in glob.glob(os.path.join(U, "ty_*.lua")) + glob.glob(os.path.join(U, "mi_*.lua")): keep[f] = open(f, encoding="utf-8").read()
subprocess.check_call([sys.executable, os.path.join(root, "tools", "gen_defs.py")], cwd=root)
for f, t in keep.items(): open(f, "w", encoding="utf-8").write(t)
for p in glob.glob(os.path.join(U, "ha_*.lua")):
    i = os.path.basename(p)[:-4]; t = open(p, encoding="utf-8").read()
    t = re.sub(r'(\n\t\tname = "[^"\n]*",)', r'\1\n\tscript = "%s.lua",' % i, t, count=1)
    t = re.sub(r'(\n\t\t\t\tname = "%s_w\d",)' % i, r'\1\n\tscript = "%s.lua",' % i, t)
    open(p, "w", encoding="utf-8").write(t)
subprocess.check_call([sys.executable, os.path.join(root, "tools", "add_sounds.py")], cwd=root)
