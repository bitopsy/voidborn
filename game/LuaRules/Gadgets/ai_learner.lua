--[[
ai_learner.lua - "Learner": a Voidborn skirmish bot that learns from every match.

Synced gadgets cannot read or write files, so learning is split in two halves:

  IN-GAME (this file)
    * the whole genome comes from mod options  lrn_<gene> = <number>  (defaults below)
    * mistake-based adaptation while the match runs:
        - bad wave (lost a lot, killed little)  -> attack later with a bigger army
        - good wave                              -> attack a bit earlier
        - per unit kind kill/loss efficiency     -> shifts the unit mix toward what works
        - energy stalls / metal floating         -> more solar / deeper factory queues
    * at game over it prints ONE line per bot team:   [LEARN_STATS] {json}
      with the genome used, the result, the economy/combat numbers and the lessons it learned

  BETWEEN MATCHES (learner.py)
    * parses that line, turns it into a fitness, moves the genome, logs everything to games.csv

Switch it on with either
    start script:  LuaAI=Learner;      (needs a "Learner" entry in the game's LuaAI.lua)
    mod option:    lrn_teams = 1,3     (comma separated team IDs, no LuaAI entry needed)
Other mod options
    bot_skill = 1..3        same option the other bots read (2 default)
    lrn_game_id = <text>    copied into the stats line so learner.py can match it
    lrn_max_frames = <n>    ends the match as a draw at that frame (so a stalemate still reports)
    lrn_debug = 1           extra log lines
    vb_cmd_upgrade_t3 = <id>  command id of the T2 -> T3 upgrade (ASSUMED 34921, see ai_darwin.lua)

Unit lookup uses customParams.faction + customParams.kind like the other bots.
The T3 path (fac3, raider3, ...) is inactive unless the faction has those kinds.
--]]

function gadget:GetInfo()
	return { name = "Learner", desc = "Self-learning Lua skirmish bot for Voidborn", author = "goddot / claude", date = "2026", license = "GPL", layer = 2, enabled = true }
end
if not gadgetHandler:IsSyncedCode() then return false end

local CMD_FIGHT, CMD_MOVE, CMD_GUARD = CMD.FIGHT, CMD.MOVE, CMD.GUARD
local CMD_UPGRADE = 34920                     -- "Upgrade T2" (gadgets/vb_factory_upgrade.lua)
local spGiveOrder, spGetTeamUnits, spTest = Spring.GiveOrderToUnit, Spring.GetTeamUnits, Spring.TestBuildOrder
local floor, random, sqrt, cos, sin, pi, min, max = math.floor, math.random, math.sqrt, math.cos, math.sin, math.pi, math.min, math.max

local MO = Spring.GetModOptions() or {}
local DEBUG = (MO.lrn_debug == "1")
local CMD_UPGRADE_T3 = tonumber(MO.vb_cmd_upgrade_t3) or 34921
local MAX_FRAMES = tonumber(MO.lrn_max_frames)

-- ============================================================
-- GENOME  (keep names, defaults and ranges in sync with GENES in learner.py)
-- ============================================================
local GENE_DEFAULTS = {
	w_raider = 0.30, w_assault = 0.30, w_art = 0.25, w_heavy = 0.50, w_support = 0.10,
	eco_priority = 0.50, def_ratio = 0.15, expand_interval = 600, con_rate = 1.0,
	attack_value = 2500, attack_interval = 1200,
	tech2_frame = 12000, tech3_frame = 30000,
	scout_rate = 0.20, retreat_hp = 0.25,
}
local G = {}
for name, def in pairs(GENE_DEFAULTS) do G[name] = tonumber(MO["lrn_" .. name]) or def end

-- ============================================================
-- STATE / DEF TABLES
-- ============================================================
local bots, spots = {}, {}
local defsByFaction, kindOf, facOf = {}, {}, {}
local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
local ARMY_KINDS = { raider = true, assault = true, art = true, heavy = true,
	raider2 = true, assault2 = true, art2 = true, heavy2 = true,
	raider3 = true, assault3 = true, art3 = true, heavy3 = true }
local FAC_KINDS = { fac = true, fac2 = true, fac3 = true }
local SUPPORT_KINDS = { support = true, support2 = true, support3 = true }
local SKILL_MUL = { [1] = 1.4, [2] = 1.0, [3] = 0.75 }     -- wave size multiplier by bot_skill
local TECH_MUL = { [1] = 1.5, [2] = 1.0, [3] = 0.67 }      -- tech frame multiplier by bot_skill
local TARGET_PRIO = { fac = 1, fac2 = 1, fac3 = 1, mex = 2, com = 3 }
local BASES = { "raider", "assault", "art", "heavy", "support" }          -- unit roles the bot chooses between
local WEIGHT_GENE = { raider = "w_raider", assault = "w_assault", art = "w_art", heavy = "w_heavy", support = "w_support" }
local ROLE_OF = {}                                                          -- kind -> role ("raider2" -> "raider")
for _, b in ipairs(BASES) do for _, s in ipairs({ "", "2", "3" }) do ROLE_OF[b .. s] = b end end
local gameEnding = false

local function Dist2(ax, az, bx, bz) return (ax - bx) ^ 2 + (az - bz) ^ 2 end

local function CmdCount(u)
	local c
	if Spring.GetUnitCommandCount then c = Spring.GetUnitCommandCount(u) else c = Spring.GetUnitCommands(u, 0) end
	if type(c) == "table" then c = #c end
	return c or 0
end
local function Idle(u) return CmdCount(u) == 0 end

local function IsLearnerTeam(teamID)
	local ai = Spring.GetTeamLuaAI(teamID)
	if ai and ai ~= "" and ai:find("Learner") then return true end
	if MO.lrn_teams then
		for id in tostring(MO.lrn_teams):gmatch("%d+") do
			if tonumber(id) == teamID then return true end
		end
	end
	return false
end

-- tiny JSON writer (numbers, strings, nested tables with string keys) for the stats line
local function JNum(v)
	if v ~= v or v == math.huge or v == -math.huge then return "0" end
	return string.format("%.6g", v)
end
local function ToJSON(v)
	local t = type(v)
	if t == "number" then return JNum(v)
	elseif t == "boolean" then return v and "true" or "false"
	elseif t == "string" then return '"' .. v:gsub('[%c"\\]', " ") .. '"'
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '":' .. ToJSON(v[k] ~= nil and v[k] or v[tonumber(k)]) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
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

local function NewBot(teamID, allyTeam, sx, sz)
	local bot = { team = teamID, ally = allyTeam, bx = sx, bz = sz, wave = 0, lastAttack = -99999, lastMex = -99999,
		builds = {}, retreat = {}, skill = floor(tonumber(MO.bot_skill) or 2),
		-- what the bot learns while the match runs
		attackMul = 1.0, solarMul = 1.0, spendMul = 1.0, kindMul = {}, killedBy = {}, lostBy = {},
		waveMark = nil, winMark = { f = 0, stall = 0, flt = 0 }, lastLearn = 0,
		st = { killed = 0, lost = 0, income = 0, stall = 0, flt = 0, samples = 0, bad_waves = 0, good_waves = 0,
			mex_peak = 0, t2 = -1, t3 = -1 } }
	if bot.skill < 1 or bot.skill > 3 then bot.skill = 2 end
	for _, b in ipairs(BASES) do bot.kindMul[b] = 1.0; bot.killedBy[b] = 0; bot.lostBy[b] = 0 end
	return bot
end

function gadget:GameStart()
	ScanSpots()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if teamID ~= Spring.GetGaiaTeamID() and IsLearnerTeam(teamID) then
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
				Spring.Echo("[Learner] team " .. teamID .. " (" .. tostring(fac0) .. ") is missing unit kinds: " .. table.concat(missing, ",") .. " - bot disabled for this team")
			else
				local bot = NewBot(teamID, allyTeam, sx, sz)
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
				Spring.Echo("[Learner] controlling team " .. teamID .. " (skill " .. bot.skill .. ")")
			end
		end
	end
end

-- ============================================================
-- LEARNING SIGNALS: who killed what, what was lost
-- ============================================================
function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	for _, bot in pairs(bots) do bot.retreat[unitID] = nil end
	local ud = UnitDefs[unitDefID]
	local cost = ud and ud.metalCost or 0
	if cost <= 0 then return end
	if Spring.GetUnitIsBeingBuilt(unitID) then return end          -- an unfinished building is not a real loss
	local victim = bots[unitTeam]
	if victim then
		victim.st.lost = victim.st.lost + cost
		local role = ROLE_OF[kindOf[unitDefID]]
		if role then victim.lostBy[role] = victim.lostBy[role] + cost end
	end
	if attackerTeam and attackerTeam ~= unitTeam then
		local killer = bots[attackerTeam]
		if killer and not Spring.AreTeamsAllied(attackerTeam, unitTeam) then
			killer.st.killed = killer.st.killed + cost
			local role = attackerDefID and ROLE_OF[kindOf[attackerDefID]]
			if role then killer.killedBy[role] = killer.killedBy[role] + cost end
		end
	end
end

-- Periodic self-review (every 1800 frames = 1 minute): turns the numbers into small corrections.
local function Learn(bot, f)
	local st = bot.st
	-- 1. kill/loss efficiency per unit role -> multiplier on that role's weight in the unit roulette
	for _, b in ipairs(BASES) do
		local k, l = bot.killedBy[b], bot.lostBy[b]
		if k + l > 400 then
			local target = max(0.5, min(2.0, (k + 150) / (l + 150)))
			bot.kindMul[b] = bot.kindMul[b] * 0.7 + target * 0.3
		end
	end
	-- 2. energy stalls and floating metal in the last window
	local win = f - bot.winMark.f
	if win > 0 then
		local stallFrac, fltFrac = (st.stall - bot.winMark.stall) / win, (st.flt - bot.winMark.flt) / win
		if stallFrac > 0.20 then bot.solarMul = min(1.8, bot.solarMul * 1.15)
		elseif stallFrac < 0.02 then bot.solarMul = max(1.0, bot.solarMul * 0.97) end
		if fltFrac > 0.30 then bot.spendMul = min(2.0, bot.spendMul * 1.15)
		elseif fltFrac < 0.05 then bot.spendMul = max(1.0, bot.spendMul * 0.97) end
	end
	bot.winMark = { f = f, stall = st.stall, flt = st.flt }
	if DEBUG then Spring.Echo(string.format("[Learner] t%d learn f=%d attackMul=%.2f solarMul=%.2f spendMul=%.2f", bot.team, f, bot.attackMul, bot.solarMul, bot.spendMul)) end
end

-- Did the last wave pay off?  Looked at 1500 frames after it left.
local function EvaluateWave(bot, f)
	local m = bot.waveMark
	if not m or f - m.f < 1500 then return end
	local dl, dk = bot.st.lost - m.lost, bot.st.killed - m.killed
	if dl > 0.7 * m.value and dk < dl then                       -- mistake: threw the army away
		bot.attackMul = min(2.0, bot.attackMul * 1.25); bot.st.bad_waves = bot.st.bad_waves + 1
	elseif dk > 0 and dk >= 1.5 * dl then                        -- good trade: can afford to go earlier
		bot.attackMul = max(0.6, bot.attackMul * 0.90); bot.st.good_waves = bot.st.good_waves + 1
	end
	bot.waveMark = nil
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
local function FacTotal(bot) return Total(bot, "fac") + Count(bot, "fac2") + Count(bot, "fac3") end
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
	if DEBUG then Spring.Echo(string.format("[Learner] t%d %s at %d,%d", bot.team, kind, x, z)) end
	spGiveOrder(builder, -defsByFaction[bot.fac][kind], { x, y, z, 0 }, {})
	Note(bot, kind)
end

-- ============================================================
-- BUILDERS (commander + constructors)
-- ============================================================
local function BuilderThink(bot, u, f, res)
	local F = defsByFaction[bot.fac]
	local mexN, solarN = Total(bot, "mex"), Total(bot, "solar")
	local metal = res.m
	local ux, _, uz = Spring.GetUnitPosition(u)
	local ecoMul = G.eco_priority / 0.5
	local defMul = G.def_ratio / 0.15
	local expand = 700 + f * 0.35

	-- 1. first factory
	if FacTotal(bot) == 0 then
		local x, y, z = FindSpot(F.fac, bot.bx + 220, bot.bz, 40, 260)
		if x then Order(bot, u, "fac", x, y, z) return end
	end
	-- 2. mexes (expand_interval paces everything beyond the first three)
	local wantMex = max(3, floor((3 + floor(f / 1800)) * ecoMul + 0.5))
	if (mexN < wantMex or mexN < solarN * 0.6 + 2) and (mexN < 3 or f - bot.lastMex >= G.expand_interval) then
		local s = FreeSpot(bot, u, expand)
		if s then
			s.claimed = f; bot.lastMex = f
			Order(bot, u, "mex", s.x, Spring.GetGroundHeight(s.x, s.z), s.z)
			return
		end
	end
	-- 3. energy (solarMul rises when the bot noticed energy stalls) and support buildings
	local wantSolar = floor((3 + mexN * 2) * ecoMul * bot.solarMul + 0.5)
	if solarN < min(wantSolar, 18 + floor((bot.solarMul - 1) * 10)) then
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
-- FACTORIES: tier-ups (T2, and T3 when the faction has it), weighted unit choice from the genome
-- ============================================================
local TIER_UP = {
	fac  = { to = "fac2", cmd = CMD_UPGRADE,    gene = "tech2_frame", minMex = 5, minCon = 2, capM = 1500, capE = 2000, stat = "t2" },
	fac2 = { to = "fac3", cmd = CMD_UPGRADE_T3, gene = "tech3_frame", minMex = 8, minCon = 3, capM = 3000, capE = 4000, stat = "t3" },
}
local function MaybeUpgrade(bot, fac, f, res)
	local F = defsByFaction[bot.fac]
	local up = TIER_UP[kindOf[Spring.GetUnitDefID(fac)]]
	if not up or not F[up.to] then return false end
	if Count(bot, up.to) > 0 then return false end
	if up.to == "fac2" and Count(bot, "fac3") > 0 then return false end
	if GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) then return true end
	if bot.upgradeTried and f - bot.upgradeTried < 900 then return false end
	if f < G[up.gene] * (TECH_MUL[bot.skill] or 1) then return false end
	if Total(bot, "mex") < up.minMex or Count(bot, "con") < up.minCon then return false end
	local needM, needE = min(up.capM, (res.ms or 2000) * 0.8), min(up.capE, (res.es or 3000) * 0.8)
	if res.m < needM or res.e < needE then return false end
	bot.upgradeTried = f
	spGiveOrder(fac, up.cmd, {}, {})
	if DEBUG then Spring.Echo(string.format("[Learner] team %d upgrades a factory to %s (frame %d)", bot.team, up.to, f)) end
	return (GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac)) or false
end

-- roulette over the five roles; gene weight x in-game learned multiplier for that role
local function PickUnit(bot, F, res, f, tier)
	local s = (tier == 1) and "" or tostring(tier)
	local list, total = {}, 0
	for _, base in ipairs(BASES) do
		local kind = base .. s
		local def = F[kind]
		local wt = (G[WEIGHT_GENE[base]] or 0) * (bot.kindMul[base] or 1)
		if def and wt > 0 and res.m >= (UnitDefs[def].metalCost or 0) * 0.6 then
			local ok = true
			if base == "heavy" then ok = f > 4000 and Count(bot, kind) < 3 + floor(f / 9000) end
			if base == "support" then ok = Count(bot, kind) < 2 end
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
	if q >= 2 + (bot.spendMul > 1.3 and 1 or 0) then return end   -- metal floating for a while: keep a deeper queue
	local F = defsByFaction[bot.fac]
	local wantCons = min(2 + floor(f * G.con_rate / 5400), 6)
	if Count(bot, "con") + Queued(bot, "con") < wantCons and res.m > 90 then
		spGiveOrder(fac, -F.con, {}, {}); Note(bot, "con")
		return
	end
	if f < 9000 and Total(bot, "scout") < 2 and random() < G.scout_rate * 2 then
		spGiveOrder(fac, -F.scout, {}, {}); Note(bot, "scout")
		return
	end
	local fk, def = kindOf[Spring.GetUnitDefID(fac)], nil
	if fk == "fac3" then def = PickUnit(bot, F, res, f, 3) or PickUnit(bot, F, res, f, 2) end
	if fk == "fac2" then def = PickUnit(bot, F, res, f, 2) end
	def = def or PickUnit(bot, F, res, f, 1) or F.raider
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
	local rhp = G.retreat_hp
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

	-- attackMul is what the bot learned from its own waves in this match
	local need = G.attack_value * (SKILL_MUL[bot.skill] or 1) * (1 + f / 36000) * bot.attackMul
	if value >= need and f - bot.lastAttack > G.attack_interval then
		local t = EnemyTarget(bot)
		if t then
			bot.target, bot.lastAttack, bot.wave = t, f, bot.wave + 1
			bot.waveMark = { f = f, lost = bot.st.lost, killed = bot.st.killed, value = value }
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
	if MAX_FRAMES and f >= MAX_FRAMES and not gameEnding then
		gameEnding = true
		Spring.Echo("[Learner] max frames reached, ending the match as a draw")
		Spring.GameOver({})
	end
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
			local st = bot.st
			-- bookkeeping for the stats line (this function runs once per second of game time)
			st.samples = st.samples + 30
			st.income = st.income + (mi or 0)
			if e < 20 then st.stall = st.stall + 30 end
			if ms and ms > 0 and m > 0.9 * ms then st.flt = st.flt + 30 end
			local mexNow = Count(bot, "mex")
			if mexNow > st.mex_peak then st.mex_peak = mexNow end
			if st.t2 < 0 and Count(bot, "fac2") > 0 then st.t2 = f end
			if st.t3 < 0 and Count(bot, "fac3") > 0 then st.t3 = f end
			if f - bot.lastLearn >= 1800 then bot.lastLearn = f; Learn(bot, f) end
			EvaluateWave(bot, f)

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

-- ============================================================
-- GAME OVER: one machine-readable line per bot team, read by learner.py
-- ============================================================
function gadget:GameOver(winners)
	local win = {}
	for _, a in ipairs(winners or {}) do win[a] = true end
	local frames = Spring.GetGameFrame()
	for teamID, bot in pairs(bots) do
		local st = bot.st
		local out = {
			game_id = MO.lrn_game_id or "", team = teamID, won = win[bot.ally] and 1 or 0,
			draw = (next(win) == nil) and 1 or 0, frames = frames, skill = bot.skill,
			genome = G,
			stats = { killed = st.killed, lost = st.lost, income = st.income, stall = st.stall, float = st.flt,
				samples = st.samples, waves = bot.wave, bad_waves = st.bad_waves, good_waves = st.good_waves,
				mex_peak = st.mex_peak, t2 = st.t2, t3 = st.t3 },
			lessons = { attack_mul = bot.attackMul, solar_mul = bot.solarMul, spend_mul = bot.spendMul,
				kind_mul = bot.kindMul, killed_by = bot.killedBy, lost_by = bot.lostBy },
		}
		Spring.Echo("[LEARN_STATS] " .. ToJSON(out))
	end
end
