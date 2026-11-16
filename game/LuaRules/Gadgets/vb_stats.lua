function gadget:GetInfo()
	return {
		name = "Voidborn statistics",
		desc = "Records damage, kills, losses, economy, army and defence value and the unit mix of every team, over time, for the stats dashboard",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true,
	}
end

--[[
  What this gadget does

  SYNCED   Counts what happens (damage, kills, losses, units built, metal and energy flow) and, every
           SAMPLE_FRAMES, measures what each team owns (army value, defence value, economy value, build power,
           unit mix ...). Everything is sent to the unsynced side as short "key=value" strings, so a new
           statistic needs no change anywhere else: the widget draws what it finds.
  UNSYNCED Keeps every message (so a widget that is reloaded, or a player who joins late, gets the whole
           history again) and hands them to LuaUI/Widgets/vb_dashboard.lua through Script.LuaUI.

  Every client runs the synced code from frame 0 (also a client that joins later: it catches up), so every
  client ends up with the full history. Nothing here influences the game.

  Messages sent to the dashboard (Script.LuaUI.<name>):
    VBStats_Sample(frame, teamID, "k=v,k=v,...")     one sample of one team          (see KEYS below)
    VBStats_Units (frame, teamID, "defID:count,...")  what the team owns at that moment
    VBStats_Defs  (frame, teamID, kind, "defID:v,..") cumulative per unit type: dd dt kl ls bt  (see DEF_KINDS)
    VBStats_Event (frame, teamID, kind, defID, otherTeamID)
    VBStats_Over  (frame, "allyTeamID,allyTeamID")    the game is over, these allyteams won
]]

local SAMPLE_FRAMES = 150      -- 5 seconds between two samples
local TICK_FRAMES   = 30       -- resource flow is added up once a second
local DEFS_EVERY    = 2        -- the per-unit-type tables are sent every 2nd sample
local MAX_EVENTS    = 400

-- cumulative per-unit-type tables
--   dd  damage dealt BY this unit type        dt  damage taken BY this unit type
--   kl  enemy value killed by this unit type  ls  value lost of this unit type
--   bt  built (count)
local DEF_KINDS = { "dd", "dt", "kl", "ls", "bt" }

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local spGetUnitHealth, spGetUnitTeam, spGetUnitDefID = Spring.GetUnitHealth, Spring.GetUnitTeam, Spring.GetUnitDefID
	local spGetTeamResources, spAreTeamsAllied = Spring.GetTeamResources, Spring.AreTeamsAllied
	local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
	local floor = math.floor
	local concat = table.concat

	local gaia = Spring.GetGaiaTeamID()
	local teams = {}            -- list of the teamIDs that are measured
	local T = {}                -- teamID -> counters

	-- what kind of thing is every unit type?   army / def / eco / fac / builder / com
	local roleOf, kindOf, buildPowerOf, heavyOf = {}, {}, {}, {}
	for defID, ud in pairs(UnitDefs) do
		local cp = ud.customParams or {}
		local kind = cp.kind
		local armed = ud.weapons and #ud.weapons > 0
		local mobile = ud.canMove and (ud.speed or 0) > 0
		local role
		if cp.iscommander == "true" or kind == "com" then role = "com"
		elseif ud.isFactory or kind == "fac" then role = "fac"
		elseif kind == "con" then role = "builder"
		elseif mobile then role = "army"
		elseif armed or kind == "def1" or kind == "def2" then role = "def"
		else role = "eco" end
		roleOf[defID] = role
		kindOf[defID] = kind
		buildPowerOf[defID] = ud.buildSpeed or 0
		heavyOf[defID] = (kind == "heavy")
	end

	local function NewTeam(teamID)
		local t = {
			-- cumulative
			dd = 0, dt = 0, ff = 0, kv = 0, kc = 0, lv = 0, lc = 0, bv = 0, bc = 0,
			mp = 0, mu = 0, mw = 0, ep = 0, eu = 0, ew = 0,
			defs = {},
			sampled = 0,
		}
		for _, k in ipairs(DEF_KINDS) do t.defs[k] = {} end
		T[teamID] = t
		teams[#teams + 1] = teamID
		return t
	end

	local function Add(tbl, key, v) tbl[key] = (tbl[key] or 0) + v end

	-- the metal value of a unit: the real one (forge / custom units change it), else the unit definition's
	local function CostOf(unitID, defID)
		if Spring.GetUnitCosts then
			local ok, _, metal = pcall(Spring.GetUnitCosts, unitID)
			if ok and type(metal) == "number" then return metal end
		end
		local ud = UnitDefs[defID]
		return ud and ud.metalCost or 0
	end

	local function Finished(unitID)
		if not spGetUnitIsBeingBuilt then return true end
		local being = spGetUnitIsBeingBuilt(unitID)
		return not being
	end

	local events = {}
	local function Event(frame, teamID, kind, defID, other)
		if #events >= MAX_EVENTS then return end
		events[#events + 1] = { frame, teamID, kind, defID or 0, other or -1 }
		SendToUnsynced("vbstats_event", frame, teamID, kind, defID or 0, other or -1)
	end

	local firstBlood, seenFactory, seenHeavy = false, {}, {}

	----------------------------------------------------------------------------
	-- counting
	----------------------------------------------------------------------------
	function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
		if paralyzer or not damage or damage <= 0 then return end
		local t = T[unitTeam]
		if not t then return end
		-- do not count the overkill: the unit only had what it had
		local hp = spGetUnitHealth(unitID)
		if hp and hp < 0 then damage = damage + hp end
		if damage <= 0 then return end
		if attackerTeam and T[attackerTeam] and attackerTeam ~= unitTeam and not spAreTeamsAllied(unitTeam, attackerTeam) then
			t.dt = t.dt + damage
			local a = T[attackerTeam]
			a.dd = a.dd + damage
			if attackerDefID then
				Add(a.defs.dd, attackerDefID, damage)
				Add(t.defs.dt, attackerDefID, damage)
			end
		elseif attackerTeam and T[attackerTeam] then
			T[attackerTeam].ff = T[attackerTeam].ff + damage      -- friendly fire and self-inflicted damage
		else
			t.dt = t.dt + damage                                   -- the environment (crashes, falling ...)
		end
	end

	local finishedUnit = {}      -- unitID -> metal value: only units that were finished count as lost
	function gadget:UnitFinished(unitID, unitDefID, unitTeam)
		local t = T[unitTeam]
		if not t then return end
		local v = CostOf(unitID, unitDefID)
		finishedUnit[unitID] = v
		t.bc = t.bc + 1; t.bv = t.bv + v
		Add(t.defs.bt, unitDefID, 1)
		local frame = Spring.GetGameFrame()
		if roleOf[unitDefID] == "fac" and not seenFactory[unitTeam] then
			seenFactory[unitTeam] = true; Event(frame, unitTeam, "factory", unitDefID)
		elseif heavyOf[unitDefID] and not seenHeavy[unitTeam] then
			seenHeavy[unitTeam] = true; Event(frame, unitTeam, "heavy", unitDefID)
		elseif kindOf[unitDefID] == "def2" then
			t.def2 = (t.def2 or 0) + 1
			if t.def2 == 1 then Event(frame, unitTeam, "tower", unitDefID) end
		end
	end

	function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
		local v = finishedUnit[unitID]
		finishedUnit[unitID] = nil
		local t = T[unitTeam]
		if not t or not v then return end          -- not ours to count, or it was never finished
		t.lc = t.lc + 1; t.lv = t.lv + v
		Add(t.defs.ls, unitDefID, v)
		local frame = Spring.GetGameFrame()
		if roleOf[unitDefID] == "com" then Event(frame, unitTeam, "commander", unitDefID, attackerTeam) end
		if attackerTeam and T[attackerTeam] and attackerTeam ~= unitTeam and not spAreTeamsAllied(unitTeam, attackerTeam) then
			local a = T[attackerTeam]
			a.kc = a.kc + 1; a.kv = a.kv + v
			if attackerDefID then Add(a.defs.kl, attackerDefID, v) end
			if not firstBlood then firstBlood = true; Event(frame, attackerTeam, "firstblood", unitDefID, unitTeam) end
		end
	end

	-- (a captured or given unit keeps its value and now belongs to its new team: the scan in Sample() sees that)

	----------------------------------------------------------------------------
	-- sampling
	----------------------------------------------------------------------------
	-- (%.0f, not %d: a 32 bit %d would overflow on big totals on some platforms)
	local function Fmt(v)
		if v == floor(v) then return string.format("%.0f", v) end
		return string.format("%.2f", v)
	end

	local history = {}     -- kept for the log at game end: history[teamID] = number of samples
	local sampleNo = 0

	local function Sample(frame)
		sampleNo = sampleNo + 1
		-- what every team owns right now, in one pass over all units
		local own = {}
		for _, teamID in ipairs(teams) do
			own[teamID] = { av = 0, dv = 0, ev = 0, fv = 0, uv = 0, ac = 0, dc = 0, ec = 0, uc = 0, bp = 0, mex = 0, hp = 0, defs = {} }
		end
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			local teamID = spGetUnitTeam(unitID)
			local o = own[teamID]
			if o and Finished(unitID) then
				local defID = spGetUnitDefID(unitID)
				local v = CostOf(unitID, defID)
				local role = roleOf[defID]
				o.uv = o.uv + v; o.uc = o.uc + 1
				Add(o.defs, defID, 1)
				if role == "army" then o.av = o.av + v; o.ac = o.ac + 1
				elseif role == "def" then o.dv = o.dv + v; o.dc = o.dc + 1
				elseif role == "eco" then o.ev = o.ev + v; o.ec = o.ec + 1; if kindOf[defID] == "mex" then o.mex = o.mex + 1 end
				elseif role == "fac" then o.fv = o.fv + v end
				o.bp = o.bp + (buildPowerOf[defID] or 0)
				local hp = spGetUnitHealth(unitID)
				if hp and hp > 0 then o.hp = o.hp + hp end
			end
		end

		for _, teamID in ipairs(teams) do
			local t, o = T[teamID], own[teamID]
			local mCur, mSto, mPull, mInc, mExp = spGetTeamResources(teamID, "metal")
			local eCur, eSto, ePull, eInc, eExp = spGetTeamResources(teamID, "energy")
			local parts = {
				"mi=" .. Fmt(mInc or 0), "mx=" .. Fmt(mExp or 0), "ms=" .. Fmt(mCur or 0), "mc=" .. Fmt(mSto or 0), "mq=" .. Fmt(mPull or 0),
				"ei=" .. Fmt(eInc or 0), "ex=" .. Fmt(eExp or 0), "es=" .. Fmt(eCur or 0), "ec=" .. Fmt(eSto or 0), "eq=" .. Fmt(ePull or 0),
				"mp=" .. Fmt(t.mp), "mu=" .. Fmt(t.mu), "mw=" .. Fmt(t.mw),
				"ep=" .. Fmt(t.ep), "eu=" .. Fmt(t.eu), "ew=" .. Fmt(t.ew),
				"dd=" .. Fmt(t.dd), "dt=" .. Fmt(t.dt), "ff=" .. Fmt(t.ff),
				"kv=" .. Fmt(t.kv), "kc=" .. Fmt(t.kc), "lv=" .. Fmt(t.lv), "lc=" .. Fmt(t.lc),
				"bv=" .. Fmt(t.bv), "bc=" .. Fmt(t.bc),
				"av=" .. Fmt(o.av), "dv=" .. Fmt(o.dv), "ev=" .. Fmt(o.ev), "fv=" .. Fmt(o.fv), "uv=" .. Fmt(o.uv),
				"ac=" .. Fmt(o.ac), "dc=" .. Fmt(o.dc), "ek=" .. Fmt(o.ec), "uc=" .. Fmt(o.uc),
				"bp=" .. Fmt(o.bp), "mex=" .. Fmt(o.mex), "hp=" .. Fmt(o.hp),
			}
			SendToUnsynced("vbstats_sample", frame, teamID, concat(parts, ","))
			local u = {}
			for defID, n in pairs(o.defs) do u[#u + 1] = defID .. ":" .. n end
			SendToUnsynced("vbstats_units", frame, teamID, concat(u, ","))
			if sampleNo % DEFS_EVERY == 0 or frame <= 1 then
				for _, kind in ipairs(DEF_KINDS) do
					local d = {}
					for defID, v in pairs(t.defs[kind]) do d[#d + 1] = defID .. ":" .. Fmt(v) end
					SendToUnsynced("vbstats_defs", frame, teamID, kind, concat(d, ","))
				end
			end
			t.sampled = t.sampled + 1
		end
	end

	-- the flow of resources, added up once a second
	local function Tick()
		for _, teamID in ipairs(teams) do
			local t = T[teamID]
			local _, _, _, mInc, mExp, _, _, _, mEx = spGetTeamResources(teamID, "metal")
			local _, _, _, eInc, eExp, _, _, _, eEx = spGetTeamResources(teamID, "energy")
			local dt = TICK_FRAMES / 30
			t.mp = t.mp + (mInc or 0) * dt; t.mu = t.mu + (mExp or 0) * dt; t.mw = t.mw + (mEx or 0) * dt
			t.ep = t.ep + (eInc or 0) * dt; t.eu = t.eu + (eExp or 0) * dt; t.ew = t.ew + (eEx or 0) * dt
		end
	end

	function gadget:GameFrame(n)
		if n % TICK_FRAMES == 0 then Tick() end
		if n == 1 or n % SAMPLE_FRAMES == 0 then Sample(n) end
	end

	function gadget:GameOver(winners)
		local frame = Spring.GetGameFrame()
		Tick()
		Sample(frame)
		-- the per-unit-type tables of the very last moment
		for _, teamID in ipairs(teams) do
			for _, kind in ipairs(DEF_KINDS) do
				local d = {}
				for defID, v in pairs(T[teamID].defs[kind]) do d[#d + 1] = defID .. ":" .. Fmt(v) end
				SendToUnsynced("vbstats_defs", frame, teamID, kind, concat(d, ","))
			end
		end
		local w = {}
		for _, a in ipairs(winners or {}) do w[#w + 1] = a end
		SendToUnsynced("vbstats_over", frame, concat(w, ","))
		Spring.SetGameRulesParam("vb_stats_over", 1)
	end

	function gadget:Initialize()
		for _, teamID in ipairs(Spring.GetTeamList()) do
			if teamID ~= gaia then NewTeam(teamID) end
		end
		-- a gadget that starts late (cheats, /luarules reload): count what already stands as finished
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			if Finished(unitID) then
				local teamID = spGetUnitTeam(unitID)
				if T[teamID] then finishedUnit[unitID] = CostOf(unitID, spGetUnitDefID(unitID)) end
			end
		end
	end

--------------------------------------------------------------------------------
else  -- UNSYNCED: remember everything and hand it to the dashboard
--------------------------------------------------------------------------------
	local log = {}            -- every message, in order: { name, arg1, arg2, ... }
	local over = nil          -- { frame, winners } once the game is over

	local function Send(name, ...)
		local fn = Script.LuaUI and Script.LuaUI(name) and Script.LuaUI[name]
		if fn then pcall(fn, ...) end
	end

	local function Record(name, ...)
		log[#log + 1] = { name, ... }
		Send(name, ...)
	end

	-- replay everything to the dashboard (it asks for this when it is (re)loaded)
	local function Replay()
		for i = 1, #log do
			local m = log[i]
			Send(m[1], unpack(m, 2))
		end
		if over then Send("VBStats_Over", over[1], over[2]) end
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("vbstats_sample", function(_, frame, team, str) Record("VBStats_Sample", frame, team, str) end)
		gadgetHandler:AddSyncAction("vbstats_units",  function(_, frame, team, str) Record("VBStats_Units", frame, team, str) end)
		gadgetHandler:AddSyncAction("vbstats_defs",   function(_, frame, team, kind, str) Record("VBStats_Defs", frame, team, kind, str) end)
		gadgetHandler:AddSyncAction("vbstats_event",  function(_, frame, team, kind, def, other) Record("VBStats_Event", frame, team, kind, def, other) end)
		gadgetHandler:AddSyncAction("vbstats_over",   function(_, frame, winners) over = { frame, winners }; Send("VBStats_Over", frame, winners) end)
	end

	function gadget:Shutdown()
		for _, n in ipairs({ "vbstats_sample", "vbstats_units", "vbstats_defs", "vbstats_event", "vbstats_over" }) do
			gadgetHandler:RemoveSyncAction(n)
		end
	end

	function gadget:RecvLuaMsg(msg)
		if msg == "vbstats:replay" then Replay() end
	end
end
