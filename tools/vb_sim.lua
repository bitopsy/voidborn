-- Simulates a match on the mock engine (tools/vb_mock.lua) and runs the REAL stats gadget and dashboard widget on it.
-- It is not a model of Voidborn: it only makes believable numbers (economy that grows, armies that clash, a commander
-- that dies in the end), so the gadget has something to count and the dashboard something to draw.
--   Sim.run{ teams = 2 or 4, minutes = 30, seed = 1, stopAt = minute or nil }  ->  { gadget =, unsynced =, widget =, mock = }
local Mock = dofile(ROOT .. "/tools/vb_mock.lua")
local W = Mock.world
local Sim = { Mock = Mock }

local function Rng(seed)
	local s = seed
	return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end

local function ByKind(prefix)
	local r = {}
	for id, ud in pairs(Mock.UnitDefs) do
		if ud.name:sub(1, #prefix) == prefix and ud.customParams then r[ud.customParams.kind] = r[ud.customParams.kind] or {}; table.insert(r[ud.customParams.kind], id) end
	end
	for _, l in pairs(r) do table.sort(l) end
	return r
end

local TEAMS = {
	{ side = "Choir", prefix = "ch_", color = { 0.35, 0.70, 1.00 }, name = "VoidBot Choir" },
	{ side = "Maw",   prefix = "mw_", color = { 1.00, 0.50, 0.10 }, name = "VoidBot Maw" },
	{ side = "Choir", prefix = "ch_", color = { 0.40, 1.00, 0.55 }, name = "Ada" },
	{ side = "Maw",   prefix = "mw_", color = { 0.85, 0.35, 1.00 }, name = "Brutus" },
	{ side = "Choir", prefix = "ch_", color = { 1.00, 0.90, 0.25 }, name = "Cleo" },
	{ side = "Maw",   prefix = "mw_", color = { 0.95, 0.30, 0.35 }, name = "Dax" },
}

function Sim.run(o)
	o = o or {}
	Mock.install()
	W.frame, W.units, W.nextID, W.teams, W.rules, W.echoes = 0, {}, 1, {}, {}, {}
	for k in pairs(Mock.LuaUIGlobals) do Mock.LuaUIGlobals[k] = nil end
	Mock.ops = {}
	local rnd = Rng(o.seed or 7)
	local nTeams = o.teams or 2
	local minutes = o.minutes or 30

	for t = 0, nTeams - 1 do
		local d = TEAMS[t + 1]
		W.addTeam(t, { ally = t, name = d.name, side = d.side, color = d.color, ai = (t < 2) and true or nil })
	end
	W.myAlly = 0

	-- the real gadget, both halves, joined the way the engine joins them
	local unsynced
	local function SendToUnsynced(name, ...) local fn = unsynced and unsynced.actions[name]; if fn then fn(nil, ...) end end
	local gadget = Mock.loadGadget(ROOT .. "/game/LuaRules/Gadgets/vb_stats.lua", true, SendToUnsynced)
	unsynced = Mock.loadGadget(ROOT .. "/game/LuaRules/Gadgets/vb_stats.lua", false)
	_G.Script = Mock.Script
	unsynced.gadget = unsynced

	-- the widget
	local widget
	local function LoadWidget()
		widget = Mock.loadWidget(ROOT .. "/game/LuaUI/Widgets/vb_dashboard.lua")
		if widget.Initialize then widget:Initialize() end
		return widget
	end

	local kinds = {}
	local teams = {}
	for t = 0, nTeams - 1 do
		kinds[t] = ByKind(TEAMS[t + 1].prefix)
		teams[t] = { id = t, skill = 0.75 + rnd() * 0.5, mexN = 0, solarN = 0, facN = 0, stock = 400, spent = 0, power = 1, queue = {}, spentWindow = {}, alive = true }
		if t == 1 then teams[t].skill = 0.95 end
	end
	local function Pick(t, kind) local l = kinds[t][kind]; return l and l[math.floor(rnd() * #l) + 1] end
	local function Cost(def) return Mock.UnitDefs[def].metalCost end

	local function Finish(t, def)
		local id = W.addUnit(def, t)
		gadget:UnitFinished(id, def, t)
		return id
	end
	for t = 0, nTeams - 1 do teams[t].commander = Finish(t, Pick(t, "com")) end
	if gadget.Initialize then gadget:Initialize() end
	if unsynced.Initialize then unsynced:Initialize() end
	LoadWidget()

	local function UnitsOf(t, role)
		local r = {}
		for id, u in pairs(W.units) do
			if u.team == t then
				local k = Mock.UnitDefs[u.def].customParams.kind
				local isArmy = k == "scout" or k == "raider" or k == "assault" or k == "art" or k == "heavy" or k == "support"
				local isDef = k == "def1" or k == "def2"
				if (role == "army" and isArmy) or (role == "def" and isDef) or (role == nil) then r[#r + 1] = id end
			end
		end
		table.sort(r)
		return r
	end

	local function Damage(att, tgt, amount)
		local u = W.units[tgt]
		if not u then return end
		u.hp = u.hp - amount
		local aDef = att and W.units[att] and W.units[att].def
		local aTeam = att and W.units[att] and W.units[att].team
		gadget:UnitDamaged(tgt, u.def, u.team, amount, false, 1, 1, att, aDef, aTeam)
		if u.hp <= 0 then
			local def, team = u.def, u.team
			gadget:UnitDestroyed(tgt, def, team, att, aDef, aTeam)
			W.removeUnit(tgt)
		end
	end

	local lastMsg = 0
	local total = minutes * 60 * 30
	local stopAt = o.stopAt and o.stopAt * 60 * 30 or total
	local over = false
	for frame = 1, math.min(total, stopAt) do
		W.frame = frame
		local sec = frame / 30
		if frame % 30 == 0 then
			for t = 0, nTeams - 1 do
				local T = teams[t]
				local mins = sec / 60
				-- economy
				local mInc = (3 + T.mexN * 1.9) * T.skill * (0.95 + rnd() * 0.1)
				local eInc = (12 + T.solarN * 21) * (0.95 + rnd() * 0.1)
				T.stock = T.stock + mInc
				local cap = 1000 + 500 * math.floor(mins / 6)
				local waste = 0
				if T.stock > cap then waste = T.stock - cap; T.stock = cap end
				table.insert(T.spentWindow, T.spent); T.spent = 0
				if #T.spentWindow > 6 then table.remove(T.spentWindow, 1) end
				local sp = 0; for _, v in ipairs(T.spentWindow) do sp = sp + v end
				local mExp = sp / #T.spentWindow
				local eStock = math.min(1000 + 600 * math.floor(mins / 8), (W.teams[t].res.energy[1] or 0) + eInc * 0.5)
				W.teams[t].res.metal = { T.stock, cap, mExp * 1.2, mInc, mExp, 0, 0, 0, waste }
				W.teams[t].res.energy = { eStock, 1000 + 600 * math.floor(mins / 8), eInc * 0.8, eInc, eInc * 0.7 + mExp * 4, 0, 0, 0, math.max(0, eInc * 0.1 - 2) }
				-- build whatever the budget allows
				local function Buy(kind, count)
					local def = Pick(t, kind)
					if def and T.stock >= Cost(def) then
						T.stock = T.stock - Cost(def); T.spent = T.spent + Cost(def)
						Finish(t, def)
						return true
					end
				end
				if T.mexN < 8 + math.floor(mins * 0.7) and T.mexN < 28 and Buy("mex") then T.mexN = T.mexN + 1
				elseif T.solarN < 4 + math.floor(mins * 0.9) and T.solarN < 26 and Buy("solar") then T.solarN = T.solarN + 1
				elseif T.facN < 1 and Buy("fac") then T.facN = T.facN + 1
				elseif mins > 1 and #UnitsOf(t, "army") < 12 + mins * 3.2 then
					local r = rnd()
					local kind = r < 0.15 and "scout" or r < 0.4 and "raider" or r < 0.7 and "assault" or r < 0.82 and "art" or r < 0.92 and "support" or "heavy"
					if kind == "heavy" and mins < 11 then kind = "assault" end
					Buy(kind)
				end
				if mins > 4 and rnd() < 0.05 then Buy(rnd() < 0.7 and "def1" or "def2") end
				if mins > 6 and rnd() < 0.02 then Buy("store") end
				if mins > 12 and rnd() < 0.015 then Buy("heart") end
				if mins > 2 and rnd() < 0.02 then Buy("con") end
			end
		end
		-- fighting: every 5 seconds from minute 5, in waves
		if frame % 150 == 0 and sec > 300 then
			local wave = 0.25 + 0.75 * math.abs(math.sin(sec / 170))
			for a = 0, nTeams - 1 do
				local b = (a + 1) % nTeams
				if nTeams == 2 then b = 1 - a end
				local mine, theirs = UnitsOf(a, "army"), UnitsOf(b)
				if #mine > 0 and #theirs > 0 then
					local power = 0
					for _, id in ipairs(mine) do power = power + Cost(W.units[id].def) end
					local budget = power * 0.035 * wave * teams[a].skill * (0.6 + rnd() * 0.8)
					while budget > 0 and #theirs > 0 do
						local att = mine[math.floor(rnd() * #mine) + 1]
						local tgt = theirs[math.floor(rnd() * #theirs) + 1]
						local dmg = math.min(budget, 60 + rnd() * 240)
						budget = budget - dmg
						Damage(att, tgt, dmg)
						if not W.units[tgt] then
							for i = #theirs, 1, -1 do if theirs[i] == tgt then table.remove(theirs, i) end end
						end
					end
				end
			end
		end
		gadget:GameFrame(frame)
		-- the end: the last team's commander dies
		if not over and frame >= total - 2 then
			over = true
			local loser = 1
			local alive = {}
			for id, u in pairs(W.units) do
				if u.team == loser and Mock.UnitDefs[u.def].customParams.kind == "com" then Damage(teams[0].commander, id, 1e9) end
			end
			W.teams[loser].dead = true
			gadget:GameOver({ 0 })
			if widget.GameOver then widget:GameOver() end
		end
	end
	return { stats = widget.Stats, gadget = gadget, unsynced = unsynced, widget = widget, mock = Mock, loadWidget = LoadWidget }
end

return Sim
