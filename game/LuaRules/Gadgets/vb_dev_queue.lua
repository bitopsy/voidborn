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
--   Every team has ONE production line.  The first entry that is not on hold is
--   built.  While it is built the gadget pays its metal and energy a little every
--   frame; when the team cannot pay, the unit stalls.  Cancelling refunds what was
--   already paid.  When a unit is finished, the gadget hands "vbdev:<spec>" (count=1)
--   to the existing vb_dev_units gadget, which creates the unit exactly as before.
--   The state is published to the owner as the team rules param "vbq":
--       <id>|<units left>|<progress 0..1000>|<state b/s/w/h>;...
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
			return { metal = tonumber(p.metal) or 0, energy = tonumber(p.energy) or 0, build = math.max(1, tonumber(p.build) or 30) }
		end
	end
	local function Pick(v, base) v = tonumber(v) or 0; if v > 0 then return v end return base or 0 end
	return { metal = Pick(s.metal, ud.metalCost), energy = Pick(s.energy, ud.energyCost), build = math.max(1, Pick(s.buildtime, 30)) }
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
		parts[i] = string.format("%s|%d|%d|%s", e.tid, e.n, math.floor(e.prog * 1000 + 0.5), e.hold and "h" or e.state)
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

local function Find(teamID, tid)
	for i, e in ipairs(queues[teamID] or {}) do
		if e.tid == tid then return e, i end
	end
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
	spec.team = teamID
	spec.x, spec.z = nil, nil
	n = math.max(1, math.min(MAX_QUEUE, math.floor(tonumber(n) or 1)))
	local q = queues[teamID]
	if not q then q = {}; queues[teamID] = q end
	local e = Find(teamID, tid)
	if e then
		e.n = math.min(MAX_QUEUE, e.n + n)
		if e.prog == 0 then          -- nothing paid yet: take the newest version of the design
			e.spec, e.price = spec, Price(spec, ud)
		end
	else
		q[#q + 1] = { tid = tid, spec = spec, price = Price(spec, ud), n = n, prog = 0, spentM = 0, spentE = 0,
			hold = false, state = "w", lastOk = 0, playerID = playerID }
	end
	dirty[teamID] = true
end

local function Remove(teamID, tid, n, all)
	local e, i = Find(teamID, tid)
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
	local spec = {}
	for k, v in pairs(e.spec) do spec[k] = v end
	spec.count, spec.team = 1, teamID
	e.n, e.prog, e.spentM, e.spentE = e.n - 1, 0, 0, 0
	if e.n <= 0 then
		local _, i = Find(teamID, e.tid)
		if i then table.remove(queues[teamID], i) end
	end
	-- the existing creation gadget does the actual spawning
	local ok, err = pcall(function() return gadgetHandler:RecvLuaMsg("vbdev:" .. Ser(spec), e.playerID) end)
	if not ok then Spring.Echo("[VB] queue: could not hand the unit to vb_dev_units: " .. tostring(err)) end
	dirty[teamID] = true
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
	elseif cmd == "rem" then Remove(teamID, SafeId(rest), n)
	elseif cmd == "clear" then Remove(teamID, SafeId(rest), 0, true)
	elseif cmd == "hold" then
		local e = Find(teamID, SafeId(rest))
		if e then e.hold = not e.hold; dirty[teamID] = true end
	end
	return true
end

function gadget:GameFrame(frame)
	for teamID, q in pairs(queues) do
		-- the first entry that is not on hold is the one being built
		local active
		for _, e in ipairs(q) do
			if not e.hold and not active then active = e
			elseif e.state ~= "w" and e ~= active then e.state = "w" end
		end
		if active then
			local pr = active.price
			local dp = math.min(1 / (pr.build * FPS), 1 - active.prog)
			local m, en = pr.metal * dp, pr.energy * dp
			if Pay(teamID, m, en) then
				active.prog = active.prog + dp
				active.spentM, active.spentE = active.spentM + m, active.spentE + en
				active.lastOk = frame
				if active.state ~= "b" then active.state = "b"; dirty[teamID] = true end
				if active.prog >= 0.9999 then Finish(teamID, active, frame) end
			elseif frame - active.lastOk > 20 and active.state ~= "s" then
				active.state = "s"; dirty[teamID] = true
			end
			if frame % 4 == 0 then dirty[teamID] = true end
		end
		if dirty[teamID] then Publish(teamID) end
	end
end
