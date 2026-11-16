-- A small mock of the Spring/Recoil engine, enough to run LuaRules/Gadgets/vb_stats.lua and LuaUI/Widgets/vb_dashboard.lua
-- without an engine. Used by tools/test_stats.py (smoke test) and tools/render_dashboard.py (screenshots).
-- Needs the global ROOT (the repo folder). Everything it makes is returned in the table M.
local M = {}

-- --------------------------------------------------------------------------------------------- unit definitions
local function LoadDefs()
	local defs, byName, names = {}, {}, {}
	for _, file in ipairs(UNIT_FILES) do names[#names + 1] = file end      -- the runner (Python) lists game/units/*.lua
	table.sort(names)
	local id = 0
	for _, file in ipairs(names) do
		local t = dofile(file)
		for name, d in pairs(t) do
			id = id + 1
			local ud = {
				id = id, name = name, humanName = d.name, metalCost = d.metalCost, energyCost = d.energyCost, health = d.maxDamage,
				customParams = d.customParams, buildSpeed = d.workerTime or 0,
				canMove = d.canMove and true or false, speed = (d.maxVelocity or 0) * 30,
				weapons = d.weapons and #d.weapons > 0 and d.weapons or {},
				isFactory = (d.customParams and d.customParams.kind == "fac") or false,
				isBuilding = not d.canMove,
			}
			defs[id] = ud; byName[name] = id
		end
	end
	return defs, byName
end
M.UnitDefs, M.defByName = LoadDefs()

-- --------------------------------------------------------------------------------------------- the world
local W = { frame = 0, units = {}, nextID = 1, teams = {}, rules = {}, echoes = {}, luaRulesMsgs = {} }
M.world = W

function W.addTeam(id, o)
	W.teams[id] = { id = id, ally = o.ally or id, name = o.name or ("Team " .. id), side = o.side or "", color = o.color or { 1, 1, 1 }, ai = o.ai,
		res = { metal = { 0, 1000, 0, 0, 0, 0, 0, 0, 0 }, energy = { 0, 1000, 0, 0, 0, 0, 0, 0, 0 } }, dead = false, leader = o.ai and -1 or id }
end
function W.addUnit(defID, team, hpFrac, beingBuilt)
	local id = W.nextID; W.nextID = id + 1
	local ud = M.UnitDefs[defID]
	W.units[id] = { id = id, def = defID, team = team, hp = ud.health * (hpFrac or 1), maxhp = ud.health, building = beingBuilt or false }
	return id
end
function W.removeUnit(id) W.units[id] = nil end

-- --------------------------------------------------------------------------------------------- Spring
local noop = function() end
local Spring = setmetatable({}, { __index = function(t, k) return noop end })
Spring.Echo = function(...) W.echoes[#W.echoes + 1] = table.concat({ ... }, " ") end
Spring.GetGaiaTeamID = function() return 99 end
Spring.GetTeamList = function() local l = {}; for id in pairs(W.teams) do l[#l + 1] = id end; table.sort(l); return l end
Spring.GetAllUnits = function() local l = {}; for id in pairs(W.units) do l[#l + 1] = id end; table.sort(l); return l end
Spring.GetUnitTeam = function(u) return W.units[u] and W.units[u].team end
Spring.GetUnitDefID = function(u) return W.units[u] and W.units[u].def end
Spring.GetUnitHealth = function(u) local x = W.units[u]; if x then return x.hp, x.maxhp end end
Spring.GetUnitCosts = function(u) local x = W.units[u]; if x then local ud = M.UnitDefs[x.def]; return 1000, ud.metalCost, ud.energyCost end end
Spring.GetUnitIsBeingBuilt = function(u) local x = W.units[u]; return x and x.building or false, 1 end
Spring.GetTeamResources = function(t, r) local v = W.teams[t].res[r]; return v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9] end
Spring.AreTeamsAllied = function(a, b) return W.teams[a] and W.teams[b] and W.teams[a].ally == W.teams[b].ally end
Spring.GetGameFrame = function() return W.frame end
Spring.SetGameRulesParam = function(k, v) W.rules[k] = v end
Spring.GetGameRulesParam = function(k) return W.rules[k] end
Spring.GetTeamInfo = function(t)
	local x = W.teams[t]; if not x then return end
	return t, x.leader, x.dead, x.ai ~= nil, x.side, x.ally
end
Spring.GetAIInfo = function(t) return 1, W.teams[t].name end
Spring.GetPlayerInfo = function(p) return W.teams[p] and W.teams[p].name or "Player" end
Spring.GetTeamColor = function(t) local c = W.teams[t].color; return c[1], c[2], c[3], 1 end
Spring.GetModOptions = function() return W.modoptions or {} end
Spring.GetSpectatingState = function() return W.spectator or false end
Spring.GetMyAllyTeamID = function() return W.myAlly or 0 end
Spring.IsCheatingEnabled = function() return false end
Spring.GetViewGeometry = function() return W.vsx or 1920, W.vsy or 1080 end
Spring.GetMouseState = function() return W.mx or -1, W.my or -1 end
Spring.SendLuaRulesMsg = function(m) W.luaRulesMsgs[#W.luaRulesMsgs + 1] = m end
Spring.PlaySoundFile = noop
-- fog of war: with W.fog, only every third unit of a team that is not ours is visible (and identified)
Spring.GetTeamUnits = function(t)
	local l = {}
	for id, u in pairs(W.units) do
		if u.team == t and (not W.fog or (W.teams[t].ally == (W.myAlly or 0)) or id % 3 == 0) then l[#l + 1] = id end
	end
	table.sort(l)
	return l
end
M.Spring = Spring

-- --------------------------------------------------------------------------------------------- VFS, Script, GL
local VFS = {}
VFS.Include = function(path, env)
	local f = assert(loadfile(ROOT .. "/game/" .. path))
	return f()
end
VFS.ZIP_FIRST = 0
M.VFS = VFS

local LuaUIGlobals = {}
M.LuaUIGlobals = LuaUIGlobals
M.Script = { LuaUI = setmetatable({}, { __call = function(_, name) return LuaUIGlobals[name] ~= nil end, __index = function(_, name) return LuaUIGlobals[name] end }) }

-- gl: every drawing call is recorded in M.ops, and the Python side turns them into an SVG
M.ops = {}
local cur, curW = { 1, 1, 1, 1 }, 1
local building
local gl = {}
gl.Color = function(r, g, b, a) cur = { r, g, b, a or 1 } end
gl.LineWidth = function(w) curW = w end
gl.Rect = function(x1, y1, x2, y2) M.ops[#M.ops + 1] = { "rect", cur, x1, y1, x2, y2 } end
gl.Vertex = function(x, y) if building then building.v[#building.v + 1] = x; building.v[#building.v + 1] = y end end
gl.BeginEnd = function(mode, fn, ...)
	building = { "poly", cur, mode, curW, v = {} }
	fn(...)
	M.ops[#M.ops + 1] = building
	building = nil
end
gl.Text = function(str, x, y, size, opts) M.ops[#M.ops + 1] = { "text", cur, str, x, y, size, opts or "", "glyph" } end
local function Font(kind)
	local f = { color = { 1, 1, 1, 1 } }
	function f:Begin() end
	function f:End() end
	function f:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
	function f:SetOutlineColor() end
	function f:Print(str, x, y, size, opts) M.ops[#M.ops + 1] = { "text", self.color, str, x, y, size, opts or "", kind } end
	function f:GetTextWidth(str) return (M.measure and M.measure(kind, str)) or (#str * 0.6) end
	return f
end
gl.LoadFont = function(file) return Font(file:find("Mono") and "mono" or "glyph") end
M.gl = gl
M.GL = setmetatable({ LINES = "LINES", LINE_STRIP = "LINE_STRIP", LINE_LOOP = "LINE_LOOP", TRIANGLES = "TRIANGLES", TRIANGLE_FAN = "TRIANGLE_FAN", TRIANGLE_STRIP = "TRIANGLE_STRIP", QUADS = "QUADS" }, { __index = function() return 0 end })

-- install everything as globals (the gadgets and widgets are run with an environment that falls back to _G)
function M.install()
	_G.Spring, _G.UnitDefs, _G.VFS, _G.Script, _G.gl, _G.GL = Spring, M.UnitDefs, VFS, M.Script, gl, M.GL
	_G.WeaponDefs = {}
	_G.WG = {}
	_G.CMD = setmetatable({}, { __index = function() return 0 end })
	_G.Game = { mapSizeX = 5120, mapSizeZ = 5120 }
	_G.LOG = setmetatable({}, { __index = function() return 0 end })
end

-- --------------------------------------------------------------------------------------------- gadgets and widgets
-- a gadget: loaded as the engine does, with `gadget`, `gadgetHandler` and SendToUnsynced in its environment
function M.loadGadget(path, synced, sendTo)
	local actions = {}
	local env = setmetatable({}, { __index = _G })
	env.gadget = env
	env.GG = M.GG
	env.gadgetHandler = {
		IsSyncedCode = function() return synced end,
		AddSyncAction = function(_, name, fn) actions[name] = fn end,
		RemoveSyncAction = function(_, name) actions[name] = nil end,
		RemoveGadget = noop,
	}
	if synced then env.SendToUnsynced = sendTo end
	local chunk = assert(loadfile(path))
	setfenv(chunk, env)
	chunk()
	env.actions = actions
	return env
end
M.GG = {}

function M.loadWidget(path)
	local env = setmetatable({}, { __index = _G })
	env.widget = env
	env.widgetHandler = {
		RegisterGlobal = function(_, name, fn) LuaUIGlobals[name] = fn; return true end,
		DeregisterGlobal = function(_, name) LuaUIGlobals[name] = nil end,
		AddAction = noop,
	}
	local chunk = assert(loadfile(path))
	setfenv(chunk, env)
	chunk()
	return env
end

return M
