#!/usr/bin/env python3
"""0.19 weapon graphics pass.
1. writes game/effects/vb_effects_019.lua: richer impact bursts (flash, glow, shockwave ring, sparks) and
   projectile trails (cegTag) for the five factions
2. updates game/weapons/*.lua: projectiles use the new trails / impacts, lasers and plasma are thicker and brighter
Idempotent: run it again and nothing changes.   python3 tools/gen_fx_019.py
"""
import re, os, glob
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
G = os.path.join(ROOT, "game")

# core colour, accent colour (r g b)
FACTIONS = {
    "choir":  ("0.6 0.9 1",   "0.5 0.3 1"),
    "maw":    ("0.75 1 0.25", "0.3 0.85 0.1"),
    "tympan": ("1 0.85 0.4",  "0.8 0.45 1"),
    "miasma": ("0.85 0.45 1", "0.9 0.9 0.3"),
    "haptic": ("1 0.65 0.55", "1 0.3 0.45"),
}

def psys(name, cm, tex, n, life, lifes, size, sizes, growth, speed, speeds, drag="0.92", grav="0, 0, 0",
         directional=False, rot=180, rots=0, pos="0, 2, 0", vec="0, 1, 0"):
    return f'''\t\t{name} = {{ air = true, class = "CSimpleParticleSystem", count = 1, ground = true, water = true, properties = {{
\t\t\tairdrag = {drag},
\t\t\tcolormap = "{cm}",
\t\t\tdirectional = {str(directional).lower()},
\t\t\temitrot = {rot},
\t\t\temitrotspread = {rots},
\t\t\temitvector = "{vec}",
\t\t\tgravity = "{grav}",
\t\t\tnumparticles = {n},
\t\t\tparticlelife = {life},
\t\t\tparticlelifespread = {lifes},
\t\t\tparticlesize = {size},
\t\t\tparticlesizespread = {sizes},
\t\t\tparticlespeed = {speed},
\t\t\tparticlespeedspread = {speeds},
\t\t\tpos = "{pos}",
\t\t\tsizegrowth = {growth},
\t\t\tsizemod = 1.0,
\t\t\ttexture = "{tex}",
\t\t\talwaysvisible = false,
\t\t}}, }},
'''

def flash(cm, size, ttl):
    return f'''\t\tflash = {{ air = true, class = "CSimpleGroundFlash", count = 1, ground = true, water = true, properties = {{
\t\t\tcolormap = "{cm}",
\t\t\tsize = {size},
\t\t\tsizegrowth = -0.04,
\t\t\tttl = {ttl},
\t\t\ttexture = "groundflash",
\t\t}}, }},
'''

def impact(core, acc, k):
    """k = scale: 1 for a normal hit, 2 for a heavy one"""
    c, a = core, acc
    hot = f"1 1 1 0.95  {c} 0.9  {a} 0.45  0 0 0 0"          # white-hot centre fading to the faction colours
    glow = f"{c} 0.85  {a} 0.4  0 0 0 0"
    s = ['\tusedefaultexplosions = false,\n'.replace('\t', '\t', 1)]
    s.append(flash(f"{c} 0.95  {a} 0.35  0 0 0 0", round(30 * k, 1), 22 if k == 1 else 30))
    s.append(psys("core", hot, "circularthingy", 3 if k == 1 else 5, 9, 4, round(13 * k, 1), round(4 * k, 1), 2.2, 0, 0.5))
    s.append(psys("glow", glow, "flare", 2 if k == 1 else 3, 16, 6, round(22 * k, 1), round(6 * k, 1), 0.6, 0, 0.3))
    s.append(psys("ring", f"{c} 0.7  {a} 0.3  0 0 0 0", "circularthingy", 1, 14, 2, round(5 * k, 1), 0, round(4.2 * k, 1), 0, 0, drag="1.0"))
    s.append(psys("sparks", f"1 1 1 0.9  {c} 0.8  {a} 0.35  0 0 0 0", "flare", 9 if k == 1 else 18, 16, 8, round(3.4 * k, 1), round(1.4 * k, 1), -0.05,
                  round(3.2 * k, 1), round(2.2 * k, 1), drag="0.9", grav="0, -0.12, 0", directional=True, rot=50, rots=40))
    return "".join(s)

def trail(core, acc, k):
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(psys("head", f"1 1 1 0.8  {c} 0.7  {a} 0.2  0 0 0 0", "flare", 1, 7, 2, round(7 * k, 1), round(1.5 * k, 1), -0.35 * k, 0, 0,
                  drag="1.0", pos="0, 0, 0", vec="0, 0, 0"))
    s.append(psys("wake", f"{c} 0.45  {a} 0.2  0 0 0 0", "circularthingy", 1, 14, 4, round(4 * k, 1), round(1.2 * k, 1), 0.15 * k, 0.15, 0.2,
                  drag="0.95", pos="0, 0, 0", vec="0, 0, 0"))
    return "".join(s)

def beamhit(core, acc):
    """a beam fires its hit effect EVERY frame, so this one is deliberately light: a small flash, a glow and two sparks"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(flash(f"{c} 0.8  {a} 0.3  0 0 0 0", 16, 5))
    s.append(psys("glow", f"1 1 1 0.7  {c} 0.6  {a} 0.2  0 0 0 0", "flare", 1, 5, 2, 9, 2, 0.4, 0, 0.2))
    s.append(psys("sparks", f"1 1 1 0.8  {c} 0.6  0 0 0 0", "flare", 2, 8, 4, 2.2, 0.8, -0.1, 2.4, 1.6, drag="0.9", grav="0, -0.1, 0",
                  directional=True, rot=60, rots=30))
    return "".join(s)

# ---- the three faction specials (tools/gen_specials.py) ---------------------------------------------------------------
def arc_hit(core, acc):
    """HAPTIC branching arc: a wide impact: a big flash, a fast shockwave ring and sparks thrown out in every direction"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(flash(f"1 1 1 0.9  {c} 0.8  {a} 0.3  0 0 0 0", 76, 26))
    s.append(psys("core", f"1 1 1 0.95  {c} 0.9  {a} 0.4  0 0 0 0", "circularthingy", 3, 8, 3, 18, 5, 2.4, 0, 0.4))
    s.append(psys("ring", f"{c} 0.8  {a} 0.35  0 0 0 0", "circularthingy", 1, 15, 2, 8, 0, 6.0, 0, 0, drag="1.0"))
    s.append(psys("ring2", f"{a} 0.6  0 0 0 0", "circularthingy", 1, 20, 2, 6, 0, 3.4, 0, 0, drag="1.0"))
    s.append(psys("sparks", f"1 1 1 0.95  {c} 0.85  {a} 0.4  0 0 0 0", "flare", 16, 14, 8, 3.4, 1.2, -0.08, 4.2, 2.6, drag="0.9",
                  grav="0, -0.1, 0", directional=True, rot=90, rots=70))
    return "".join(s)

def arc_spark(core, acc):
    """one segment of an arc branch (spawned by vb_arc.lua along the line to a second target)"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(psys("glow", f"1 1 1 0.9  {c} 0.7  {a} 0.2  0 0 0 0", "flare", 1, 7, 2, 9, 3, -0.3, 0, 0, drag="1.0", pos="0, 0, 0", vec="0, 0, 0"))
    s.append(psys("sparks", f"1 1 1 0.9  {c} 0.7  0 0 0 0", "flare", 3, 9, 4, 2.4, 0.8, -0.1, 1.4, 1.0, drag="0.9", grav="0, 0, 0",
                  directional=True, rot=180, rots=180))
    return "".join(s)

def sonar_trail(core, acc):
    """TYMPAN sonar pulse: one expanding ring per frame along the flight path (the shell itself is almost invisible)"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(psys("ring", f"1 1 1 0.55  {c} 0.5  {a} 0.2  0 0 0 0", "circularthingy", 1, 16, 2, 4, 0.5, 3.6, 0, 0, drag="1.0", pos="0, 0, 0", vec="0, 0, 0"))
    s.append(psys("core", f"{c} 0.45  0 0 0 0", "flare", 1, 6, 1, 5, 1, -0.5, 0, 0, drag="1.0", pos="0, 0, 0", vec="0, 0, 0"))
    return "".join(s)

def sonar_hit(core, acc):
    """three rings leaving the impact one inside the other, at different speeds"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(flash(f"{c} 0.7  {a} 0.3  0 0 0 0", 44, 20))
    for i, (sz, gr, life) in enumerate(((5, 5.2, 15), (4, 3.4, 20), (3, 2.1, 26))):
        s.append(psys(f"ring{i}", f"{c} {0.8 - 0.15 * i:.2f}  {a} {0.35 - 0.07 * i:.2f}  0 0 0 0", "circularthingy", 1, life, 2, sz, 0, gr, 0, 0, drag="1.0", pos="0, 3, 0"))
    s.append(psys("core", f"1 1 1 0.8  {c} 0.6  0 0 0 0", "flare", 1, 9, 2, 14, 3, 1.2, 0, 0))
    return "".join(s)

def wave_trail(core, acc):
    """MIASMA sine wave: glowing beads that hang in the air and drift apart, so the snaking path stays visible"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(psys("bead", f"1 1 1 0.7  {c} 0.65  {a} 0.3  0 0 0 0", "flare", 1, 20, 4, 7, 2, -0.18, 0.1, 0.15, drag="0.95", pos="0, 0, 0", vec="0, 1, 0"))
    s.append(psys("halo", f"{a} 0.4  0 0 0 0", "circularthingy", 1, 22, 4, 3, 1, 0.5, 0.05, 0.1, drag="0.95", pos="0, 0, 0", vec="0, 1, 0"))
    return "".join(s)

def wave_hit(core, acc):
    """a bloom that lingers"""
    c, a = core, acc
    s = ['\tusedefaultexplosions = false,\n']
    s.append(flash(f"{c} 0.8  {a} 0.35  0 0 0 0", 60, 30))
    s.append(psys("bloom", f"{c} 0.6  {a} 0.4  {a} 0.2  0 0 0 0", "circularthingy", 6, 46, 14, 12, 5, 1.1, 0.6, 0.5, drag="0.94", grav="0, 0.02, 0",
                  directional=False, rot=180, rots=180))
    s.append(psys("ring", f"{c} 0.7  {a} 0.3  0 0 0 0", "circularthingy", 1, 18, 2, 6, 0, 4.4, 0, 0, drag="1.0"))
    s.append(psys("spores", f"1 1 1 0.9  {c} 0.7  {a} 0.3  0 0 0 0", "flare", 9, 30, 12, 3, 1.2, -0.05, 1.8, 1.4, drag="0.93", grav="0, 0.03, 0",
                  directional=True, rot=70, rots=60))
    return "".join(s)

def build_effects():
    out = ["-- Voidborn 0.19 weapon graphics: impact bursts and projectile trails for the five factions\n-- (generated by tools/gen_fx_019.py)\nreturn {\n"]
    for f, (c, a) in FACTIONS.items():
        for suffix, body in (("impact", impact(c, a, 1)), ("impact_big", impact(c, a, 2)),
                             ("trail", trail(c, a, 1)), ("trail_big", trail(c, a, 1.8)), ("beamhit", beamhit(c, a))):
            out.append(f'\t["vb_{f}_{suffix}"] = {{\n{body}\t}},\n')
    for f, make in (("haptic", (("arc", arc_hit), ("arcspark", arc_spark))), ("tympan", (("sonar", sonar_trail), ("sonar_hit", sonar_hit))),
                    ("miasma", (("wave", wave_trail), ("wave_hit", wave_hit)))):
        c, a = FACTIONS[f]
        for suffix, fn in make:
            out.append(f'\t["vb_{f}_{suffix}"] = {{\n{fn(c, a)}\t}},\n')
    out.append("}\n")
    return "".join(out)

# ---------------------------------------------------------------------------------------------
def active(line): return not line.strip().startswith("--")

def getv(block, key):
    for l in reversed(block):          # a hand-edited block can set a key twice: the LAST one is what Lua uses
        if active(l):
            m = re.match(r'\s*' + key + r'\s*=\s*([^,\n]+)', l)
            if m: return m.group(1).strip().strip('"')
    return None

def setv(block, key, val, after="weaponType"):
    """set an active `key = val,` line (replace it, or add it after the weaponType line)"""
    for i in range(len(block) - 1, -1, -1):
        l = block[i]
        if active(l) and re.match(r'\s*' + key + r'\s*=', l):
            ind = re.match(r'\s*', l).group(0)
            block[i] = f"{ind}{key} = {val},"
            return
    for i, l in enumerate(block):
        if active(l) and re.match(r'\s*' + after + r'\s*=', l):
            ind = re.match(r'\s*', l).group(0)
            block.insert(i + 1, f"{ind}{key} = {val},")
            return

def fnum(x): return ("%.2f" % x).rstrip("0").rstrip(".")

def scale(block, key, mul, lo=None):
    v = getv(block, key)
    if v is None: return
    try: x = float(v)
    except ValueError: return
    done = getattr(scale, "_done", None)
    setv(block, key, fnum(max(x * mul, lo or 0)), after=key)

def patch_weapon(name, block):
    wt = getv(block, "weaponType")
    eg = getv(block, "explosionGenerator") or ""
    m = re.match(r'custom:vb_(\w+?)_(?:hit|impact|impact_big|beamhit)$', eg)
    if not m or m.group(1) not in FACTIONS or wt in ("Flame", "DGun"): return block
    if wt == "BeamLaser":                     # fires its hit effect every frame: keep it light
        f = m.group(1)
        setv(block, "explosionGenerator", f'"custom:vb_{f}_beamhit"')
        return block
    f = m.group(1)
    size = float(getv(block, "size") or 0)
    big = size >= 9 or wt in ("BeamLaser", "LightningCannon")
    already = (getv(block, "cegTag") or "").startswith("vb_") or "_impact" in eg      # patched by an earlier run
    setv(block, "explosionGenerator", f'"custom:vb_{f}_impact{"_big" if big else ""}"')
    if wt in ("Cannon", "MissileLauncher", "LaserCannon"):
        setv(block, "cegTag", f'"vb_{f}_trail{"_big" if size >= 12 else ""}"')
    if already: return block
    if wt == "LaserCannon":
        scale(block, "thickness", 1.3, 2.0); scale(block, "coreThickness", 1.3); scale(block, "laserFlareSize", 1.4)
    elif wt == "Cannon":
        scale(block, "size", 1.2)
    elif wt == "BeamLaser":
        scale(block, "laserFlareSize", 1.3)
    return block

def patch_file(path):
    lines = open(path).read().split("\n")
    out, i = [], 0
    starts = [k for k, l in enumerate(lines) if re.match(r'^\t(\w+) = \{', l)]
    starts.append(len(lines) - 1)
    out.extend(lines[:starts[0]])
    for a, b in zip(starts, starts[1:]):
        name = re.match(r'^\t(\w+) = \{', lines[a]).group(1)
        blk = patch_weapon(name, lines[a + 1:b])
        out.append(lines[a]); out.extend(blk)
    out.extend(lines[starts[-1]:])
    open(path, "w").write("\n".join(out))

if __name__ == "__main__":
    open(os.path.join(G, "effects", "vb_effects_019.lua"), "w").write(build_effects())
    for p in sorted(glob.glob(os.path.join(G, "weapons", "vb_weapons*.lua"))):
        patch_file(p)
    print("done")
