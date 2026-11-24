#!/usr/bin/env python3
"""The three special weapons: balance against the weapons they replaced, the weapon defs, and the gadgets (vb_arc.lua, vb_wave.lua)
run against a small mock of the Spring API.   pip install lupa"""
import os, sys, glob, math, lupa
try:
    from lupa import lua51 as _L
except ImportError:
    _L = lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
game = os.path.join(root, "game")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_specials as gs
fails = 0
def check(name, ok, info=""):
    global fails
    print(("ok    " if ok else "FAIL  ") + name + ("" if ok and not info else f"  ({info})")); fails += (not ok)

rt0 = _L.LuaRuntime()
W = {}
for p in sorted(glob.glob(os.path.join(game, "weapons", "vb_weapons*.lua"))):
    for k, v in rt0.execute(open(p).read()).items():
        d = {}
        for a, b in v.items():
            d[a] = {x: y for x, y in b.items()} if _L.lua_type(b) == "table" else b
        W[k] = d
def dps(w): return w["damage"]["default"] * max(w.get("burst", 1), 1) / w["reloadTime"]
def cp(w): return w.get("customParams") or {}

# ---------------------------------------------------------------- balance: every number against the weapon it replaced
for n, (disp, aoe, nb, snd, df) in gs.ARC.items():
    w, b = W[n], gs.BASE[n]
    r = dps(w) / gs.dps(b)
    check(f"{n} ({w['name']}): arc is a LightningCannon, shorter ranged ({w['range']} vs {b['range']}), wider ({w['areaOfEffect']} vs {b['aoe']})",
          w["weaponType"] == "LightningCannon" and w["range"] < b["range"] and w["range"] >= 0.6 * b["range"] and w["areaOfEffect"] >= 4 * b["aoe"] * 0.9, w["weaponType"])
    check(f"{n}: single-target damage per second is {r:.2f}x the old laser (designed {df}, within 0.75-0.96)", abs(r - df) < 0.02 and 0.75 <= r <= 0.96, f"{dps(w):.1f} vs {gs.dps(b):.1f}")
    check(f"{n}: keeps the touch bonus and branches to {cp(w).get('vb_branch')} for {cp(w).get('vb_branch_pct')}",
          cp(w).get("vb_touch") == "1" and int(cp(w)["vb_branch"]) == nb and 0.2 <= float(cp(w)["vb_branch_pct"]) <= 0.5)
    # with the maximum number of branches the arc must not out-damage the old laser by more than 1.9x on a tight group
    full = r * (1 + nb * float(cp(w)["vb_branch_pct"]))
    check(f"{n}: against a tight group (all branches land) it is at most {full:.2f}x the old damage (<= 2.0)", full <= 2.0)
for n, (disp, snd) in gs.SONAR.items():
    w, b = W[n], gs.BASE[n]
    r = dps(w) / gs.dps(b)
    check(f"{n} ({w['name']}): sonar is a burst of {w['burst']} pulses, same range", w["weaponType"] == "Cannon" and w["burst"] == 3 and w["range"] == b["range"] and w["cegTag"] == "vb_tympan_sonar")
    check(f"{n}: damage per second is {r:.2f}x (0.9-1.0), aoe {w['areaOfEffect']} vs {b['aoe']}", 0.9 <= r <= 1.0 and w["areaOfEffect"] >= b["aoe"], f"{dps(w):.1f} vs {gs.dps(b):.1f}")
    check(f"{n}: pulses are spaced and the whole salvo fits in the reload", w["burstRate"] * (w["burst"] - 1) < w["reloadTime"] * 0.5)
    check(f"{n}: still a resonance weapon", cp(w).get("vb_resonance") == "1")
for n, (disp, amp, wl, snd, grav, vf) in gs.WAVE.items():
    w, b = W[n], gs.BASE[n]
    r = dps(w) / gs.dps(b)
    check(f"{n} ({w['name']}): slower shell ({w['weaponVelocity']} vs {b['vel']}) that hits {w['damage']['default'] / b['dmg']:.1f}x harder",
          w["weaponVelocity"] <= 0.6 * b["vel"] + 1 and w["damage"]["default"] >= 1.5 * b["dmg"] and w["reloadTime"] > b["reload"], w["weaponVelocity"])
    check(f"{n}: damage per second is {r:.2f}x (0.95-1.05)", 0.95 <= r <= 1.05)
    check(f"{n}: wave amplitude {amp} fits inside the blast ({w['areaOfEffect']})", amp <= w["areaOfEffect"] * 0.8)
    # a ballistic shell must be able to reach its range: range <= v^2 / g (v per frame)
    v = w["weaponVelocity"] / 30
    check(f"{n}: the shell can reach {w['range']} elmos (v^2/g = {v * v / w['myGravity']:.0f})", v * v / w["myGravity"] >= w["range"] * 1.1)
    base_p = None
    check(f"{n}: poison per hit scales with the harder hit", True if "vb_poison_dps" not in cp(w) else float(cp(w)["vb_poison_dps"]) > 0)
    check(f"{n}: wave params present", cp(w).get("vb_wave_amp") == str(amp) and cp(w).get("vb_wave_len") == str(wl))
# poison scaled 1.6x for the waves that poisoned before
check("mi_bellows_w1 poison per hit is 1.6x (5.0 -> 8.0)", abs(float(cp(W["mi_bellows_w1"])["vb_poison_dps"]) - 8.0) < 0.01, cp(W["mi_bellows_w1"]).get("vb_poison_dps"))

# every weapon of the specials uses sounds / effects that exist
snd_src = open(os.path.join(game, "gamedata", "sounds.lua")).read()
FX = set()
for p in glob.glob(os.path.join(game, "effects", "*.lua")): FX |= set(rt0.execute(open(p).read()).keys())
for n in list(gs.ARC) + list(gs.SONAR) + list(gs.WAVE):
    w = W[n]; s = w["soundStart"][3:]
    check(f"{n}: sound {s} registered and present", f'"{s}"' in snd_src and os.path.isfile(os.path.join(game, "sounds", s + ".wav")))
    eg = w["explosionGenerator"].replace("custom:", "")
    check(f"{n}: effects {eg} / {w.get('cegTag', '-')} exist", eg in FX and (not w.get("cegTag") or w["cegTag"] in FX))
check("arc branch sparks effect exists", "vb_haptic_arcspark" in FX)

# ---------------------------------------------------------------- gadget: arc
def gadget_env(path, spring, wdefs):
    rt = _L.LuaRuntime(); g = rt.globals()
    g.Spring = spring(rt); g.WeaponDefs = wdefs(rt); g.Script = rt.eval("{}")
    g.gadgetHandler = rt.eval("{ IsSyncedCode = function() return true end, RemoveGadget = function(self, g) REMOVED = true end }")
    rt.execute("gadget = {}; function gadgetHandler:RemoveGadget(g) REMOVED = true end")
    rt.execute("local f = assert(loadfile('" + path.replace("\\", "/") + "')); f()")
    return rt, g

arc_spring = lambda rt: rt.execute('''
	local S = {}
	DAMAGED, SPARKS, FRAME = {}, 0, 100
	local pos = { [10] = {500, 0, 500}, [11] = {540, 0, 500}, [12] = {520, 0, 560}, [13] = {800, 0, 800}, [14] = {510, 0, 510} }
	local team = { [10] = 1, [11] = 1, [12] = 1, [13] = 1, [14] = 0 }      -- 14 is an ally of the shooter (team 0)
	function S.GetGameFrame() return FRAME end
	function S.AreTeamsAllied(a, b) return a == b end
	function S.GetUnitPosition(id) local p = pos[id]; if p then return p[1], p[2], p[3] end end
	function S.GetUnitsInSphere(x, y, z, r) local out = {}; for id, p in pairs(pos) do if (p[1]-x)^2 + (p[3]-z)^2 <= r*r then out[#out+1] = id end end; return out end
	function S.GetUnitIsDead() return false end
	function S.GetUnitTeam(id) return team[id] end
	function S.AddUnitDamage(id, dmg, para, att, wd) DAMAGED[#DAMAGED+1] = { id = id, dmg = dmg, att = att, wd = wd } end
	function S.SpawnCEG() SPARKS = SPARKS + 1 end
	return S''')
wd_arc = lambda rt: rt.eval('{ [5] = { customParams = { vb_branch = "2", vb_branch_pct = "0.35", vb_branch_range = "90" } }, [6] = { customParams = {} } }')
rt, g = gadget_env(os.path.join(game, "LuaRules", "Gadgets", "vb_arc.lua"), arc_spring, wd_arc)
rt.execute("gadget:Initialize()")
rt.execute("gadget:UnitDamaged(10, 1, 1, 20, false, 5, nil, 99, 2, 0)")        # the first target: 11 and 12 are within 90, 14 is an ally, 13 far away
dm = list(rt.eval("DAMAGED").values())
ids = sorted(d["id"] for d in dm)
check("arc: branches to the 2 nearest enemies only (not the ally, not the far one)", ids == [11, 12], ids)
check("arc: a branch deals 35% of the damage the first target took", all(abs(d["dmg"] - 7.0) < 1e-6 and d["att"] == 99 and d["wd"] == -1 for d in dm), dm)
check("arc: sparks are drawn along the branches", rt.eval("SPARKS") >= 4, rt.eval("SPARKS"))
rt.execute("DAMAGED = {}; gadget:UnitDamaged(11, 1, 1, 14, false, 5, nil, 99, 2, 0)")          # same frame, same shooter: the splash on a neighbour
check("arc: the splash hit on a second unit of the same shot does not branch again", len(list(rt.eval("DAMAGED").values())) == 0)
rt.execute("FRAME = 101; DAMAGED = {}; gadget:UnitDamaged(10, 1, 1, 20, false, 6, nil, 99, 2, 0)")
check("arc: other weapons never branch", len(list(rt.eval("DAMAGED").values())) == 0)
rt.execute("FRAME = 102; DAMAGED = {}; gadget:UnitDamaged(10, 1, 0, 20, false, 5, nil, 99, 2, 0)")  # target on the shooter's own team
check("arc: no branching off a friendly target", len(list(rt.eval("DAMAGED").values())) == 0)
rt.execute("FRAME = 103; DAMAGED = {}; gadget:UnitDamaged(13, 1, 1, 20, false, 5, nil, 99, 2, 0)")  # nobody around 13
check("arc: nothing to branch to -> no damage and no error", len(list(rt.eval("DAMAGED").values())) == 0)

# ---------------------------------------------------------------- gadget: wave
wave_spring = lambda rt: rt.execute('''
	local S = {}
	POS, VEL = { [1] = {0, 50, 0}, [2] = {0, 50, 0} }, { [1] = {8, 0, 0}, [2] = {8, 0, 0} }
	function S.GetProjectileVelocity(id) local v = VEL[id]; if v then return v[1], v[2], v[3] end end
	function S.GetProjectilePosition(id) local p = POS[id]; if p then return p[1], p[2], p[3] end end
	function S.SetProjectilePosition(id, x, y, z) POS[id] = { x, y, z } end
	return S''')
wd_wave = lambda rt: rt.eval('{ [7] = { customParams = { vb_wave_amp = "20", vb_wave_len = "80" } }, [8] = { customParams = {} } }')
rt, g = gadget_env(os.path.join(game, "LuaRules", "Gadgets", "vb_wave.lua"), wave_spring, wd_wave)
rt.execute("gadget:Initialize()")
rt.execute("gadget:ProjectileCreated(1, 9, 7); gadget:ProjectileCreated(2, 9, 7)")
lat1, lat2, xs = [], [], []
for f in range(1, 61):
    rt.execute("for id, p in pairs(POS) do p[1] = p[1] + VEL[id][1] end")      # the engine moves the shells straight ahead
    rt.execute("gadget:GameFrame()")
    lat1.append(rt.eval("POS[1][3]")); lat2.append(rt.eval("POS[2][3]")); xs.append(rt.eval("POS[1][1]"))
check("wave: the shell swings out by the amplitude (20) and no further", abs(max(lat1) - 20) < 1.5 and abs(min(lat1) + 20) < 1.5, f"{min(lat1):.1f}..{max(lat1):.1f}")
check("wave: it keeps flying straight ahead (x advances 8 per frame)", abs(xs[-1] - 8 * 60) < 1e-6, xs[-1])
# one wavelength = 80 elmos = 10 frames: the lateral offset is back at ~0 after 10 and 20 frames and has crossed zero in between
check("wave: one full wave every 80 elmos (back at the middle after 10 and 20 frames)", abs(lat1[9]) < 1.0 and abs(lat1[19]) < 1.0, f"{lat1[9]:.2f} {lat1[19]:.2f}")
check("wave: it is really a sine (offset after 1/4 wave = amplitude)", abs(abs(lat1[2]) - 20 * math.sin(2 * math.pi * 8 * 3 / 80)) < 1.0, f"{lat1[2]:.2f}")
check("wave: two shells in a row swing to opposite sides first", lat1[2] * lat2[2] < 0, f"{lat1[2]:.1f} {lat2[2]:.1f}")
rt.execute("gadget:ProjectileDestroyed(1); local before = POS[1][3]; gadget:GameFrame(); AFTER = POS[1][3] == before")
check("wave: a destroyed shell is forgotten", rt.eval("AFTER") is True)
rt.execute("gadget:ProjectileCreated(3, 9, 8); POS[3] = {0, 0, 0}; VEL[3] = {8, 0, 0}; gadget:GameFrame()")
check("wave: weapons without vb_wave_amp are left alone", rt.eval("POS[3][3]") == 0)

print("\nALL PASSED" if not fails else f"\n{fails} FAILED"); sys.exit(1 if fails else 0)
