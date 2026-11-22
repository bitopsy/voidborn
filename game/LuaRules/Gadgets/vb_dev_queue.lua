function gadget:GetInfo()
	return { name = "Voidborn Dev Build Queue", desc = "Forge units cost metal/energy/build time, show progress and can be put on hold",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

if not gadgetHandler:IsSyncedCode() then return end

--------------------------------------------------------------------------------
-- What this does
--   The forge and the build panel no longer create a unit instantly.  They send
--       vbq:add:<n>:<spec>      queue n units of a design
--       vbq:rem:<n>:<id>        take n units out of the queue (the last ones first)
--       vbq:hold:1:<id>         toggle hold on that queue entry
--       vbq:clear:1:<id>        cancel the entry
--   Every factory has its own production line.  A forge design is built by a tier 2 lab and gets that lab's
--   line too (the build panel names the lab in spec.fac); without a tier 2 lab the designs share one team line.  On each line the first entry that is not on hold is
--   built; the lines run side by side and all pay from the team's metal and energy.  While it is built the gadget pays its metal and energy a little every
--   frame; when the team cannot pay, the unit stalls.  Cancelling refunds what was
--   already paid.  When a unit is finished, the gadget hands "vbdev:<spec>" (count=1)
--   to the existing vb_dev_units gadget, which creates the unit exactly as before.
--   The state is published to the owner as the team rules param "vbq":
--       <id>|<units left>|<progress 0..1000>|<state b/s/w/h/p>|<factory unitID or 0>;...
--   and the ids in vbq:rem / hold / clear may carry the factory: "<id>@<factoryID>".
--
--   The states are:  b = building, s = stalled (the team cannot pay), w = waiting in the
--   queue, h = on hold, p = pending (the factory of the line is still being built, so
--   the entry waits for the factory to finish; nothing is paid until then).
--------------------------------------------------------------------------------

local FPS = 30
local MAX_QUEUE = 200

-- the price rules, shared with the forge panel
local Cost
do
	local ok, c = pcall(VFS.Include, "LuaRules/Headers/vb_cost.h.lua")
	if ok and type(c) == "table" and type(c.Cost) == "function" then Cost = c end
end

local queues = {}      -- teamID -> list of entries
local dirty = {}       -- teamID -> true when the published string has to be rewritten

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function SafeId(s)
	return (tostring(s or ""):gsub("[^%w_%-]", "_"):sub(1, 24))
end

-- the wire format of the forge: a Lua table literal with quoted keys (sorted, so that
-- two equal specs give the same string)
local function Ser(t)
	local keys = {}
	for k, v in pairs(t) do
		if type(v) == "number" or type(v) == "string" then keys[#keys + 1] = k end
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = t[k]
		if type(v) == "number" then parts[#parts + 1] = string.format("[%q]=%s", k, string.format("%.6g", v))
		else parts[#parts + 1] = string.format("[%q]=%q", k, v) end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Strict parser for the wire format (["key"]=number or ["key"]="text", comma separated).
-- It never runs the received text as code, so a hand made message cannot hang or crash the game.
local function Parse(str)
	if type(str) ~= "string" or #str > 24000 then return nil end
	local body = str:match("^{(.*)}$")
	if not body then return nil end
	local t, pos, n = {}, 1, #body
	while pos <= n do
		local k, after = body:match('^%["([%w_]+)"%]=()', pos)
		if not k then return nil end
		pos = after
		local sv, a2 = body:match('^"([^"\\]*)"()', pos)
		if sv then
			t[k], pos = sv, a2
		else
			local nv, a3 = body:match("^(%-?[%d%.eE%+%-]+)()", pos)
			local num = nv and tonumber(nv)
			if not num then return nil end
			t[k], pos = num, a3
		end
		local c = body:sub(pos, pos)
		if c == "," then pos = pos + 1 elseif c ~= "" then return nil end
	end
	return t
end

local function Price(spec, ud)
	local s = {}
	for k, v in pairs(spec) do s[k] = v end
	s.count = 1
	if Cost then
		local ok, p = pcall(Cost.Cost, s, ud)
		if ok and type(p) == "table" then
			-- build is in SECONDS here (the header returns build points and the matching seconds)
			return { metal = tonumber(p.metal) or 0, energy = tonumber(p.energy) or 0,
				build = math.max(0.5, tonumber(p.seconds) or ((tonumber(p.build) or 30) / (Cost.BUILD_POWER or 100))) }
		end
	end
	local function Pick(v, base) v = tonumber(v) or 0; if v > 0 then return v end return base or 0 end
	return { metal = Pick(s.metal, ud.metalCost), energy = Pick(s.energy, ud.energyCost),
		build = math.max(0.5, Pick(s.buildtime, ud.buildTime or 3000) / 100) }
end

local function TeamOf(playerID)
	local _, _, isSpec, teamID = Spring.GetPlayerInfo(playerID, false)
	if isSpec then return nil end
	return teamID
end

local function Publish(teamID)
	local q = queues[teamID] or {}
	local parts = {}
	for i, e in ipairs(q) do
		parts[i] = string.format("%s|%d|%d|%s|%d", e.tid, e.n, math.floor(e.prog * 1000 + 0.5), e.hold and "h" or e.state, e.line or 0)
	end
	Spring.SetTeamRulesParam(teamID, "vbq", table.concat(parts, ";"), { allied = true })
	dirty[teamID] = nil
end

-- pay for a slice of the unit: all or nothing
local function Pay(teamID, metal, energy)
	if metal <= 0 and energy <= 0 then return true end
	local m = Spring.GetTeamResources(teamID, "metal") or 0
	local e = Spring.GetTeamResources(teamID, "energy") or 0
	if m < metal or e < energy then return false end
	if metal > 0 then Spring.UseTeamResource(teamID, "metal", metal) end
	if energy > 0 then Spring.UseTeamResource(teamID, "energy", energy) end
	return true
end

local function Refund(teamID, e)
	if e.spentM > 0 then Spring.AddTeamResource(teamID, "metal", e.spentM) end
	if e.spentE > 0 then Spring.AddTeamResource(teamID, "energy", e.spentE) end
	e.spentM, e.spentE, e.prog = 0, 0, 0
end

local function Find(teamID, tid, line)
	for i, e in ipairs(queues[teamID] or {}) do
		if e.tid == tid and (e.line or 0) == (line or 0) then return e, i end
	end
end

-- "d_mw_gnasher@123" -> "d_mw_gnasher", 123
local function SplitRef(ref)
	local id, fac = tostring(ref or ""):match("^(.-)@(%d+)$")
	if id then return SafeId(id), tonumber(fac) end
	return SafeId(ref), 0
end

--------------------------------------------------------------------------------
-- where finished units appear: next to the factory that ordered them, otherwise at the team start
--------------------------------------------------------------------------------
local function OwnFactory(teamID, fac)
	fac = tonumber(fac)
	if fac and Spring.ValidUnitID(fac) and Spring.GetUnitTeam(fac) == teamID then return fac end
end

local function SpawnPoint(teamID, fac)
	fac = OwnFactory(teamID, fac)
	local x, z
	if fac then
		local fx, _, fz = Spring.GetUnitPosition(fac)
		local r = (Spring.GetUnitRadius(fac) or 40) + 48
		local a = math.random() * 2 * math.pi
		x, z = fx + r * math.cos(a), fz + r * math.sin(a)
	else
		local sx, _, sz = Spring.GetTeamStartPosition(teamID)
		if sx and sx > 0 and sz and sz > 0 then x, z = sx + math.random(-60, 60), sz + math.random(-60, 60)
		else x, z = Game.mapSizeX / 2, Game.mapSizeZ / 2 end
	end
	x = math.max(16, math.min(Game.mapSizeX - 16, x))
	z = math.max(16, math.min(Game.mapSizeZ - 16, z))
	return x, z
end

-- can this factory build that unit?  (stops a hand made message from conjuring any unit)
local function FactoryCanBuild(fac, ud)
	local fd = fac and UnitDefs[Spring.GetUnitDefID(fac)]
	if not fd then return false end
	for _, b in ipairs(fd.buildOptions or {}) do
		if b == ud.id or b == ud.name then return true end
	end
	return false
end

-- Is the factory finished?  A factory that is still under construction cannot
-- build anything yet, so its line waits for it (the entry sits in the queue in
-- the "p" state - pending - until the factory is done).
local function FactoryReady(fac)
	fac = tonumber(fac)
	if not fac or fac == 0 then return true end       -- the team line of forge designs has no factory
	if not Spring.ValidUnitID(fac) then return false end
	if Spring.GetUnitIsBeingBuilt and Spring.GetUnitIsBeingBuilt(fac) then return false end
	if GG.VB_FactoryBusy and GG.VB_FactoryBusy(fac) then return false end      -- being upgraded to tier 2
	return true
end

--------------------------------------------------------------------------------
-- queue operations
--------------------------------------------------------------------------------
local function Add(teamID, playerID, spec, n)
	local tid = SafeId(spec.id)
	if tid == "" then tid = "custom" end
	spec.id = tid
	local ud = spec.base and UnitDefNames[spec.base]
	if not ud then
		Spring.SendMessageToPlayer(playerID, "[VB] queue: unknown base unit '" .. tostring(spec.base) .. "'")
		return
	end
	local line = 0
	if spec.plain then
		-- a stock unit ordered from a factory: no design changes, and the factory must really offer it
		local fac = OwnFactory(teamID, spec.fac)
		if not fac or not FactoryCanBuild(fac, ud) then return end
		spec = { id = tid, base = spec.base, plain = 1, fac = fac }
		line = fac
	else
		-- a forge design: the player has to be allowed to use the forge, and only cheaters may run lua=
		if not (GG.VB_ForgeAllowed and GG.VB_ForgeAllowed(playerID)) then
			Spring.SendMessageToPlayer(playerID, "[VB] the unit forge is switched off in this game (modoption vb_forge)")
			return
		end
		-- ... and has to own a finished tier 2 factory (upgrade the faction's factory first)
		if GG.VB_ForgeUnlocked and not GG.VB_ForgeUnlocked(teamID) then
			Spring.SendMessageToPlayer(playerID, "[VB] custom units need a Tier 2 factory: upgrade your factory first")
			return
		end
		if spec.lua and not (GG.VB_DevAllowed and GG.VB_DevAllowed(playerID)) then spec.lua = nil end
		-- designs are built by a TIER 2 lab and get that lab's own line (the units appear next to it);
		-- without a lab that is tier 2 (cheats, or the build panel did not name one) they share the team line
		local fac = OwnFactory(teamID, spec.fac)
		local fd = fac and UnitDefs[Spring.GetUnitDefID(fac)]
		if fac and (tonumber(fd and fd.customParams and fd.customParams.tier) or 1) >= 2 then
			line, spec.fac = fac, fac
		else
			spec.fac = nil
		end
	end
	spec.team = teamID
	spec.x, spec.z = nil, nil
	n = math.max(1, math.min(MAX_QUEUE, math.floor(tonumber(n) or 1)))
	local q = queues[teamID]
	if not q then q = {}; queues[teamID] = q end
	local e = Find(teamID, tid, line)
	if e then
		e.n = math.min(MAX_QUEUE, e.n + n)
		if e.prog == 0 then          -- nothing paid yet: take the newest version of the design
			e.spec, e.price = spec, Price(spec, ud)
		end
	else
		q[#q + 1] = { tid = tid, line = line, spec = spec, price = Price(spec, ud), n = n, prog = 0, spentM = 0, spentE = 0,
			hold = false, state = "w", lastOk = 0, playerID = playerID }
	end
	dirty[teamID] = true
end

local function Remove(teamID, tid, n, all, line)
	local e, i = Find(teamID, tid, line)
	if not e then return end
	if all or e.n <= n then
		Refund(teamID, e)
		table.remove(queues[teamID], i)
	else
		e.n = e.n - n
	end
	dirty[teamID] = true
end

local function Finish(teamID, e, frame)
	-- the factory has to be finished before the unit may appear
	if not FactoryReady(e.line) then return end
	local spec = {}
	for k, v in pairs(e.spec) do spec[k] = v end
	spec.count, spec.team = 1, teamID
	e.n, e.prog, e.spentM, e.spentE = e.n - 1, 0, 0, 0
	if e.n <= 0 then
		local _, i = Find(teamID, e.tid, e.line)
		if i then table.remove(queues[teamID], i) end
	end
	dirty[teamID] = true
	local x, z = SpawnPoint(teamID, spec.fac)
	if spec.plain then
		-- stock unit: create it directly (not a dev feature, so no cheat check)
		local ud = UnitDefNames[spec.base]
		local unitID = ud and Spring.CreateUnit(ud.id, x, Spring.GetGroundHeight(x, z), z, 0, teamID)
		if not unitID then
			Spring.Echo("[VB] queue: could not create " .. tostring(spec.base) .. " (unit limit or blocked spot)")
		else
			local fac = OwnFactory(teamID, spec.fac)
			if fac then   -- walk a little away from the factory so the next unit has room
				local fx, _, fz = Spring.GetUnitPosition(fac)
				local dx, dz = x - fx, z - fz
				local d = math.max(1, math.sqrt(dx * dx + dz * dz))
				Spring.GiveOrderToUnit(unitID, CMD.MOVE, { x + dx / d * 70, Spring.GetGroundHeight(x, z), z + dz / d * 70 }, 0)
			end
		end
		return
	end
	spec.x, spec.z = x, z
	-- the existing creation gadget does the actual spawning (the queue already charged for the unit)
	local ok, err = pcall(GG.VB_QueueSpawn, spec, e.playerID)
	if not ok then Spring.Echo("[VB] queue: could not hand the unit to vb_dev_units: " .. tostring(err)) end
end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
function gadget:Initialize()
	Spring.SetGameRulesParam("vbq_ready", 1)
end

function gadget:Shutdown()
	Spring.SetGameRulesParam("vbq_ready", 0)
end

-- a factory that is replaced by its tier 2 version (vb_factory_upgrade.lua) keeps its lines: they move to the new unit
function GG.VB_FactorySwap(oldID, newID)
	for teamID, q in pairs(queues) do
		for _, e in ipairs(q) do
			if (e.line or 0) == oldID then e.line = newID end
			if e.spec and tonumber(e.spec.fac) == oldID then e.spec.fac = newID end
		end
		dirty[teamID] = true
	end
end

-- a factory that dies takes its line with it: refund what was paid
function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	if GG.VB_swapping == unitID then return end          -- only being replaced by its tier 2 version
	local q = queues[teamID]
	if not q then return end
	for i = #q, 1, -1 do
		if (q[i].line or 0) == unitID then Refund(teamID, q[i]); table.remove(q, i); dirty[teamID] = true end
	end
end

function gadget:RecvLuaMsg(msg, playerID)
	if type(msg) ~= "string" or msg:sub(1, 4) ~= "vbq:" then return end
	local teamID = TeamOf(playerID)
	if not teamID then return true end
	local cmd, n, rest = msg:match("^vbq:(%a+):(%d+):(.*)$")
	if not cmd then return true end
	n = tonumber(n) or 1
	if cmd == "add" then
		local spec = Parse(rest)
		if spec then Add(teamID, playerID, spec, n) end
	elseif cmd == "rem" then local id, f = SplitRef(rest); Remove(teamID, id, n, false, f)
	elseif cmd == "clear" then
		local id, f = SplitRef(rest)
		if f == 0 then      -- no lab named (e.g. a design is deleted): clear its entry on every line
			local q = queues[teamID] or {}
			for i = #q, 1, -1 do
				if q[i].tid == id then Refund(teamID, q[i]); table.remove(q, i); dirty[teamID] = true end
			end
		else Remove(teamID, id, 0, true, f) end
	elseif cmd == "hold" then
		local id, f = SplitRef(rest)
		local e = Find(teamID, id, f)
		if e then e.hold = not e.hold; dirty[teamID] = true end
	end
	return true
end

function gadget:GameFrame(frame)
	for teamID, q in pairs(queues) do
		-- on every line (a factory, or the team line of forge designs) the first entry that is not on hold is built
		local active, any = {}, nil
		for _, e in ipairs(q) do
			local ln = e.line or 0
			if not e.hold and not active[ln] then active[ln] = e
			elseif e ~= active[ln] and e.state ~= "w" then e.state = "w"; dirty[teamID] = true end
		end
		for ln, e in pairs(active) do
			if not FactoryReady(e.line) then
				-- the factory of this line is still being built: the entry waits for it
				-- (nothing is paid and no progress is made until the factory is done)
				if e.state ~= "p" then e.state = "p"; dirty[teamID] = true end
				any = true
			else
				local pr = e.price
				local dp = math.min(1 / (pr.build * FPS), 1 - e.prog)
				local m, en = pr.metal * dp, pr.energy * dp
				if Pay(teamID, m, en) then
					e.prog = e.prog + dp
					e.spentM, e.spentE = e.spentM + m, e.spentE + en
					e.lastOk = frame
					if e.state ~= "b" then e.state = "b"; dirty[teamID] = true end
					if e.prog >= 0.9999 then Finish(teamID, e, frame) end
				elseif frame - e.lastOk > 20 and e.state ~= "s" then
					e.state = "s"; dirty[teamID] = true
				end
				any = true
			end
		end
		if any and frame % 4 == 0 then dirty[teamID] = true end
		if dirty[teamID] then Publish(teamID) end
	end
end
