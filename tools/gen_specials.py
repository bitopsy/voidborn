#!/usr/bin/env python3
"""0.19: three new weapon behaviours, one per faction.   python3 tools/gen_specials.py     (idempotent)

  HAPTIC  - BRANCHING ARC.   A short-ranged lightning that never misses, bursts over a wide area and then BRANCHES: it jumps to the nearest
            enemies around the first target (gadget vb_arc.lua).  Range 0.7x of the laser it replaces, single-target damage 0.8x.
  TYMPAN  - SONAR PULSES.    Three rings (a burst of three small shells) that travel out like a sonar wave.  Same range, wider burst, 0.95x damage
            per second: the pulses land one after another, so they are worse against fast targets than one shell.
  MIASMA  - SINE WAVE.       A slow shell that snakes sideways in a sine wave (gadget vb_wave.lua).  Each shot hits 1.6x harder (and poisons 1.6x
            harder) but is fired 1.6x less often and flies about half as fast, so it is easy to sidestep: same damage per second on paper.

Every number is derived from the BASE table (the weapon as it was before this script), and tools/test_specials.py checks the result.
"""
import os, re, glob, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_fx_019 as fx

G = os.path.join(fx.ROOT, "game")

# the weapons as they were: range, damage per shot, burst, reload (s), area of effect, velocity, poison dps per hit
BASE = {
    "ha_prickle_w1":    dict(range=330, dmg=15,  burst=1, reload=0.45, aoe=8),
    "ha_gauntlet_w2":   dict(range=200, dmg=13,  burst=1, reload=0.3,  aoe=6),
    "ha_polydactyl_w2": dict(range=260, dmg=16,  burst=2, reload=0.4,  aoe=8),
    "ha_hecaton_w2":    dict(range=300, dmg=26,  burst=3, reload=0.4,  aoe=10),
    "ty_drummer_w1":    dict(range=360, dmg=42,  burst=1, reload=0.7,  aoe=40),
    "ty_malleus_w1":    dict(range=430, dmg=95,  burst=1, reload=0.8,  aoe=50),
    "ty_gong_w1":       dict(range=880, dmg=240, burst=1, reload=1.9,  aoe=80),
    "ty_cacophon_w1":   dict(range=600, dmg=300, burst=1, reload=1.3,  aoe=90),
    "mi_bellows_w1":    dict(range=340, dmg=44,  burst=1, reload=0.7,  aoe=30, vel=480),
    "mi_bloomguard_w1": dict(range=410, dmg=100, burst=1, reload=0.65, aoe=40, vel=480),
    "mi_stench_w1":     dict(range=860, dmg=190, burst=1, reload=2.2,  aoe=90, vel=330),
}
def dps(b): return b["dmg"] * b["burst"] / b["reload"]

# the new designs
ARC_RANGE, ARC_DPS, ARC_RELOAD = 0.70, 0.80, 0.6
ARC = {   # name: (display name, aoe, branches, sound, damage per second as a fraction of the old laser's)
    "ha_prickle_w1":    ("Thorn Arc", 36, 2, "vb_arc_zap", ARC_DPS),
    "ha_gauntlet_w2":   ("Branching Grasp", 40, 2, "vb_arc_zap", ARC_DPS),
    "ha_polydactyl_w2": ("Finger Lightning", 48, 3, "vb_arc_heavy", ARC_DPS),
    # the T2 heavy's damage per metal has to stay within 25% of the T3's (tools/test_t3_units.py), so its arc keeps more of the old damage
    # and branches to two enemies, not three
    "ha_hecaton_w2":    ("Many-Handed Storm", 60, 2, "vb_arc_heavy", 0.95),
}
ARC_BRANCH_PCT, ARC_BRANCH_RANGE = 0.35, 90

SONAR_RELOAD, SONAR_DPS, SONAR_AOE, SONAR_BURST, SONAR_RATE = 1.5, 0.95, 1.15, 3, 0.14
SONAR = {  # name: (display name, sound)
    "ty_drummer_w1":  ("Sonar Pulse", "vb_sonar_ping"),
    "ty_malleus_w1":  ("Resonant Ring", "vb_sonar_ping"),
    "ty_gong_w1":     ("Deep Ping", "vb_sonar_deep"),
    "ty_cacophon_w1": ("Echo Salvo", "vb_sonar_deep"),
}

WAVE_RELOAD, WAVE_DMG, WAVE_AOE = 1.6, 1.6, 1.2
WAVE = {   # name: (display name, amplitude, wavelength, sound, gravity, speed as a fraction of the old shell's)
    # a ballistic shell can only reach range <= v^2/g (v per frame), so the long-range Slow Tide cannot be quite as slow
    "mi_bellows_w1":    ("Drift Wave", 20, 90, "vb_warble_light", 0.05, 0.55),
    "mi_bloomguard_w1": ("Undulating Bloom", 22, 100, "vb_warble_heavy", 0.05, 0.55),
    "mi_stench_w1":     ("Slow Tide", 30, 130, "vb_warble_heavy", 0.04, 0.59),
}

# ------------------------------------------------------------------------------------------------------------------------
def getcp(block):
    """customParams of a weapon block as a dict (and the line span it occupies)"""
    for i, l in enumerate(block):
        if fx.active(l) and re.match(r'\s*customParams\s*=\s*\{', l):
            j = i
            while not re.match(r'\s*\},?\s*$', block[j]): j += 1
            d = {}
            for k in range(i + 1, j):
                m = re.match(r'\s*(\w+)\s*=\s*"([^"]*)"', block[k])
                if m: d[m.group(1)] = m.group(2)
            return d, i, j
    return {}, None, None

def setcp(block, updates, drop=()):
    d, i, j = getcp(block)
    d.update(updates)
    for k in drop: d.pop(k, None)
    new = ["\t\tcustomParams = {"] + [f'\t\t\t{k} = "{v}",' for k, v in d.items()] + ["\t\t},"]
    if i is None:
        at = next(n for n, l in enumerate(block) if fx.active(l) and re.match(r'\s*weaponType\s*=', l)) + 1
        block[at:at] = new
    else:
        block[i:j + 1] = new

def drop(block, *keys):
    return [l for l in block if not (fx.active(l) and re.match(r'\s*(' + "|".join(keys) + r')\s*=', l))]

def setdmg(block, v):
    for i in range(len(block) - 1, -1, -1):
        if fx.active(block[i]) and re.search(r'default\s*=', block[i]):
            block[i] = re.sub(r'default\s*=\s*[\d.]+', "default = " + fx.fnum(v), block[i]); return
    raise SystemExit("no damage line")

def faction(name): return {"ha": "haptic", "ty": "tympan", "mi": "miasma"}[name[:2]]

# ---- haptic: branching arc -------------------------------------------------------------------------------------------
def make_arc(name, block):
    if fx.getv(block, "weaponType") == "LightningCannon": return block
    disp, aoe, nb, snd, df = ARC[name]; b = BASE[name]
    dmg = round(dps(b) * df * ARC_RELOAD, 2)
    block = drop(block, "weaponVelocity", "duration", "burst", "burstRate", "sprayAngle", "cegTag", "size", "texture1", "texture2", "texture3", "texture4",
                 "coreThickness", "laserFlareSize", "thickness", "intensity", "areaOfEffect", "reloadTime", "range", "name", "edgeEffectiveness")
    setdmg(block, dmg)
    for k, v in (("weaponType", '"LightningCannon"'), ("name", f'"{disp}"'), ("range", str(round(b["range"] * ARC_RANGE))), ("reloadTime", fx.fnum(ARC_RELOAD)),
                 ("areaOfEffect", str(aoe)), ("edgeEffectiveness", "0.45"), ("thickness", "2.4"), ("beamTTL", "10"), ("duration", "1.0"),
                 ("texture1", '"lightning"'), ("intensity", "24"), ("laserFlareSize", "1"), ("sprayAngle", "0"), ("rgbColor", '"1 0.6 0.75"'),
                 ("explosionGenerator", '"custom:vb_haptic_arc"'), ("impulseBoost", "0"), ("noSelfDamage", "true"),
                 ("soundStart", f'"{snd}"'), ("soundStartVolume", "0.9"), ("soundHit", '"vb_hit_touch"'), ("soundHitVolume", "0.7")):
        fx.setv(block, k, v)
    setcp(block, {"vb_touch": "1", "vb_branch": str(nb), "vb_branch_pct": fx.fnum(ARC_BRANCH_PCT), "vb_branch_range": str(ARC_BRANCH_RANGE)})
    return block

# ---- tympan: sonar pulses --------------------------------------------------------------------------------------------
def make_sonar(name, block):
    if str(fx.getv(block, "cegTag") or "").startswith("vb_tympan_sonar"): return block
    disp, snd = SONAR[name]; b = BASE[name]
    reload_ = round(b["reload"] * SONAR_RELOAD, 2)
    dmg = round(dps(b) * SONAR_DPS * reload_ / SONAR_BURST, 2)
    block = drop(block, "burst", "burstRate", "name", "size", "stages", "separation", "noGap", "sprayAngle")
    setdmg(block, dmg)
    for k, v in (("name", f'"{disp}"'), ("reloadTime", fx.fnum(reload_)), ("burst", str(SONAR_BURST)), ("burstRate", fx.fnum(SONAR_RATE)),
                 ("areaOfEffect", str(round(b["aoe"] * SONAR_AOE))), ("sprayAngle", "30"), ("size", "2.5"), ("stages", "1"),
                 ("cegTag", '"vb_tympan_sonar"'), ("explosionGenerator", '"custom:vb_tympan_sonar_hit"'),
                 ("soundStart", f'"{snd}"'), ("soundStartVolume", "0.9"), ("soundHit", '"vb_hit_sonic"'), ("soundHitVolume", "0.8")):
        fx.setv(block, k, v)
    setcp(block, {"vb_resonance": "1"})
    return block

# ---- miasma: sine wave -----------------------------------------------------------------------------------------------
def make_wave(name, block):
    if "vb_wave_amp" in getcp(block)[0]: return block
    disp, amp, wl, snd, grav, vf = WAVE[name]; b = BASE[name]
    reload_ = round(b["reload"] * WAVE_RELOAD, 2)
    dmg = round(b["dmg"] * WAVE_DMG, 2)
    cp, _, _ = getcp(block)
    poison = float(cp.get("vb_poison_dps", "0")) * WAVE_DMG
    block = drop(block, "name", "myGravity")
    setdmg(block, dmg)
    for k, v in (("name", f'"{disp}"'), ("reloadTime", fx.fnum(reload_)), ("areaOfEffect", str(round(b["aoe"] * WAVE_AOE))),
                 ("weaponVelocity", str(round(b["vel"] * vf))), ("myGravity", fx.fnum(grav)), ("sprayAngle", "40"),   # the wave is the spread
                 ("cegTag", '"vb_miasma_wave"'), ("explosionGenerator", '"custom:vb_miasma_wave_hit"'),
                 ("soundStart", f'"{snd}"'), ("soundStartVolume", "0.9"), ("soundHit", '"vb_hit_gas"'), ("soundHitVolume", "0.8")):
        fx.setv(block, k, v)
    upd = {"vb_wave_amp": str(amp), "vb_wave_len": str(wl)}
    if poison: upd["vb_poison_dps"] = fx.fnum(round(poison, 2))
    setcp(block, upd)
    return block

def patch_file(path):
    lines = open(path).read().split("\n")
    starts = [k for k, l in enumerate(lines) if re.match(r'^\t(\w+) = \{', l)]
    starts.append(len(lines) - 1)
    out = lines[:starts[0]]; n = 0
    for a, b in zip(starts, starts[1:]):
        name = re.match(r'^\t(\w+) = \{', lines[a]).group(1)
        blk = lines[a + 1:b]
        for table, fn in ((ARC, make_arc), (SONAR, make_sonar), (WAVE, make_wave)):
            if name in table:
                new = fn(name, blk); n += new != blk; blk = new
        out.append(lines[a]); out.extend(blk)
    out.extend(lines[starts[-1]:])
    open(path, "w").write("\n".join(out))
    return n

if __name__ == "__main__":
    total = sum(patch_file(p) for p in sorted(glob.glob(os.path.join(G, "weapons", "vb_weapons*.lua"))))
    print("rewrote %d weapons" % total)
