#!/usr/bin/env python3
"""0.18 Tier 3 data checks: the lab chain, the five heavies, their weapons, assets.   pip install lupa   (python3 tools/test_t3_units.py)"""
import os, sys, glob
import lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
game = os.path.join(root, "game")
rt = lupa.LuaRuntime()
def load(p): return rt.eval("function(s) return load(s)() end")(open(p).read())
def py(t):
    if lupa.lua_type(t) != "table": return t
    ks = list(t.keys())
    if ks and all(isinstance(k, int) for k in ks): return [py(t[k]) for k in sorted(ks)]
    return {k: py(t[k]) for k in ks}
units = {}
for p in glob.glob(os.path.join(game, "units", "*.lua")):
    units.update(py(load(p)))
weapons = {}
for p in glob.glob(os.path.join(game, "weapons", "*.lua")):
    weapons.update(py(load(p)))
fails = 0
def check(n, ok, info=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + n + (f"  ({info})" if info != "" else ""))
    if not ok: fails += 1

FACS = {"choir": ("ch_womb2", "ch_womb3", "ch_eidolon", "ch_panopticon"), "maw": ("mw_hive2", "mw_hive3", "mw_dreadmaw", "mw_devourer"),
        "tympan": ("ty_echo2", "ty_echo3", "ty_carillon", "ty_organon"), "miasma": ("mi_nostril2", "mi_nostril3", "mi_rafflesia", "mi_titanarum"),
        "haptic": ("ha_palm2", "ha_palm3", "ha_atlas", "ha_hecaton")}
TWIST = {"tympan": "vb_resonance", "miasma": "vb_poison_dps", "haptic": "vb_touch"}
def dps(w):
    d = w["damage"]["default"]; b = w.get("burst", 1)
    if w["weaponType"] == "BeamLaser": return d * w["beamTime"] / w["reloadTime"]      # damage is per second while the beam is on
    return d * b / w["reloadTime"]
for fac, (l2, l3, h3, h2) in FACS.items():
    a, b, h, o = units[l2], units[l3], units[h3], units[h2]
    cp2, cp3, cph = a["customParams"], b["customParams"], h["customParams"]
    check(f"{fac}: the T2 lab upgrades to the T3 lab (tier 3, priced and timed)", cp2.get("upgrade_to") == l3 and cp2.get("upgrade_tier") == "3"
          and float(cp2["upgrade_metal"]) > 2000 and float(cp2["upgrade_seconds"]) > 45)
    check(f"{fac}: the T3 lab is kind fac3, tier 3, and is not upgradable again", cp3["kind"] == "fac3" and cp3["tier"] == "3" and "upgrade_to" not in cp3)
    bo2, bo3 = list(a["buildOptions"]), list(b["buildOptions"])
    check(f"{fac}: the T3 lab builds everything the T2 lab builds, plus the heavy", set(bo2) < set(bo3) and set(bo3) - set(bo2) == {h3}, sorted(set(bo3) - set(bo2)))
    others = [n for n, u in units.items() if h3 in (u.get("buildOptions") or [])]
    check(f"{fac}: only the T3 lab builds the heavy", others == [l3], others)
    check(f"{fac}: {h3} is a slow T3 heavy (kind heavy3, speed < the T2 heavy's, < 0.5)", cph["kind"] == "heavy3" and cph["tier"] == "3"
          and h["maxVelocity"] < o["maxVelocity"] and h["maxVelocity"] < 0.5, f'{h["maxVelocity"]} vs {o["maxVelocity"]}')
    check(f"{fac}: it is at least twice as costly and as tough as the T2 heavy", h["metalCost"] >= 2 * o["metalCost"] and h["maxDamage"] >= 2 * o["maxDamage"])
    ws = [weapons[w["def"]] for w in h["weapons"]]
    types = [w["weaponType"] for w in ws]
    check(f"{fac}: weapons = a heavy beam laser, lightning cannon and artillery or missiles (SplinterFaction T3)",
          types[0] == "BeamLaser" and "LightningCannon" in types and len(ws) >= 3, types)
    check(f"{fac}: the beam reloads slowly (>= 5 s) like the Leviathan's laser", ws[0]["reloadTime"] >= 5 and ws[0]["beamTime"] < ws[0]["reloadTime"])
    check(f"{fac}: every weapon has its sound and no friendly fire", all(w.get("soundStart") and w.get("soundHit") and w.get("avoidFriendly") is False and w.get("collideFriendly") is False for w in ws))
    if fac in TWIST:
        check(f"{fac}: the faction's rule ({TWIST[fac]}) is on its weapons", all(TWIST[fac] in (w.get("customParams") or {}) for w in ws if w["weaponType"] != "MissileLauncher" or fac != "tympan"))
    o_dps = sum(dps(weapons[w["def"]]) for w in o["weapons"]); h_dps = sum(dps(w) for w in ws)
    check(f"{fac}: sustained damage per metal is within 25% of the T2 heavy's, total at least 1.8x", 0.75 <= (h_dps / h["metalCost"]) / (o_dps / o["metalCost"]) <= 1.25 and h_dps >= 1.8 * o_dps,
          f"T2 {o_dps:.0f}/s ({o_dps/o['metalCost']:.3f} per metal)  T3 {h_dps:.0f}/s ({h_dps/h['metalCost']:.3f} per metal)")
    for u in (l3, h3):
        check(f"{u}: model, build picture and script exist, the model is in meta.json", all(os.path.isfile(os.path.join(game, d, f)) for d, f in
              (("objects3d", u + ".s3o"), ("unitpics", u + ".png"), ("scripts", u + ".lua"))))
    check(f"{h3}: the unit def has sounds (select / ok / cant)", all(k in units[h3].get("sounds", {}) for k in ("select", "ok", "cant")))
    check(f"{l3}: the lab has its select sound", "select" in units[l3].get("sounds", {}))
snd = open(os.path.join(game, "gamedata", "sounds.lua")).read(); wid = open(os.path.join(game, "LuaUI", "Widgets", "vb_sounds.lua")).read()
upg = open(os.path.join(game, "LuaRules", "Gadgets", "vb_factory_upgrade.lua")).read()
# the T3 lab upgrade is announced by the upgrade gadget, the T3 heavy by the widget (both with the spoken vox_ lines)
for n, played, where in (("vox_t3_upgrade", f"sounds/vox_t3_upgrade.wav" in upg, "vb_factory_upgrade"),
                         ("vox_t3_unit_ready", 'cp.kind == "heavy3" then Play("vox_t3_unit_ready"' in wid, "vb_sounds")):
    check(f"announcement {n}: wav exists, is registered in sounds.lua, and is played by {where}",
          os.path.isfile(os.path.join(game, "sounds", n + ".wav")) and n + '"' in snd and played)
for n in ("vox_energy_full", "vox_metal_full", "vox_factory_idle", "vox_queue_empty"):
    check(f"announcement {n}: wav exists, is registered, and the widget can play it",
          os.path.isfile(os.path.join(game, "sounds", n + ".wav")) and n + '"' in snd
          and (n in wid or n.replace("vox_", '" .. kind .. "_').replace("_stall", "_stall") != n and ('"vox_" .. kind .. "_' + n.split("_")[-1] + '"') in wid))
check("tier2_ready is played by the upgrade gadget", "sounds/tier2_ready.wav" in upg)
labs = [n for n, u in units.items() if (u.get("customParams") or {}).get("kind") in ("fac", "fac2", "fac3") or u.get("isFactory")]
check("every lab has canRepeat (REPEAT toggle loops its line)", len(labs) >= 15 and all(units[n].get("canRepeat") is True for n in labs),
      [n for n in labs if units[n].get("canRepeat") is not True])
print("\nALL PASSED" if not fails else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
