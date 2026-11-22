--[[
llmAI.lua - evolab-evolved skirmish AI for Voidborn (working rewrite)

Evolved genes (12 generations, population 100, best champion gen 10, Elo 1238.3):
  w_heavy 0.82136, w_ranged 0.23825, w_cheap 0.30564, def_ratio 0.12528, eco_priority 0.4677
All other genes stay at their defaults.

How it is switched on (it never touches teams that VoidBot controls):
  * start script: give the team  LuaAI=llmAI;   (needs an "llmAI" entry in the game's LuaAI.lua), or
  * mod option    llm_teams = 1,3     (comma separated team IDs, no LuaAI entry needed)
Mod options:
  bot_skill = 1..3 (same option VoidBot reads; 2 default)
  llm_debug = 1            extra log lines
  llm_<gene> = <number>    overrides any gene, e.g. llm_w_heavy=0.5  (this is the evolab hook)

Unit lookup uses customParams.faction + customParams.kind exactly like ai_voidbot.lua.
--]]

function gadget:GetInfo()
	return { name = "llmAI", desc = "Evolab-evolved Lua skirmish bot for Voidborn", author = "evolab / goddot", date = "2026", license = "GPL", layer = 2, enabled = true }
end
if not gadgetHandler:IsSyncedCode() then return false end

local CMD_FIGHT, CMD_MOVE, CMD_GUARD = CMD.FIGHT, CMD.MOVE, CMD.GUARD
local CMD_UPGRADE = 34920                     -- "Upgrade T2" (gadgets/vb_factory_upgrade.lua)
local spGiveOrder, spGetTeamUnits, spTest = Spring.GiveOrderToUnit, Spring.GetTeamUnits, Spring.TestBuildOrder
local floor, random, sqrt, cos, sin, pi, min, max = math.floor, math.random, math.sqrt, math.cos, math.sin, math.pi, math.min, math.max

local MO = Spring.GetModOptions() or {}
local DEBUG = (MO.llm_debug == "1")

-- ============================================================
-- GENES (evolved values). Every behaviour number below goes through EV().
-- ============================================================
local GENES = {
	w_cheap = 0.30564, w_mid = 0.3, w_heavy = 0.82136, w_ranged = 0.23825,
	def_ratio = 0.12528, eco_priority = 0.4677, expand_interval = 600,
	attack_value = 2500, attack_interval = 1200, tech_frame = 12000,
	scout_rate = 0.2, retreat_hp = 0.25,
}
local function EV(name, default)
	local o = tonumber(MO["llm_" .. name])
	if o then return o end
	local v = GENES[name]
	if v ~= nil then return v end
	return default
end

-- ============================================================
-- STATE / DEF TABLES
-- ============================================================
local bots, spots = {}, {}
local defsByFaction, kindOf, facOf = {}, {}, {}
local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
local ARMY_KINDS = { raider = true, assault = true, art = true, heavy = true, raider2 = true, assault2 = true, art2 = true, heavy2 = true }
local FAC_KINDS = { fac = true, fac2 = true }
local SUPPORT_KINDS = { support = true, support2 = true }
local SKILL_MUL = { [1] = 1.4, [2] = 1.0, [3] = 0.75 }     -- wave size multiplier by bot_skill
local TECH_MUL = { [1] = 1.5, [2] = 1.0, [3] = 0.67 }      -- tech_frame multiplier by bot_skill
local TARGET_PRIO = { fac = 1, fac2 = 1, mex = 2, com = 3 }

local function Dist2(ax, az, bx, bz) return (ax - bx) ^ 2 + (az - bz) ^ 2 end

local function CmdCount(u)
	local c
	if Spring.GetUnitCommandCount then c = Spring.GetUnitCommandCount(u) else c = Spring.GetUnitCommands(u, 0) end
	if type(c) == "table" then c = #c end
	return c or 0
end
local function Idle(u) return CmdCount(u) == 0 end

local function IsLLMTeam(teamID)
	local ai = Spring.GetTeamLuaAI(teamID)
	if ai and ai ~= "" and ai:find("llmAI") then return true end
	if MO.llm_teams then
		for id in tostring(MO.llm_teams):gmatch("%d+") do
			if tonumber(id) == teamID then return true end
		end
	end
	return false
end

-- ============================================================
-- METAL SPOTS (flood fill of metal cells, 16 unit grid)
-- ============================================================
local function ScanSpots()
	local cw, ch = floor(mapX / 16), floor(mapZ / 16)
	local seen = {}
	for cx = 0, cw - 1 do
		for cz = 0, ch - 1 do
			local key = cx * 4096 + cz
			if not seen[key] and Spring.GetMetalAmount(cx, cz) > 0 then
				local stack, sx, sz, n = { { cx, cz } }, 0, 0, 0
				seen[key] = true
				while #stack > 0 do
					local c = table.remove(stack)
					sx, sz, n = sx + c[1], sz + c[2], n + 1
					for dx = -1, 1 do
						for dz = -1, 1 do
							local nx, nz = c[1] + dx, c[2] + dz
							local k2 = nx * 4096 + nz
							if nx >= 0 and nz >= 0 and nx < cw and nz < ch and not seen[k2] and Spring.GetMetalAmount(nx, nz) > 0 then
								seen[k2] = true; stack[#stack + 1] = { nx, nz }
							end
						end
					end
				end
				spots[#spots + 1] = { x = (sx / n) * 16 + 8, z = (sz / n) * 16 + 8 }
			end
		end
	end
	--Spring.Echo("[llmAI] found " .. #spots .. " metal spots")
end

function gadget:Initialize()
	for id, ud in pairs(UnitDefs) do
		local cp = ud.customParams
		if cp and cp.faction then
			defsByFaction[cp.faction] = defsByFaction[cp.faction] or {}
			defsByFaction[cp.faction][cp.kind] = id
			kindOf[id] = cp.kind; facOf[id] = cp.faction
		end
	end
end

function gadget:GameStart()
	ScanSpots()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if teamID ~= Spring.GetGaiaTeamID() and IsLLMTeam(teamID) then
			local _, _, _, _, _, allyTeam = Spring.GetTeamInfo(teamID, false)
			local sx, _, sz = Spring.GetTeamStartPosition(teamID)
			local need = { "fac", "mex", "solar", "heart", "radar", "store", "def1", "def2", "con", "raider", "assault", "art", "support", "scout", "heavy" }
			local fac0
			for _, u in ipairs(spGetTeamUnits(teamID)) do fac0 = facOf[Spring.GetUnitDefID(u)] or fac0 end
			local missing = {}
			for _, k in ipairs(need) do
				if not (fac0 and defsByFaction[fac0] and defsByFaction[fac0][k]) then missing[#missing + 1] = k end
			end
			if #missing > 0 then
				--Spring.Echo("[llmAI] team " .. teamID .. " (" .. tostring(fac0) .. ") is missing unit kinds: " .. table.concat(missing, ",") .. " - bot disabled for this team")
			else
				local bot = { team = teamID, ally = allyTeam, bx = sx, bz = sz, wave = 0, lastAttack = -99999, lastMex = -99999,
					builds = {}, retreat = {}, skill = floor(tonumber(MO.bot_skill) or 2) }
				if bot.skill < 1 or bot.skill > 3 then bot.skill = 2 end
				-- nearest enemy start position: used for the defence front and for scouting
				local bestd
				for _, t in ipairs(Spring.GetTeamList()) do
					local _, _, _, _, _, ally = Spring.GetTeamInfo(t, false)
					if t ~= Spring.GetGaiaTeamID() and ally ~= allyTeam then
						local ex, _, ez = Spring.GetTeamStartPosition(t)
						if ex and ex >= 0 then
							local d = Dist2(ex, ez, sx, sz)
							if not bestd or d < bestd then bestd, bot.ex, bot.ez = d, ex, ez end
						end
					end
				end
				if bot.ex then
					local dx, dz = bot.ex - sx, bot.ez - sz
					local len = max(1, sqrt(dx * dx + dz * dz))
					bot.fx, bot.fz = sx + dx / len * 350, sz + dz / len * 350
				else
					bot.fx, bot.fz = sx, sz
				end
				bots[teamID] = bot
				--Spring.Echo("[llmAI] controlling team " .. teamID .. " (skill " .. bot.skill .. ")")
			end
		end
	end
end

function gadget:UnitDestroyed(unitID)
	for _, bot in pairs(bots) do bot.retreat[unitID] = nil end
end

-- ============================================================
-- HELPERS
-- ============================================================
local function Count(bot, kind)
	local d = defsByFaction[bot.fac][kind]
	return d and Spring.GetTeamUnitDefCount(bot.team, d) or 0
end
local function Queued(bot, kind)
	local n, f = 0, Spring.GetGameFrame()
	for _, b in pairs(bot.builds) do if b.kind == kind and b.frame > f - 900 then n = n + 1 end end
	return n
end
local function Total(bot, kind) return Count(bot, kind) + Queued(bot, kind) end
local function FacTotal(bot) return Total(bot, "fac") + Count(bot, "fac2") end
local function Note(bot, kind) bot.builds[#bot.builds + 1] = { kind = kind, frame = Spring.GetGameFrame() }; if #bot.builds > 60 then table.remove(bot.builds, 1) end end

local function FindSpot(def, ox, oz, rmin, rmax, tries)
	for _ = 1, tries or 40 do
		local a, r = random() * 2 * pi, rmin + random() * (rmax - rmin)
		local x, z = ox + cos(a) * r, oz + sin(a) * r
		if x > 80 and z > 80 and x < mapX - 80 and z < mapZ - 80 then
			local y = Spring.GetGroundHeight(x, z)
			local _, ny = Spring.GetGroundNormal(x, z)
			if y > 5 and ny and ny > 0.93 and spTest(def, x, y, z, 0) >= 2 then return x, y, z end
		end
	end
end

local function FreeSpot(bot, builder, maxR)
	local mexDef = defsByFaction[bot.fac].mex
	local bestd, best = 1e12, nil
	local ux, _, uz = Spring.GetUnitPosition(builder)
	local f = Spring.GetGameFrame()
	for _, s in ipairs(spots) do
		local d0 = Dist2(s.x, s.z, bot.bx, bot.bz)
		if d0 < maxR * maxR then
			local y = Spring.GetGroundHeight(s.x, s.z)
			local fresh = (not s.claimed) or s.claimed < f - 1500
			if y > 5 and fresh and spTest(mexDef, s.x, y, s.z, 0) >= 2 then
				local d = Dist2(s.x, s.z, ux, uz) + d0 * 0.3
				if d < bestd then bestd, best = d, s end
			end
		end
	end
	return best
end

local function Order(bot, builder, kind, x, y, z)
	if DEBUG then Spring.Echo(string.format("[llmAI] t%d %s at %d,%d", bot.team, kind, x, z)) end
	spGiveOrder(builder, -defsByFaction[bot.fac][kind], { x, y, z, 0 }, {})
	Note(bot, kind)
end

-- ============================================================
-- BUILDERS (commander + constructors): economy and defence, scaled by the genes
-- ============================================================
local function BuilderThink(bot, u, f, res)
	local F = defsByFaction[bot.fac]
	local mexN, solarN = Total(bot, "mex"), Total(bot, "solar")
	local metal = res.m
	local ux, _, uz = Spring.GetUnitPosition(u)
	local ecoMul = EV("eco_priority", 0.5) / 0.5
	local defMul = EV("def_ratio", 0.15) / 0.15
	local expand = 700 + f * 0.35

	-- 1. first factory
	if FacTotal(bot) == 0 then
		local x, y, z = FindSpot(F.fac, bot.bx + 220, bot.bz, 40, 260)
		if x then Order(bot, u, "fac", x, y, z) return end
	end
	-- 2. mexes (expand_interval paces everything beyond the first three)
	local wantMex = max(3, floor((3 + floor(f / 1800)) * ecoMul + 0.5))
	if (mexN < wantMex or mexN < solarN * 0.6 + 2) and (mexN < 3 or f - bot.lastMex >= EV("expand_interval", 600)) then
		local s = FreeSpot(bot, u, expand)
		if s then
			s.claimed = f; bot.lastMex = f
			Order(bot, u, "mex", s.x, Spring.GetGroundHeight(s.x, s.z), s.z)
			return
		end
	end
	-- 3. energy and support buildings
	local wantSolar = floor((3 + mexN * 2) * ecoMul + 0.5)
	if solarN < min(wantSolar, 18) then
		local x, y, z = FindSpot(F.solar, bot.bx, bot.bz, 60, 420)
		if x then Order(bot, u, "solar", x, y, z) return end
	end
	if Total(bot, "heart") < (f > 18000 and 3 or 1) and metal > 500 and f > 7000 then
		local x, y, z = FindSpot(F.heart, bot.bx - 80, bot.bz, 60, 380)
		if x then Order(bot, u, "heart", x, y, z) return end
	end
	if Total(bot, "radar") < 1 and mexN >= 3 then
		local x, y, z = FindSpot(F.radar, bot.bx + 300, bot.bz, 40, 300)
		if x then Order(bot, u, "radar", x, y, z) return end
	end
	if Total(bot, "store") < 1 and mexN >= 6 then
		local x, y, z = FindSpot(F.store, bot.bx, bot.bz, 60, 350)
		if x then Order(bot, u, "store", x, y, z) return end
	end
	-- 4. defence: def_ratio scales the target; half of the turrets go to the front facing the enemy
	if Total(bot, "def1") < floor((2 + mexN * 0.5) * defMul + 0.5) and metal > 150 and f > 3600 then
		local ox, oz = ux, uz
		if random() < 0.5 then ox, oz = bot.fx, bot.fz end
		local x, y, z = FindSpot(F.def1, ox, oz, 40, 260)
		if x then Order(bot, u, "def1", x, y, z) return end
	end
	if Total(bot, "def2") < min(4, floor(f / 7200 * defMul)) and metal > 700 then
		local x, y, z = FindSpot(F.def2, bot.fx, bot.fz, 60, 320)
		if x then Order(bot, u, "def2", x, y, z) return end
	end
	if FacTotal(bot) < 2 and mexN >= 6 and metal > 600 then
		local x, y, z = FindSpot(F.fac, bot.bx + 260, bot.bz + (random() < 0.5 and -1 or 1) * 200, 40, 300)
		if x then Order(bot, u, "fac", x, y, z) return end
	end
	-- 5. otherwise help the factory
	if bot.facUnit then spGiveOrder(u, CMD_GUARD, { bot.facUnit }, {}) end
end

-- ============================================================
-- FACTORIES: tier-up at tech_frame, weighted unit choice from the genes
-- ============================================================
local function MaybeUpgrade(bot, fac, f, res)
	local F = defsByFaction[bot.fac]
	if not F.fac2 or kindOf[Spring.GetUnitDefID(fac)] ~= "fac" then return false end
	if Count(bot, "fac2") > 0 then return false end
	if GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) then return true end
	if bot.upgradeTried and f - bot.upgradeTried < 900 then return false end
	if f < EV("tech_frame", 12000) * (TECH_MUL[bot.skill] or 1) then return false end
	if Total(bot, "mex") < 5 or Count(bot, "con") < 2 then return false end
	local needM, needE = min(1500, (res.ms or 2000) * 0.8), min(2000, (res.es or 3000) * 0.8)
	if res.m < needM or res.e < needE then return false end
	bot.upgradeTried = f
	spGiveOrder(fac, CMD_UPGRADE, {}, {})
	--Spring.Echo(string.format("[llmAI] team %d upgrades its factory to tier 2 (frame %d)", bot.team, f))
	return (GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac)) or false
end

-- roulette over cheap / mid / ranged / heavy using the evolved weights
local function PickUnit(bot, F, res, f, tier2)
	local s = tier2 and "2" or ""
	local weights = {
		{ "raider" .. s, EV("w_cheap", 0.3) }, { "assault" .. s, EV("w_mid", 0.3) },
		{ "art" .. s, EV("w_ranged", 0.5) }, { "heavy" .. s, EV("w_heavy", 0.2) },
		{ "support" .. s, 0.12 },
	}
	local list, total = {}, 0
	for _, w in ipairs(weights) do
		local kind, wt = w[1], w[2]
		local def = F[kind]
		if def and wt > 0 then
			local ok = res.m >= (UnitDefs[def].metalCost or 0) * 0.6
			if kind:sub(1, 5) == "heavy" then ok = ok and f > 4000 and Count(bot, kind) < 3 + floor(f / 9000) end
			if kind:sub(1, 7) == "support" then ok = ok and Count(bot, kind) < 2 end
			if ok then list[#list + 1] = { def, wt }; total = total + wt end
		end
	end
	if total <= 0 then return nil end
	local pick, run = random() * total, 0
	for _, o in ipairs(list) do
		run = run + o[2]
		if run >= pick then return o[1] end
	end
	return list[#list][1]
end

local function FactoryThink(bot, fac, f, res)
	if GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) then return end
	if MaybeUpgrade(bot, fac, f, res) then return end
	local q = Spring.GetFactoryCommandCount(fac) or 0
	if type(q) == "table" then q = #q end
	if q >= 2 then return end
	local F = defsByFaction[bot.fac]
	local wantCons = min(2 + floor(f / 5400), 6)
	if Count(bot, "con") + Queued(bot, "con") < wantCons and res.m > 90 then
		spGiveOrder(fac, -F.con, {}, {}); Note(bot, "con")
		return
	end
	if f < 9000 and Total(bot, "scout") < 2 and random() < EV("scout_rate", 0.2) * 2 then
		spGiveOrder(fac, -F.scout, {}, {}); Note(bot, "scout")
		return
	end
	local def
	if kindOf[Spring.GetUnitDefID(fac)] == "fac2" then def = PickUnit(bot, F, res, f, true) end
	def = def or PickUnit(bot, F, res, f, false) or F.raider
	if def then spGiveOrder(fac, -def, {}, {}) end
end

-- ============================================================
-- ARMY: value-based waves, focused target, retreat, scouts
-- ============================================================
local function EnemyTarget(bot)
	local best, bestScore
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, dead, _, _, ally = Spring.GetTeamInfo(t, false)
		if t ~= Spring.GetGaiaTeamID() and ally ~= bot.ally and not dead then
			for _, u in ipairs(spGetTeamUnits(t)) do
				local x, y, z = Spring.GetUnitPosition(u)
				if x then
					local p = TARGET_PRIO[kindOf[Spring.GetUnitDefID(u)]] or 4
					local score = p * 1e6 + Dist2(x, z, bot.bx, bot.bz) ^ 0.5
					if not bestScore or score < bestScore then bestScore, best = score, { x, y, z } end
				end
			end
		end
	end
	return best
end

local function ArmyThink(bot, units, f)
	local army, value = {}, 0
	local rhp = EV("retreat_hp", 0.25)
	for _, u in ipairs(units) do
		local def = Spring.GetUnitDefID(u)
		local k = kindOf[def]
		if ARMY_KINDS[k] or SUPPORT_KINDS[k] then
			local hp, mhp, _, _, bp = Spring.GetUnitHealth(u)
			if hp and mhp and (bp or 1) >= 1 then
				local frac, rt = hp / mhp, bot.retreat[u]
				if rt and (frac > 0.6 or f - rt > 1800) then bot.retreat[u] = nil; rt = nil end
				if not rt and frac < rhp and bot.wave > 0 then
					bot.retreat[u] = f; rt = f
					spGiveOrder(u, CMD_MOVE, { bot.bx + 200, Spring.GetGroundHeight(bot.bx + 200, bot.bz), bot.bz }, {})
				end
				if not rt then army[#army + 1] = u; value = value + (UnitDefs[def].metalCost or 0) end
			end
		end
	end
	if #army == 0 then return end

	local need = EV("attack_value", 2500) * (SKILL_MUL[bot.skill] or 1) * (1 + f / 36000)
	if value >= need and f - bot.lastAttack > EV("attack_interval", 1200) then
		local t = EnemyTarget(bot)
		if t then
			bot.target, bot.lastAttack, bot.wave = t, f, bot.wave + 1
			--Spring.Echo(string.format("[llmAI] team %d wave %d: %d units (value %d / %d)", bot.team, bot.wave, #army, value, need))
			for _, u in ipairs(army) do spGiveOrder(u, CMD_FIGHT, t, {}) end
		end
		return
	end
	if f - bot.lastAttack < 300 then return end
	-- idle units: reinforce as a group of 4+, otherwise gather at the rally point
	local idle = {}
	for _, u in ipairs(army) do if Idle(u) then idle[#idle + 1] = u end end
	if bot.wave > 0 and #idle >= 4 then
		local t = EnemyTarget(bot)
		if t then bot.target = t; for _, u in ipairs(idle) do spGiveOrder(u, CMD_FIGHT, t, {}) end return end
	end
	local rx, rz = (bot.bx + bot.fx) / 2, (bot.bz + bot.fz) / 2
	for _, u in ipairs(idle) do
		local ux, _, uz = Spring.GetUnitPosition(u)
		if ux and Dist2(ux, uz, rx, rz) > 350 ^ 2 then
			spGiveOrder(u, CMD_MOVE, { rx + random(-100, 100), Spring.GetGroundHeight(rx, rz), rz + random(-100, 100) }, {})
		end
	end
end

local function ScoutThink(bot, scouts)
	for _, u in ipairs(scouts) do
		if Idle(u) then
			local x, z
			if bot.ex and random() < 0.5 then
				x, z = bot.ex + random(-300, 300), bot.ez + random(-300, 300)
			elseif #spots > 0 then
				local s = spots[random(#spots)]; x, z = s.x, s.z
			else
				x, z = random(mapX), random(mapZ)
			end
			x, z = max(80, min(mapX - 80, x)), max(80, min(mapZ - 80, z))
			spGiveOrder(u, CMD_MOVE, { x, Spring.GetGroundHeight(x, z), z }, {})
		end
	end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function gadget:GameFrame(f)
	if f % 30 ~= 13 then return end
	for teamID, bot in pairs(bots) do
		local units = spGetTeamUnits(teamID)
		if not bot.fac then
			for _, u in ipairs(units) do
				bot.fac = facOf[Spring.GetUnitDefID(u)]
				if bot.fac then break end
			end
		end
		if bot.fac then
			local m, ms, _, mi = Spring.GetTeamResources(teamID, "metal")
			local e, es, _, ei = Spring.GetTeamResources(teamID, "energy")
			local res = { m = m, ms = ms, e = e, es = es, mi = mi, ei = ei }
			local builders, facs, supports, scouts = {}, {}, {}, {}
			bot.facUnit = nil
			for _, u in ipairs(units) do
				local k = kindOf[Spring.GetUnitDefID(u)]
				local built = (select(5, Spring.GetUnitHealth(u)) or 1) >= 1
				if built then
					if k == "com" or k == "con" then builders[#builders + 1] = u
					elseif FAC_KINDS[k] then facs[#facs + 1] = u; bot.facUnit = bot.facUnit or u
					elseif SUPPORT_KINDS[k] then supports[#supports + 1] = u
					elseif k == "scout" then scouts[#scouts + 1] = u end
				end
			end
			for _, u in ipairs(builders) do if Idle(u) then BuilderThink(bot, u, f, res) end end
			for _, u in ipairs(facs) do FactoryThink(bot, u, f, res) end
			if bot.facUnit then
				for _, u in ipairs(supports) do if Idle(u) then spGiveOrder(u, CMD_GUARD, { bot.facUnit }, {}) end end
			end
			ScoutThink(bot, scouts)
			ArmyThink(bot, units, f)
		end
	end
end
