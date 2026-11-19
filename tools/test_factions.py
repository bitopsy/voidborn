#!/usr/bin/env python3
"""0.16: checks the four factions (choir, maw, tympan, miasma) and the three gadgets that make the two new ones play differently.

Data:      every faction has the same 22 roles, every unit has its model / script / picture / sounds, build lists resolve and stay inside
           the faction, commanders have D-gun and Q-gun, the weapon tags that the gadgets read are where they belong, the sides exist.
Gadgets:   vb_resonance.lua, vb_miasma.lua and the hearing in vb_cloak.lua run against a small mock of the Spring API.
pip install lupa
"""
import glob, os, re, struct, sys
import lupa
try:
    from lupa import lua51 as _L
except ImportError:
    _L = lupa

root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
game = os.path.join(root, "game")
fails = 0
def check(n, ok, info=None):
    global fails
    print(("ok    " if ok else "FAIL  ") + n + (f"  ({info})" if info not in (None, "") else ""))
    if not ok: fails += 1

def lua_table(src):
    rt = _L.LuaRuntime()
    return rt.execute(src)

def py(t):
    """a lupa table -> plain python (dict / list)"""
    if _L.lua_type(t) != "table": return t
    keys = list(t.keys())
    if keys and all(isinstance(k, (int, float)) for k in keys): return [py(t[k]) for k in sorted(keys)]
    return {k: py(t[k]) for k in keys}

# ------------------------------------------------------------------------------------------------ data
FACS = ["choir", "maw", "tympan", "miasma"]
ROLES = {"com", "con", "scout", "raider", "assault", "art", "support", "heavy", "fac", "mex", "solar", "heart", "store", "radar", "def1", "def2",
         "fac2", "raider2", "assault2", "art2", "support2", "heavy2"}
units = {}
for f in sorted(glob.glob(os.path.join(game, "units", "*.lua"))):
    for name, d in py(lua_table(open(f, encoding="utf-8").read())).items():
        units[name] = d
weapons = {}
for f in sorted(glob.glob(os.path.join(game, "weapons", "*.lua"))):
    weapons.update(py(lua_table(open(f, encoding="utf-8").read())))
by_fac = {}
for n, d in units.items():
    by_fac.setdefault(d["customParams"]["faction"], {})[n] = d

check("four factions are defined", set(by_fac) == set(FACS), ", ".join(sorted(by_fac)))
for fac in FACS:
    kinds = {d["customParams"]["kind"] for d in by_fac[fac].values()}
    check(f"{fac}: has all 22 roles", ROLES <= kinds, ", ".join(sorted(ROLES - kinds)))
    for k in ("com", "fac", "fac2", "heavy2"):
        n = [u for u, d in by_fac[fac].items() if d["customParams"]["kind"] == k]
        check(f"{fac}: exactly one {k}", len(n) == 1, ", ".join(n))

pre = {"tympan": "ty_", "miasma": "mi_"}
bad = []
for fac in ("tympan", "miasma"):
    for n, d in by_fac[fac].items():
        if not n.startswith(pre[fac]): bad.append(f"{n} has the wrong prefix")
        if not os.path.isfile(os.path.join(game, "objects3d", d["objectName"])): bad.append(f"{n}: model {d['objectName']} missing")
        if not os.path.isfile(os.path.join(game, "scripts", n + ".lua")): bad.append(f"{n}: script missing")
        if not os.path.isfile(os.path.join(game, "unitpics", d["buildPic"])): bad.append(f"{n}: unit picture missing")
        for b in (d.get("buildOptions") or []):
            if b not in units: bad.append(f"{n}: builds unknown {b}")
            elif units[b]["customParams"]["faction"] != fac: bad.append(f"{n}: builds {b} of another faction")
        for w in (d.get("weapons") or []):
            if w["def"] not in weapons: bad.append(f"{n}: weapon {w['def']} undefined")
        s = d.get("sounds") or {}
        if not s.get("select"): bad.append(f"{n}: no select sound")
check("every Tympan and Miasma unit: model, script, picture, build list and weapons resolve", not bad, "; ".join(bad[:4]))

# the s3o piece names must cover every piece the script names
def s3o_pieces(path):
    b = open(path, "rb").read()
    root_off = struct.unpack_from("<I", b, 12 + 4 + 5 * 4)[0]
    names = set()
    def walk(off):
        name_off, nchild, child_off = struct.unpack_from("<III", b, off)
        e = b.index(b"\0", name_off); names.add(b[name_off:e].decode())
        for i in range(nchild): walk(struct.unpack_from("<I", b, child_off + 4 * i)[0])
    walk(root_off)
    return names
bad = []
for fac in ("tympan", "miasma"):
    for n, d in by_fac[fac].items():
        pieces = s3o_pieces(os.path.join(game, "objects3d", d["objectName"]))
        src = open(os.path.join(game, "scripts", n + ".lua"), encoding="utf-8").read()
        used = set(re.findall(r'piece\("([a-z0-9_]+)"', src)) or set(re.findall(r'piece\s*\(?\s*"([a-z0-9_]+)"', src))
        miss = {u for u in used if u not in pieces}
        if miss: bad.append(f"{n}: {', '.join(sorted(miss))}")
check("every piece a Tympan / Miasma script names exists in its model", not bad, "; ".join(bad[:4]))

# sounds referenced by the new units / weapons exist in sounds.lua and as files
items = py(lua_table(open(os.path.join(game, "gamedata", "sounds.lua"), encoding="utf-8").read()))["SoundItems"]
miss = []
for fac in ("tympan", "miasma"):
    for n, d in by_fac[fac].items():
        for lst in (d.get("sounds") or {}).values():
            for s in (lst if isinstance(lst, list) else [lst]):
                if s not in items: miss.append(f"{n}:{s}")
for k, w in weapons.items():
    if k.startswith(("ty_", "mi_")):
        for f in ("soundStart", "soundHit"):
            if w.get(f) and w[f] not in items: miss.append(f"{k}:{w[f]}")
for k, it in items.items():
    f = it.get("file") or ""
    if f and not os.path.isfile(os.path.join(game, f)): miss.append(f"file {f}")
check("all sounds of the new factions are defined and their files exist", not miss, "; ".join(miss[:4]))

for fac, cm in (("tympan", "ty_auditor"), ("miasma", "mi_rhinarch")):
    ws = [w["def"] for w in units[cm]["weapons"]]
    check(f"{cm}: three weapons (gun, D-gun, Q-gun)", [weapons[w]["weaponType"] for w in ws] == ["Cannon", "DGun", "Cannon"] and weapons[ws[2]].get("paralyzer") is True)
sides = py(lua_table(open(os.path.join(game, "gamedata", "sidedata.lua")).read()))
for cm in ("ch_hierophant", "mw_matriarch", "ty_auditor", "mi_rhinarch"):
    ws = [weapons[w["def"]] for w in units[cm]["weapons"]]
    check(f"{cm}: D-gun and Q-gun are commandFire + noAutoTarget, the main gun is neither",
          all(w.get("commandFire") is True and w.get("noAutoTarget") is True for w in ws[1:]) and not ws[0].get("commandFire") and not ws[0].get("noAutoTarget"))
for cm in ("ch_hierophant", "mw_matriarch", "ty_auditor", "mi_rhinarch"):
    src = open(os.path.join(game, "scripts", cm + ".lua"), encoding="utf-8").read()
    def body(n):
        a = src.index(f"function script.AimWeapon{n}("); b = src.index(f"function script.AimFromWeapon{n}", a); return src[a:b]
    check(f"{cm}: the script never reports the D-gun or the Q-gun as aimed (the engine cannot fire them on an attack order)",
          "return true" in body(1) and "return false" in body(2) and "return false" in body(3) and "return true" not in body(2) + body(3) and "Turn(" not in body(2) + body(3))
check("sidedata: four sides, start units exist", len(sides) == 4 and all(s["startunit"] in units for s in sides), ", ".join(s["name"] for s in sides))

res = [k for k, w in weapons.items() if (w.get("customParams") or {}).get("vb_resonance")]
poi = [k for k, w in weapons.items() if (w.get("customParams") or {}).get("vb_poison_dps")]
check("resonance tags only on Tympan weapons, and on every Tympan gun except D / Q", res and all(k.startswith("ty_") for k in res) and
      all(((w.get("customParams") or {}).get("vb_resonance") == "1") for k, w in weapons.items() if k.startswith("ty_") and w["weaponType"] not in ("DGun",) and not w.get("paralyzer")), f"{len(res)} weapons")
check("poison tags only on Miasma weapons, and on every Miasma gun except D / Q", poi and all(k.startswith("mi_") for k in poi) and
      all(((w.get("customParams") or {}).get("vb_poison_dps")) for k, w in weapons.items() if k.startswith("mi_") and w["weaponType"] not in ("DGun",) and not w.get("paralyzer")), f"{len(poi)} weapons")
check("Tympan units carry radar and ears", units["ty_whisper"]["radarDistance"] >= 1000 and units["ty_whisper"]["customParams"].get("hear") and units["ty_pinnamast"]["radarDistance"] > 2300)
check("mobile Miasma units have no radar", all(not d.get("radarDistance") for n, d in by_fac["miasma"].items() if d["customParams"]["kind"] not in ("radar",)))
# costs stay in the same band as the older factions (same role, within +-30% of the mean of choir / maw)
kinds = {}
for fac in FACS:
    for n, d in by_fac[fac].items(): kinds.setdefault(d["customParams"]["kind"], {})[fac] = d["metalCost"]
off = [f"{k}:{fac}" for k, v in kinds.items() if k not in ("combat",) for fac in ("tympan", "miasma") if fac in v and
       not (0.7 <= v[fac] / ((v["choir"] + v["maw"]) / 2) <= 1.3)]
check("metal costs sit within 30% of the older factions' average per role", not off, ", ".join(off))

# ------------------------------------------------------------------------------------------------ gadgets
MOCK = r"""
local M = {}
M.frame = 0
M.teams = {}                 -- teamID -> allyTeam
M.units = {}                 -- unitID -> { team, def, x, y, z, dead }
M.msgs, M.losState, M.losMask, M.damage, M.params, M.cloak = {}, {}, {}, {}, {}, {}
Spring = {
  GetModOptions = function() return M.opts or {} end,
  GetGameFrame = function() return M.frame end,
  AreTeamsAllied = function(a, b) return M.teams[a] == M.teams[b] end,
  GetTeamInfo = function(t) return t, "", true, false, "", M.teams[t] end,
  ValidUnitID = function(u) return M.units[u] ~= nil and not M.units[u].dead end,
  GetUnitIsDead = function(u) return not M.units[u] or M.units[u].dead end,
  SetUnitRulesParam = function(u, k, v) M.params[u .. ":" .. k] = v end,
  SetUnitLosState = function(u, ally, st) M.losState[u .. ":" .. ally] = st end,
  SetUnitLosMask = function(u, ally, st) M.losMask[u .. ":" .. ally] = st end,
  AddUnitDamage = function(u, dmg, para, by) M.damage[#M.damage + 1] = { u = u, dmg = dmg, by = by } end,
  SendMessageToTeam = function(t, m) M.msgs[#M.msgs + 1] = m end,
  GetUnitDefID = function(u) return M.units[u] and M.units[u].def end,
  GetUnitTeam = function(u) return M.units[u] and M.units[u].team end,
  GetUnitPosition = function(u) local x = M.units[u]; if x then return x.x, x.y, x.z end end,
  GetUnitsInSphere = function(x, y, z, r)
    local out = {}
    for id, u in pairs(M.units) do if (u.x - x) ^ 2 + (u.y - y) ^ 2 + (u.z - z) ^ 2 <= r * r then out[#out + 1] = id end end
    table.sort(out); return out
  end,
  GetAllUnits = function() return {} end,
  SetUnitCloak = function(u, a, b) M.cloak[u] = a end,
  GetUnitStates = function() return { firestate = 2 } end,
  GiveOrderToUnit = function() end, FindUnitCmdDesc = function() return nil end, EditUnitCmdDesc = function() end,
  InsertUnitCmdDesc = function() end, RemoveUnitCmdDesc = function() end,
  UseTeamResource = function() return true end, GetUnitIsBeingBuilt = function() return false end, GetTeamResources = function() return 100000 end,
}
CMD = { ATTACK = 20, FIRE_STATE = 45, CLOAK = 37 }
CMDTYPE = { ICON_MODE = 5 }
GG = {}
gadgetHandler = { IsSyncedCode = function() return true end, RemoveGadget = function() end }
WeaponDefs = {
  [1] = { customParams = { vb_resonance = "1" } },
  [2] = { customParams = {} },
  [3] = { customParams = { vb_poison_dps = "4", vb_poison_secs = "6" } },
}
UnitDefs = {
  [10] = { name = "ear",  customParams = { kind = "scout", hear = "400" }, weapons = { {} } },
  [11] = { name = "com",  customParams = { kind = "com" }, weapons = { {} } },
  [12] = { name = "tank", customParams = { kind = "assault" }, weapons = { {} } },
}
function load(path)
  gadget = {}
  local chunk = assert(loadfile(path)); setfenv(chunk, getfenv(0)); chunk()
  return gadget
end
function unit(id, team, def, x) M.units[id] = { team = team, def = def, x = x or 0, y = 0, z = 0 } end
return M
"""

def run_gadget_tests():
    rt = _L.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().GAME = game
    M = rt.execute(MOCK)
    L = rt.globals()
    def ctx(opts=None):
        M.frame = 0; M.units = rt.table(); M.teams = rt.table(); M.msgs = rt.table(); M.losState = rt.table(); M.losMask = rt.table()
        M.damage = rt.table(); M.params = rt.table(); M.cloak = rt.table(); M.opts = rt.table_from(opts or {})
        M.teams[0] = 0; M.teams[1] = 1; M.teams[2] = 0; M.teams[3] = 2
    def G(name):
        g = L.load(os.path.join(game, "LuaRules", "Gadgets", name)); g.Initialize(g); return g

    # ---------------- Resonance
    ctx(); g = G("vb_resonance.lua")
    for i, t in ((101, 0), (102, 0), (103, 0), (104, 0), (105, 0), (106, 2)): L.unit(i, t, 12)
    L.unit(200, 1, 12)                                                                  # the target, enemy team
    dmg = lambda atk, wd=1, tgt=200: g.UnitPreDamaged(g, tgt, 12, M.units[tgt].team, 100.0, False, wd, 0, atk, 12, M.units[atk].team)
    seq = []
    for atk in (101, 102, 103, 104, 105):
        M.frame += 3; seq.append(round(dmg(atk), 1))
    check("resonance: 100, 112, 124, 136, 148 for five different attackers", seq == [100, 112, 124, 136, 148], seq)
    M.frame += 3; check("resonance: the same attacker again does not stack with itself (counts the four others, capped)", round(dmg(101), 1) == 148, round(dmg(101), 1))
    M.frame += 200; check("resonance: the bonus is gone after the window", round(dmg(101)) == 100)
    M.frame += 3; check("resonance: a weapon without the tag gets nothing", round(dmg(102, 2)) == 100)
    M.frame += 3; check("resonance: a unit on the target's own side adds nothing (friendly fire)", round(g.UnitPreDamaged(g, 106, 12, 2, 100.0, False, 1, 0, 101, 12, 0)) == 100)
    ctx({"resonance_step": 0.0}); g = G("vb_resonance.lua")
    for i in (101, 102): L.unit(i, 0, 12)
    L.unit(200, 1, 12); M.frame = 3; g.UnitPreDamaged(g, 200, 12, 1, 100.0, False, 1, 0, 101, 12, 0); M.frame = 6
    check("resonance: step 0 in the lobby switches it off", round(g.UnitPreDamaged(g, 200, 12, 1, 100.0, False, 1, 0, 102, 12, 0)) == 100)

    # ---------------- Poison and scent
    ctx(); g = G("vb_miasma.lua")
    L.unit(1, 0, 12); L.unit(2, 1, 12)
    hit = lambda wd=3, atk=1, tgt=2, tteam=1, ateam=0: g.UnitDamaged(g, tgt, 12, tteam, 10.0, False, wd, 0, atk, 12, ateam)
    M.frame = 30; hit()
    check("poison: a hit sets one stack and marks the target for the poisoner's allyteam", M.params["2:vb_poison"] == 1 and M.losMask["2:0"] is not None)
    for _ in range(7): hit()
    check("poison: stacks are capped at five", M.params["2:vb_poison"] == 5, M.params["2:vb_poison"])
    M.frame = 45; g.GameFrame(g, 45)
    check("poison: damage over time = stacks x dps x half a second, credited to the poisoner", len(M.damage) == 1 and abs(M.damage[1].dmg - 5 * 4 * 0.5) < 1e-6 and M.damage[1].by == 1,
          (M.damage[1].dmg if len(M.damage) else None))
    n_before = len(M.damage); hit(wd=2); check("poison: a weapon without the tag does nothing", M.params["2:vb_poison"] == 5)
    hit(tgt=1, tteam=0, ateam=0, atk=1); check("poison: friendly fire does not poison", M.params["1:vb_poison"] is None)
    M.frame = 30 + 6 * 30 + 15; g.GameFrame(g, M.frame)
    check("poison: ends six seconds after the last hit", M.params["2:vb_poison"] == 0 and len(M.damage) == n_before, M.params["2:vb_poison"])
    M.frame = 30 + 10 * 30 + 15; g.GameFrame(g, M.frame)
    check("scent: the mark is released after ten seconds", M.losMask["2:0"] == 0, M.losMask["2:0"])
    ctx({"scent_secs": 0}); g = G("vb_miasma.lua"); L.unit(1, 0, 12); L.unit(2, 1, 12); M.frame = 30
    g.UnitDamaged(g, 2, 12, 1, 10.0, False, 3, 0, 1, 12, 0)
    check("scent: scent_secs 0 in the lobby switches the mark off but keeps the poison", M.losMask["2:0"] is None and M.params["2:vb_poison"] == 1)
    ctx(); g = G("vb_miasma.lua"); L.unit(1, 0, 12); L.unit(2, 1, 12); M.frame = 30
    g.UnitDamaged(g, 2, 12, 1, 10.0, False, 3, 0, 1, 12, 0); M.units[2].dead = True; g.UnitDestroyed(g, 2); g.GameFrame(g, 45)
    check("poison: a dead unit is forgotten without errors", len(M.damage) == 0)

    # ---------------- Manual guns are never aimed by the engine
    ctx(); L.WeaponDefs[10] = rt.table_from({"manualFire": True}); L.WeaponDefs[11] = rt.table_from({"manualFire": False})
    L.UnitDefs[20] = rt.table_from({"name": "cmdr", "canFly": True, "customParams": rt.table_from({"kind": "com"}),
                                    "weapons": rt.table_from([rt.table_from({"weaponDef": 11}), rt.table_from({"weaponDef": 10}), rt.table_from({"weaponDef": 10})])})
    L.unit(7, 0, 20); L.unit(8, 1, 12)
    g = G("vb_manualfire.lua")
    r = [g.AllowWeaponTarget(g, 7, 8, wn, 0, 1.0) for wn in (1, 2, 3)]
    check("manual guns: the engine may aim the main gun but never the D-gun or the Q-gun (attack, return fire, auto-target)",
          bool(r[0][0]) is True and bool(r[1][0]) is False and bool(r[2][0]) is False)
    check("manual guns: other units' weapons are never touched", bool(g.AllowWeaponTarget(g, 8, 7, 1, 0, 1.0)[0]) is True)

    # ---------------- Hearing
    ctx(); g = G("vb_cloak.lua")
    L.unit(1, 0, 11, 0)                  # a cloaked commander of team 0 (allyteam 0)
    L.unit(2, 1, 10, 300)                # an enemy ear 300 elmos away (hears 400)
    L.unit(3, 2, 10, 900)                # an ally's ear, too far; (team 2 is allyteam 0)
    g.AllowCommand(g, 1, 11, 0, 35002, rt.table_from({"1"}))
    check("hearing: the commander can cloak when nobody listens", M.cloak[1] == 3)
    M.frame = 10; g.GameFrame(g, 10)
    check("hearing: an enemy ear within range blows the cloak", M.cloak[1] == 0 and any("heard" in str(m) for m in M.msgs.values()))
    M.frame = 20; ok = g.AllowCommand(g, 1, 11, 0, 35002, rt.table_from({"1"}))
    check("hearing: and it cannot cloak again for five seconds", ok is False and M.cloak[1] == 0)
    M.frame = 10 + 5 * 30 + 1; M.units[2].x = 900; g.AllowCommand(g, 1, 11, 0, 35002, rt.table_from({"1"}))
    check("hearing: after the lock-out, out of earshot the cloak holds", M.cloak[1] == 3)
    M.frame += 10; g.GameFrame(g, M.frame); check("hearing: an ear out of range does not decloak", M.cloak[1] == 3)
    M.units[2].x = 300; M.units[2].team = 2; M.frame += 10; g.GameFrame(g, M.frame)
    check("hearing: an ally's ear never decloaks", M.cloak[1] == 3)
    ctx({"hear_cloak": "0"}); g = G("vb_cloak.lua"); L.unit(1, 0, 11, 0); L.unit(2, 1, 10, 100)
    g.AllowCommand(g, 1, 11, 0, 35002, rt.table_from({"1"})); M.frame = 10; g.GameFrame(g, 10)
    check("hearing: hear_cloak 0 in the lobby switches it off", M.cloak[1] == 3)


# ------------------------------------------------------------------------------------------------ faction menu and spawn
def run_menu_tests():
    def fresh(extra=""):
        rt = _L.LuaRuntime(unpack_returned_tuples=True)
        rt.execute(r"""
        S = { frame = 0, side = "", spec = false, opts = {}, replay = false, msgs = {}, echo = {}, team = 0 }
        Spring = {
          GetViewGeometry = function() return 1920, 1080 end, GetModOptions = function() return S.opts end,
          GetGameFrame = function() return S.frame end, IsReplay = function() return S.replay end,
          GetSpectatingState = function() return S.spec, false, false end, GetMyTeamID = function() return S.team end,
          GetTeamInfo = function(t) return t, 0, false, false, S.side, t end,
          SendLuaRulesMsg = function(m) S.msgs[#S.msgs + 1] = m end, Echo = function(m) S.echo[#S.echo + 1] = m end,
          GetMouseState = function() return 0, 0 end,
        }
        local noop = function() end
        gl = { Color = noop, Rect = noop, Texture = noop, TexRect = noop, Text = noop }
        widgetHandler = {}
        widget = {}
        """)
        rt.globals().GAME = game
        rt.execute(r"""local c = assert(loadfile(GAME .. '/LuaUI/Widgets/vb_faction_menu.lua')); setfenv(c, getfenv(0)); c(); widget:Initialize()""")
        return rt
    rt = fresh(); G = rt.globals(); W = G.widget; S = G.S
    r = W.vbRects
    cx = lambda i: ((r[i].x1 + r.__getitem__(i).x2) / 2, (r[i].y1 + r[i].y2) / 2)
    check("menu: four cards fit on a 1920x1080 screen", len(r) == 4 and all(0 <= r[i].x1 < r[i].x2 <= 1920 and 0 <= r[i].y1 < r[i].y2 <= 1080 for i in range(1, 5)))
    check("menu: shown to a player without a side before the start", bool(W.IsAbove(W, *cx(1))))
    check("menu: it draws without a Lua error", W.DrawScreen(W) is None)
    x, y = cx(3); used = W.MousePress(W, x, y, 1)
    check("menu: a click on the third card sends vbfaction:Tympan and takes the click", bool(used) and list(S.msgs.values()) == ["vbfaction:Tympan"], list(S.msgs.values()))
    W.DrawScreen(W)
    check("menu: key 4 changes the choice to Miasma", bool(W.KeyPress(W, 52, 0, False)) and list(S.msgs.values())[-1] == "vbfaction:Miasma")
    check("menu: /vbfaction choir works too", bool(W.TextCommand(W, "vbfaction choir")) and list(S.msgs.values())[-1] == "vbfaction:Choir")
    n = len(S.msgs); check("menu: a click outside the panel is left to the game", W.MousePress(W, 5, 5, 1) is False and len(S.msgs) == n)
    for what, setup in (("a side is already set (lobby or start script)", lambda: S.__setitem__("side", "Maw")),
                        ("the game has started", lambda: S.__setitem__("frame", 5)),
                        ("the player is a spectator", lambda: S.__setitem__("spec", True)),
                        ("it is a replay", lambda: S.__setitem__("replay", True)),
                        ("the lobby option faction_menu is off", lambda: S.__setitem__("opts", rt.table_from({"faction_menu": "0"})))):
        rt = fresh(); G = rt.globals(); W = G.widget; S = G.S; setup(); x, y = cx(1) if False else (960, 500)
        check(f"menu: hidden when {what}", not W.IsAbove(W, x, y) and not W.KeyPress(W, 49, 0, False) and len(S.msgs) == 0)

    # ---- the spawner
    def spawn(msgs, sides, started_msgs=()):
        rt = _L.LuaRuntime(unpack_returned_tuples=True)
        rt.globals().GAME = game
        rt.execute(r"""
        SIDEDATA = dofile(GAME .. '/gamedata/sidedata.lua')
        VFS = { Include = function(p) return SIDEDATA end }
        PL = {}; TEAMSIDE = {}; CREATED = {}
        Game = { mapSizeX = 5120, mapSizeZ = 5120 }
        Spring = {
          GetModOptions = function() return {} end,
          GetGaiaTeamID = function() return 9 end, GetTeamList = function() return { 0, 1, 2, 3 } end, GetAllUnits = function() return {} end,
          GetTeamInfo = function(t) return t, 0, false, false, TEAMSIDE[t] or "", t, {}, {} end,
          GetPlayerInfo = function(p) local x = PL[p]; return "p" .. p, true, x.spec, x.team end,
          GetSideData = function(a) if a == nil then local o = {}; for i, s in ipairs(SIDEDATA) do o[i] = { sideName = s.name, startUnit = s.startunit } end return o end
                          for _, s in ipairs(SIDEDATA) do if string.lower(s.name) == string.lower(a) then return s.startunit end end end,
          GetTeamStartPosition = function(t) return 800 + t * 100, 0, 2300 end, GetGroundHeight = function() return 0 end,
          CreateUnit = function(def, x, y, z, f, t) CREATED[t] = def; return t end,
          SetTeamResource = function() end, AddTeamResource = function() end,
        }
        gadgetHandler = { IsSyncedCode = function() return true end }
        gadget = {}
        local c = assert(loadfile(GAME .. '/LuaRules/Gadgets/game_spawn.lua')); setfenv(c, getfenv(0)); c()
        """)
        G = rt.globals()
        for t, s in sides.items(): G.TEAMSIDE[t] = s
        for p, (team, spec) in enumerate([(0, False), (1, False), (2, False), (3, False), (0, True)], 0): G.PL[p] = rt.table_from({"team": team, "spec": spec})
        for m, p in msgs: G.gadget.RecvLuaMsg(G.gadget, m, p)
        G.gadget.GameStart(G.gadget)
        for m, p in started_msgs: G.gadget.RecvLuaMsg(G.gadget, m, p)
        return {t: G.CREATED[t] for t in range(4)}
    c = spawn([("vbfaction:Tympan", 0), ("vbfaction:miasma", 1)], {})
    check("spawn: a team without a side gets the commander of the faction it chose (case does not matter)", c[0] == "ty_auditor" and c[1] == "mi_rhinarch", c)
    check("spawn: teams that did not choose keep the old default, the sides in turn", c[2] == "ty_auditor" and c[3] == "mi_rhinarch", c)
    c = spawn([("vbfaction:Tympan", 0)], {2: "Maw", 3: ""})
    check("spawn: a team whose side is set by the lobby keeps it", c[2] == "mw_matriarch", c)
    c = spawn([("vbfaction:Tympan", 2), ("vbfaction:Miasma", 4), ("vbfaction:Nonsense", 1)], {2: "Maw"})
    check("spawn: a choice for a team with a side set, from a spectator, or for a side that does not exist is ignored", c[2] == "mw_matriarch" and c[1] == "mw_matriarch", c)
    c = spawn([], {}, [("vbfaction:Miasma", 0)])
    check("spawn: a choice that arrives after the start changes nothing", c[0] == "ch_hierophant", c)

try:
    run_menu_tests()
except lupa.LuaError as e:
    check("menu and spawn tests ran without a Lua error", False, str(e)[:300])
try:
    run_gadget_tests()
except lupa.LuaError as e:
    check("gadget tests ran without a Lua error", False, str(e)[:300])

print("\nALL PASSED" if fails == 0 else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
