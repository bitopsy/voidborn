#!/usr/bin/env python3
"""Weapon graphics / sound checks: thin continuous beams, the light per-frame beam hit effect, alien weapon sounds.   pip install lupa"""
import os, re, sys, glob, wave, lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
game = os.path.join(root, "game")
rt = lupa.LuaRuntime()
fails = 0
def check(name, ok, info=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok and not info else f"  ({info})")); fails += (not ok)

def load(p): return rt.execute(open(p).read())
W = {}
for p in sorted(glob.glob(os.path.join(game, "weapons", "vb_weapons*.lua"))):
    t = load(p)
    for k, v in t.items(): W[k] = {a: (dict(b.items()) if lupa.lua_type(b) == "table" else b) for a, b in v.items()}
FX = set()
for p in sorted(glob.glob(os.path.join(game, "effects", "*.lua"))): FX |= set(load(p).keys())
SND = set(rt.execute(open(os.path.join(game, "gamedata", "sounds.lua")).read()).keys()) if False else None
snd_src = open(os.path.join(game, "gamedata", "sounds.lua")).read()

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_beams
beams = gen_beams.BEAMS
for name, cls in beams.items():
    w = W[name]
    check(f"{name}: is a BeamLaser", w["weaponType"] == "BeamLaser", w["weaponType"])
    check(f"{name}: thin ({w['thickness']}) and on for most of its cycle", w["thickness"] <= 2.0 and 0.85 <= w["beamTime"] / w["reloadTime"] < 1.0,
          f"{w['beamTime']}/{w['reloadTime']}")
    check(f"{name}: no pulse-laser keys left", not any(k in w for k in ("weaponVelocity", "duration", "burst", "sprayAngle", "cegTag")))
    check(f"{name}: beam hum registered and present", w["soundStart"] in ("vb_beam_thin_light", "vb_beam_thin")
          and f'"{w["soundStart"][3:]}"' in snd_src and os.path.isfile(os.path.join(game, "sounds", w["soundStart"][3:] + ".wav")), w["soundStart"])

# every beam in the game fires its hit effect each frame: it must be the light one
bad = [n for n, w in W.items() if w.get("weaponType") == "BeamLaser" and not str(w.get("explosionGenerator", "")).endswith("_beamhit")]
check("every BeamLaser uses the light per-frame hit effect", not bad, bad)
missing = []
for n, w in W.items():
    for key in ("explosionGenerator", "cegTag"):
        v = str(w.get(key) or "")
        if v.startswith("custom:"): v = v[7:]
        if v and v not in FX and key == "explosionGenerator" and v.startswith("vb_"): missing.append((n, v))
        if v and key == "cegTag" and v not in FX: missing.append((n, v))
check("every effect a weapon names exists", not missing, missing[:5])

# alien weapon sounds are lower: compare the spectral centroid with the preserved original of a Haptic sound
import numpy as np
def read(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), dtype=np.int16).astype(float) / 32768
def centroid(x): S = np.abs(np.fft.rfft(x)); return (S * np.fft.rfftfreq(len(x), 1 / 44100)).sum() / S.sum()
for n in ("touch_lash", "hit_touch", "touch_light"):
    src, out = read(os.path.join(root, "tools", "sound_src", n + ".wav")), read(os.path.join(game, "sounds", n + ".wav"))
    check(f"{n}: lower and longer than its source", centroid(out) < centroid(src) * 0.8 and len(out) > len(src) * 1.2, f"{centroid(src):.0f} -> {centroid(out):.0f} Hz")
b = read(os.path.join(game, "sounds", "beam_thin.wav")); r = [np.sqrt((b[i:i + 4410] ** 2).mean()) for i in range(4410, len(b) - 8820, 4410)]
check("beam hum is steady (no gaps while it overlaps)", min(r) > 0.6 * max(r), f"{min(r):.2f}..{max(r):.2f}")
print("\nALL PASSED" if not fails else f"\n{fails} FAILED"); sys.exit(1 if fails else 0)
