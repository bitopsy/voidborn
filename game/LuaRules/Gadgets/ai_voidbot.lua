function gadget:GetInfo()
	return { name = "VoidBot", desc = "Lua skirmish bot for Voidborn", author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true }
end
if not gadgetHandler:IsSyncedCode() then return false end

local CMD_FIGHT = CMD.FIGHT
local spGiveOrder, spGetTeamUnits = Spring.GiveOrderToUnit, Spring.GetTeamUnits
local spTest = Spring.TestBuildOrder
local floor, random, sqrt, cos, sin, pi = math.floor, math.random, math.sqrt, math.cos, math.sin, math.pi

local VB_DEBUG = (Spring.GetModOptions().vb_debug == "1")
local bots = {}
local spots = {}
local defsByFaction = {}      -- faction -> kind -> defID
local kindOf = {}             -- defID -> kind
local facOf = {}
local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
local ARMY_KINDS = { raider = true, assault = true, art = true, heavy = true,
	raider2 = true, assault2 = true, art2 = true, heavy2 = true }
local FAC_KINDS = { fac = true, fac2 = true }          -- tier 1 and tier 2 factory
local SUPPORT_KINDS = { support = true, support2 = true }
local CMD_UPGRADE = 34920                              -- "Upgrade T2" (gadgets/vb_factory_upgrade.lua)
-- earliest game frame at which the bot may start the T2 upgrade, by bot_skill (1 easy .. 3 hard)
local UPGRADE_FRAME = { [1] = 18000, [2] = 12000, [3] = 8000 }

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
	Spring.Echo("[VoidBot] found " .. #spots .. " metal spots")
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

local function Dist2(ax, az, bx, bz) return (ax - bx) ^ 2 + (az - bz) ^ 2 end

function gadget:GameStart()
	ScanSpots()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local ai = Spring.GetTeamLuaAI(teamID)
		if VB_DEBUG then Spring.Echo("[VoidBot] team " .. teamID .. " luaai=" .. tostring(ai)) end
		if ai and ai ~= "" and ai:find("VoidBot") then
			local _, _, _, _, _, allyTeam = Spring.GetTeamInfo(teamID, false)
			local sx, _, sz = Spring.GetTeamStartPosition(teamID)
			local need = { "fac", "mex", "solar", "heart", "radar", "store", "def1", "def2", "con", "raider", "assault", "art", "support", "scout", "heavy" }
			local fac0 = nil
			for _, u in ipairs(Spring.GetTeamUnits(teamID)) do fac0 = facOf[Spring.GetUnitDefID(u)] or fac0 end
			local missing = {}
			for _, k in ipairs(need) do if not (fac0 and defsByFaction[fac0] and defsByFaction[fac0][k]) then missing[#missing + 1] = k end end
			if #missing > 0 then
				Spring.Echo("[VoidBot] team " .. teamID .. " (" .. tostring(fac0) .. ") is missing unit kinds: " .. table.concat(missing, ",") .. " - check units/*.lua for parse errors in infolog; bot disabled for this team")
			else
			bots[teamID] = { team = teamID, ally = allyTeam, bx = sx, bz = sz, fac = nil, wave = 0, lastAttack = 0, builds = {}, skill = tonumber(Spring.GetModOptions().bot_skill) or 2 }
			Spring.Echo("[VoidBot] controlling team " .. teamID)
			end
		end
	end
end

local function CmdCount(u)
	local c
	if Spring.GetUnitCommandCount then c = Spring.GetUnitCommandCount(u) else c = Spring.GetUnitCommands(u, 0) end
	if type(c) == "table" then c = #c end
	return c or 0
end
local function Idle(u) return CmdCount(u) == 0 end

local function FindSpot(def, ox, oz, rmin, rmax, tries)
	for i = 1, tries or 40 do
		local a, r = random() * 2 * pi, rmin + random() * (rmax - rmin)
		local x, z = ox + cos(a) * r, oz + sin(a) * r
		if x > 80 and z > 80 and x < mapX - 80 and z < mapZ - 80 then
			local y = Spring.GetGroundHeight(x, z)
			local _, ny = Spring.GetGroundNormal(x, z)
			if y > 5 and ny and ny > 0.93 and spTest(def, x, y, z, 0) >= 2 then return x, y, z end
		end
	end
end

local function Count(bot, kind)
	local d = defsByFaction[bot.fac][kind]
	return d and Spring.GetTeamUnitDefCount(bot.team, d) or 0
end
local function Queued(bot, kind)
	local n = 0
	for _, b in pairs(bot.builds) do if b.kind == kind and b.frame > Spring.GetGameFrame() - 900 then n = n + 1 end end
	return n
end
local function Total(bot, kind) return Count(bot, kind) + Queued(bot, kind) end
-- factories of either tier (a tier 1 factory that was upgraded is still a factory)
local function FacTotal(bot) return Total(bot, "fac") + Count(bot, "fac2") end

local function FreeSpot(bot, builder, maxR)
	local mexDef = defsByFaction[bot.fac].mex
	local bestd, best = 1e12, nil
	local ux, _, uz = Spring.GetUnitPosition(builder)
	for _, s in ipairs(spots) do
		local d0 = Dist2(s.x, s.z, bot.bx, bot.bz)
		if d0 < maxR * maxR then
			local y = Spring.GetGroundHeight(s.x, s.z)
			local fresh = (not s.claimed) or s.claimed < Spring.GetGameFrame() - 1500
			if y > 5 and fresh and spTest(mexDef, s.x, y, s.z, 0) >= 2 then
				local d = Dist2(s.x, s.z, ux, uz) + d0 * 0.3
				if d < bestd then bestd, best = d, s end
			end
		end
	end
	return best
end

local function Order(bot, builder, kind, x, y, z)
	if VB_DEBUG then Spring.Echo(string.format("[VoidBot] t%d %s at %d,%d", bot.team, kind, x, z)) end
	local def = defsByFaction[bot.fac][kind]
	spGiveOrder(builder, -def, { x, y, z, 0 }, {})
	bot.builds[#bot.builds + 1] = { kind = kind, frame = Spring.GetGameFrame() }
	if #bot.builds > 60 then table.remove(bot.builds, 1) end
end

local function BuilderThink(bot, u, f, res)
	local F = defsByFaction[bot.fac]
	local mexN, solarN = Total(bot, "mex"), Total(bot, "solar")
	local metal, mStore = res.m, res.ms
	local energy = res.e
	local ux, _, uz = Spring.GetUnitPosition(u)
	local expand = 700 + f * 0.35
	-- 1. factory
	if FacTotal(bot) == 0 then
		local x, y, z = FindSpot(F.fac, bot.bx + 220, bot.bz, 40, 260)
		if VB_DEBUG and not x then Spring.Echo("[VoidBot] no factory spot found near " .. bot.bx .. "," .. bot.bz) end
		if x then Order(bot, u, "fac", x, y, z) return end
	end
	-- 2. a few mexes first, then keep balance
	local wantMex = 3 + floor(f / 1800)
	if mexN < wantMex or (mexN < solarN * 0.6 + 2) then
		local s = FreeSpot(bot, u, expand)
		if s then s.claimed = f; Order(bot, u, "mex", s.x, Spring.GetGroundHeight(s.x, s.z), s.z) return end
	end
	-- 3. energy
	local wantSolar = 3 + mexN * 2
	if solarN < math.min(wantSolar, 18) then
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
	-- 4. defence near front / mexes
	local d1 = Total(bot, "def1")
	if d1 < 2 + mexN * 0.5 and metal > 150 and f > 3600 then
		local x, y, z = FindSpot(F.def1, ux, uz, 40, 260)
		if x then Order(bot, u, "def1", x, y, z) return end
	end
	if Total(bot, "def2") < math.min(4, floor(f / 7200)) and metal > 700 then
		local x, y, z = FindSpot(F.def2, bot.bx + 300, bot.bz, 60, 420)
		if x then Order(bot, u, "def2", x, y, z) return end
	end
	if FacTotal(bot) < 2 and mexN >= 6 and metal > 600 then
		local x, y, z = FindSpot(F.fac, bot.bx + 260, bot.bz + (random() < 0.5 and -1 or 1) * 200, 40, 300)
		if x then Order(bot, u, "fac", x, y, z) return end
	end
	-- 5. otherwise assist the factory
	local fac = spGetTeamUnits(bot.team)
	for _, o in ipairs(fac) do
		if FAC_KINDS[kindOf[Spring.GetUnitDefID(o)]] then spGiveOrder(u, CMD.GUARD, { o }, {}) return end
	end
end

-- Start the tier 1 -> tier 2 upgrade of this factory when the economy can carry it.  The upgrade is
-- paid a little every frame over ~45 s and the factory builds nothing meanwhile, so the bot waits for
-- a solid economy and an army first.  The command is a toggle (a second press cancels), so it is only
-- sent while the factory is not already upgrading.
local function MaybeUpgrade(bot, fac, f, res)
	local F = defsByFaction[bot.fac]
	if not F.fac2 or kindOf[Spring.GetUnitDefID(fac)] ~= "fac" then return false end
	if Count(bot, "fac2") > 0 then return false end                       -- already have a T2 factory
	if GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) then return true end  -- upgrading: leave it alone
	if bot.upgradeTried and f - bot.upgradeTried < 900 then return false end
	if f < (UPGRADE_FRAME[bot.skill] or UPGRADE_FRAME[2]) then return false end
	if Total(bot, "mex") < 5 or Count(bot, "con") < 2 then return false end
	local needM, needE = math.min(1500, (res.ms or 2000) * 0.8), math.min(2000, (res.es or 3000) * 0.8)
	if res.m < needM or res.e < needE then return false end
	bot.upgradeTried = f
	spGiveOrder(fac, CMD_UPGRADE, {}, {})
	Spring.Echo(string.format("[VoidBot] team %d upgrades its factory to tier 2 (frame %d)", bot.team, f))
	return GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) or false
end

-- what a tier 2 factory builds: mostly T2 units, paid only when the metal is there so the line does not stall
local T2_ROLL = { { "raider2", 0.20 }, { "assault2", 0.55 }, { "art2", 0.80 }, { "support2", 0.88 }, { "heavy2", 1.0 } }
local function PickT2(bot, F, res)
	local roll = random()
	for _, r in ipairs(T2_ROLL) do
		if roll <= r[2] then
			local kind, def = r[1], F[r[1]]
			if def then
				if kind == "support2" and Count(bot, "support2") >= 2 then kind = "assault2"; def = F[kind] end
				if kind == "heavy2" and Count(bot, "heavy2") >= 3 then kind = "assault2"; def = F[kind] end
				if def and res.m >= (UnitDefs[def].metalCost or 0) * 0.6 then return def end
			end
			break
		end
	end
end

local function FactoryThink(bot, fac, f, res)
	if GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) then return end       -- being upgraded
	if MaybeUpgrade(bot, fac, f, res) then return end
	local q = Spring.GetFactoryCommandCount(fac) or 0
	if type(q) == "table" then q = #q end
	if VB_DEBUG and Spring.GetGameFrame() % 900 < 30 then Spring.Echo("[VoidBot] factory q=" .. q .. " cons=" .. Count(bot, "con") .. " metal=" .. math.floor(res.m)) end
	if q >= 2 then return end
	local F = defsByFaction[bot.fac]
	local cons = Count(bot, "con")
	local wantCons = 2 + floor(f / 5400)
	if cons + Queued(bot, "con") < math.min(wantCons, 6) and res.m > 90 then
		spGiveOrder(fac, -F.con, {}, {}); bot.builds[#bot.builds + 1] = { kind = "con", frame = f }
		return
	end
	if kindOf[Spring.GetUnitDefID(fac)] == "fac2" and random() < 0.7 then
		local def2 = PickT2(bot, F, res)
		if def2 then spGiveOrder(fac, -def2, {}, {}) return end
	end
	local roll = random()
	local kind
	if f > 15000 and res.m > 1800 and roll < 0.12 then kind = "heavy"
	elseif roll < 0.30 then kind = "raider"
	elseif roll < 0.70 then kind = "assault"
	elseif roll < 0.90 then kind = "art"
	else kind = "support" end
	if kind == "support" and Count(bot, "support") >= 2 then kind = "assault" end
	if kind == "heavy" and Count(bot, "heavy") >= 3 then kind = "assault" end
	if f < 2400 and random() < 0.5 then kind = "scout" end
	local def = F[kind]
	if def then spGiveOrder(fac, -def, {}, {}) end
end

local function EnemyTarget(bot)
	local best
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, dead, _, _, ally = Spring.GetTeamInfo(t, false)
		if ally ~= bot.ally and not dead then
			local us = spGetTeamUnits(t)
			if #us > 0 then
				local u = us[random(#us)]
				local x, y, z = Spring.GetUnitPosition(u)
				if x then best = { x, y, z } end
			end
		end
	end
	return best
end

local function ArmyThink(bot, f)
	local army, home = {}, {}
	for _, u in ipairs(spGetTeamUnits(bot.team)) do
		local k = kindOf[Spring.GetUnitDefID(u)]
		if ARMY_KINDS[k] or SUPPORT_KINDS[k] or k == "scout" then army[#army + 1] = u end
	end
	local need = (6 + floor(f / 1500)) * (4 - bot.skill) * 0.5 + 4
	if #army >= need and f - bot.lastAttack > 900 then
		local t = EnemyTarget(bot)
		if t then
			bot.lastAttack = f; bot.wave = bot.wave + 1
			Spring.Echo(string.format("[VoidBot] team %d wave %d: %d units attack", bot.team, bot.wave, #army))
			for _, u in ipairs(army) do spGiveOrder(u, CMD_FIGHT, t, {}) end
		end
	elseif f - bot.lastAttack > 300 then
		for _, u in ipairs(army) do
			if Idle(u) then
				local t = EnemyTarget(bot)
				if t and bot.wave > 0 then spGiveOrder(u, CMD_FIGHT, t, {})
				else
					local ux, _, uz = Spring.GetUnitPosition(u)
					if Dist2(ux, uz, bot.bx, bot.bz) > 600 ^ 2 then spGiveOrder(u, CMD.MOVE, { bot.bx + 300, 0, bot.bz + random(-200, 200) }, {}) end
				end
			end
		end
	end
end

function gadget:GameFrame(f)
	if f % 30 ~= 7 then return end
	for teamID, bot in pairs(bots) do
		if not bot.fac then
			local u = spGetTeamUnits(teamID)[1]
			if u then bot.fac = facOf[Spring.GetUnitDefID(u)] end
		end
		if bot.fac then
			local m, ms, _, mi = Spring.GetTeamResources(teamID, "metal")
			local e, es, _, ei = Spring.GetTeamResources(teamID, "energy")
			local res = { m = m, ms = ms, e = e, es = es, mi = mi, ei = ei }
			for _, u in ipairs(spGetTeamUnits(teamID)) do
				local k = kindOf[Spring.GetUnitDefID(u)]
				if (k == "com" or k == "con") and Idle(u) and select(5, Spring.GetUnitHealth(u)) >= 1 then
					BuilderThink(bot, u, f, res)
				elseif FAC_KINDS[k] and select(5, Spring.GetUnitHealth(u)) >= 1 then
					FactoryThink(bot, u, f, res)
				elseif SUPPORT_KINDS[k] and Idle(u) then
					local c = spGetTeamUnits(teamID)
					for _, o in ipairs(c) do if FAC_KINDS[kindOf[Spring.GetUnitDefID(o)]] then spGiveOrder(u, CMD.GUARD, { o }, {}) break end end
				end
			end
			ArmyThink(bot, f)
		end
	end
end
