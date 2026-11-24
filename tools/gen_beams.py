#!/usr/bin/env python3
"""0.19: turns a set of Choir pulse lasers into thin, continuous beams (BeamLaser).
   python3 tools/gen_beams.py        (idempotent: weapons that are already beams are skipped)

A beam deals its damage per second while it is on (see tools/test_t3_units.py), so the average damage per second of every
converted weapon is kept:  new damage = old damage per second * reloadTime / beamTime.  The beam is on for 92% of each cycle.
Run tools/gen_fx_019.py afterwards if you changed effects (it gives beams the light per-frame hit effect).
"""
import os, re, glob, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_fx_019 as fx

G = os.path.join(fx.ROOT, "game")

# weapon -> class.  light = very thin and fast, mid = a little thicker
BEAMS = {
    "ch_gazer_w1": "light", "ch_lashling_w1": "light", "ch_stare_w1": "light", "ch_saccade_w1": "light", "ch_sclera_w2": "light",
    "ch_hoplite_w1": "mid", "ch_sclera_w1": "mid", "ch_colossus_w2": "mid", "ch_panopticon_w2": "mid",
}
CLASS = {
    #        reload  thickness  core  flare  tile scroll pulse   sound
    "light": (0.8,   1.3,       0.9,  4.5,   90,  9.0,   2.4,    "vb_beam_thin_light"),
    "mid":   (1.0,   1.9,       0.9,  6.5,   110, 8.0,   2.0,    "vb_beam_thin"),
}
DROP = ("weaponVelocity", "duration", "burst", "burstRate", "sprayAngle", "cegTag", "texture3", "texture4", "size", "projectiles")

def convert(name, block):
    if fx.getv(block, "weaponType") != "LaserCannon": return block
    reload_, thick, core, flare, tile, scroll, pulse, snd = CLASS[BEAMS[name]]
    old_reload = float(fx.getv(block, "reloadTime"))
    m = None
    for l in reversed(block):
        if fx.active(l):
            m = re.search(r'default\s*=\s*([\d.]+)', l)
            if m: break
    dps = float(m.group(1)) / old_reload
    beam_time = round(reload_ * 0.92, 3)
    damage = round(dps * reload_ / beam_time, 2)
    # remove the pulse-laser keys
    block = [l for l in block if not (fx.active(l) and re.match(r'\s*(' + "|".join(DROP) + r')\s*=', l))]
    # damage
    for i in range(len(block) - 1, -1, -1):
        if fx.active(block[i]) and re.search(r'default\s*=', block[i]):
            block[i] = re.sub(r'default\s*=\s*[\d.]+', "default = " + fx.fnum(damage), block[i]); break
    for k, v in (("weaponType", '"BeamLaser"'), ("reloadTime", fx.fnum(reload_)), ("beamTime", fx.fnum(beam_time)), ("beamBurst", "false"),
                 ("sweepFire", "false"), ("thickness", fx.fnum(thick)), ("coreThickness", fx.fnum(core)), ("laserFlareSize", fx.fnum(flare)),
                 ("largeBeamLaser", "true"), ("tileLength", str(tile)), ("scrollSpeed", fx.fnum(scroll)), ("pulseSpeed", fx.fnum(pulse)),
                 ("beamDecay", "0.9"), ("targetMoveError", "0.05"),
                 ("soundStart", f'"{snd}"'), ("soundStartVolume", "0.7"), ("soundHit", '"vb_hit_beam"'), ("soundHitVolume", "0.35")):
        fx.setv(block, k, v)
    return block

def patch_file(path):
    lines = open(path).read().split("\n")
    starts = [k for k, l in enumerate(lines) if re.match(r'^\t(\w+) = \{', l)]
    starts.append(len(lines) - 1)
    out = lines[:starts[0]]; n = 0
    for a, b in zip(starts, starts[1:]):
        name = re.match(r'^\t(\w+) = \{', lines[a]).group(1)
        blk = lines[a + 1:b]
        if name in BEAMS:
            new = convert(name, blk); n += new != blk; blk = new
        out.append(lines[a]); out.extend(blk)
    out.extend(lines[starts[-1]:])
    open(path, "w").write("\n".join(out))
    return n

if __name__ == "__main__":
    total = sum(patch_file(p) for p in sorted(glob.glob(os.path.join(G, "weapons", "vb_weapons*.lua"))))
    # the beams need the light per-frame hit effect, and the effect file must exist
    for p in sorted(glob.glob(os.path.join(G, "weapons", "vb_weapons*.lua"))): fx.patch_file(p)
    print("converted %d weapons to thin beams" % total)
