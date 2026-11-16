#!/usr/bin/env python3
"""Wires the generated sound items into the generated unit/weapon defs. Idempotent: safe to rerun.
   python3 tools/add_sounds.py          (run from the repo root)
tools/gen_defs.py is NOT patched: if you regenerate defs with it, rerun this script afterwards."""
import os, re, glob

G = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")

def items(*names): return "{ " + ", ".join('"vb_%s"' % n for n in names) + " }"

# ----------------------------------------------------------------------------- units
def unit_sounds(fac, kind):
    f = "choir" if fac == "choir" else "maw"
    if kind in ("fac2", "raider2", "assault2", "art2", "support2", "heavy2"): kind = kind[:-1]      # tier 2 units sound like their tier 1 role
    s = {}
    if kind in ("com", "con", "scout", "raider", "assault", "art", "support", "heavy"):
        s["select"] = items("select_" + f); s["ok"] = items("ok_" + f); s["cant"] = items("ui_error")
        if kind in ("com", "con", "support"): s["build"] = items("nano_zap")
        if kind == "com": s["underattack"] = items("alarm_commander")
    else:
        s["select"] = items("select_struct_" + f); s["cant"] = items("ui_error")
        if kind == "fac": s["build"] = items("nano_zap")
        if kind == "mex": s["activate"] = items("mex_on"); s["deactivate"] = items("power_off")
        if kind in ("solar", "heart"): s["activate"] = items("power_on"); s["deactivate"] = items("power_off")
        if kind == "radar": s["activate"] = items("radar_ping"); s["deactivate"] = items("power_off")
    return s

n_units = 0
for p in sorted(glob.glob(os.path.join(G, "units", "*.lua"))):
    t = open(p).read()
    if "\t\tsounds = {" in t: continue
    fac = re.search(r'faction = "(\w+)"', t); kind = re.search(r'kind = "(\w+)"', t)
    if not (fac and kind): continue
    body = "\t\tsounds = {\n" + "".join("\t\t\t%s = %s,\n" % kv for kv in unit_sounds(fac.group(1), kind.group(1)).items()) + "\t\t},\n"
    t2 = t.replace('\t\tcorpse = "",\n', '\t\tcorpse = "",\n' + body, 1)
    if t2 != t: open(p, "w").write(t2); n_units += 1

# ----------------------------------------------------------------------------- weapons
def weapon_sounds(wtype, gen, dmg):
    choir = "choir" in gen
    if wtype == "LaserCannon":
        if choir: start = "laser_choir_heavy" if dmg >= 90 else "laser_choir_light" if dmg < 20 else "laser_choir"
        else:     start = "acid_heavy" if dmg >= 300 else "acid_light" if dmg < 20 else "acid_spit"
        return start, ("hit_laser" if choir else "hit_acid"), 0.8
    if wtype == "MissileLauncher": return "spore_launch", "hit_acid", 0.8
    if wtype == "Flame":           return "flame_breath", None, 0.6
    if wtype == "DGun":            return "dgun_blast", "boom_med", 1.0
    return None, None, 0

wp = os.path.join(G, "weapons", "vb_weapons.lua")
txt = open(wp).read()
n_w = 0
def patch(m):
    global n_w
    key, body = m.group(1), m.group(2)
    if "soundStart" in body or "soundHit" in body: return m.group(0)
    if key in ("vb_small", "vb_med", "vb_big"):
        n_w += 1
        return "\n\t%s = {%s\n\t\tsoundHit = \"vb_boom_%s\",\n\t\tsoundHitVolume = 1.0,\n\t}," % (key, body.rstrip("\n"), key.split("_")[1])
    wt = re.search(r'weaponType = "(\w+)"', body); gen = re.search(r'explosionGenerator = "([^"]*)"', body)
    dm = re.search(r'default = ([\d\.]+)', body)
    start, hit, vol = weapon_sounds(wt.group(1) if wt else "", gen.group(1) if gen else "", float(dm.group(1)) if dm else 0)
    if not start: return m.group(0)
    add = '\n\t\tsoundStart = "vb_%s",\n\t\tsoundStartVolume = %s,\n' % (start, vol)
    if hit: add += '\t\tsoundHit = "vb_%s",\n\t\tsoundHitVolume = 0.8,\n' % hit
    n_w += 1
    return "\n\t%s = {%s%s\n\t}," % (key, body.rstrip("\n"), add.rstrip("\n"))
txt2 = re.sub(r'\n\t(\w+) = \{(.*?)\n\t\},', patch, txt, flags=re.S)
if txt2 != txt: open(wp, "w").write(txt2)
print("units patched: %d, weapons patched: %d" % (n_units, n_w))
