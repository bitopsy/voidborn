function gadget:GetInfo()
	return { name = "Voidborn Factory Upgrade", desc = "Upgrade a factory in place: tier 1 -> tier 2 (unlocks the T2 units and the unit forge) and tier 2 -> tier 3 (unlocks the slow T3 heavies)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -1, enabled = true }
end

if not gadgetHandler:IsSyncedCode() then return end

--------------------------------------------------------------------------------
-- What this does
--   Every finished tier 1 factory (a unit def with customParams.upgrade_to) gets an order button
--   "Upgrade T2".  Pressing it starts the upgrade: the team pays the cost (customParams.upgrade_metal /
--   upgrade_energy) a little every frame over customParams.upgrade_seconds, exactly like a queued unit.
--   When the team cannot pay, the upgrade stalls.  Pressing the button again cancels it and refunds
--   what was paid.  While the factory is upgrading its production lines wait (the queue gadget asks
--   GG.VB_FactoryBusy) and nothing else can be built there.
--
--   When the upgrade is done the factory is swapped for the tier 2 factory (customParams.upgrade_to):
--   same place, same facing, same health fraction, and the production queue of the old factory is
--   handed to the new one (GG.VB_FactorySwap in vb_dev_queue.lua).  A factory that dies while it is
--   upgrading loses what was paid, like any structure that is destroyed under construction.
--
--   Having a finished tier 2 factory (customParams.tier == "2") is what unlocks the unit forge: see
--   GG.VB_ForgeUnlocked(teamID).  It is published to the UI as
--       team rules param   "vb_t2"      number of finished T2 factories of the team   (allied)
--       game rules param   "vb_t2_gate" 1 = the forge needs a T2 factory, 0 = modoption vb_forge_needs_t2 is off
--       team rules param   "vbu_list"   "<unitID>:<progress 0..1000>:<b|s>;..."  the upgrades under way  (allied)
--   Cheats (/cheat) always unlock the forge, so the sandbox keeps working.
--------------------------------------------------------------------------------

local FPS = 30
local CMD_UPGRADE = 34920

local upgradeDefs = {}      -- tier 1 factory defID -> { to = defID, metal, energy, seconds, name }
local t2Defs = {}           -- defIDs of tier 2 and tier 3 factories (a T3 lab keeps the forge unlocked)
local t3Defs = {}           -- defIDs of tier 3 factories
local t2Units = {}          -- teamID -> { [unitID] = true } finished tier 2 or tier 3 factories
local t3Units = {}          -- teamID -> { [unitID] = true } finished tier 3 factories
local upg = {}              -- unitID -> upgrade state
local dirty = {}            -- teamID -> true when "vbu_list" has to be rewritten

local gate = true           -- does the forge need a tier 2 factory?

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function Num(v, d) v = tonumber(v); if v and v > 0 then return v end return d end

local function Say(teamID, msg) Spring.SendMessageToTeam(teamID, "[VB] " .. msg) end

local function Count(teamID)
	local n = 0
	for _ in pairs(t2Units[teamID] or {}) do n = n + 1 end
	return n
end

local function Count3(teamID)
	local n = 0
	for _ in pairs(t3Units[teamID] or {}) do n = n + 1 end
	return n
end

local function PublishCount(teamID)
	Spring.SetTeamRulesParam(teamID, "vb_t2", Count(teamID), { allied = true })      -- labs of tier 2 or higher
	Spring.SetTeamRulesParam(teamID, "vb_t3", Count3(teamID), { allied = true })     -- labs of tier 3
end

local function Publish(teamID)
	local parts = {}
	for uid, st in pairs(upg) do
		if st.team == teamID then parts[#parts + 1] = string.format("%d:%d:%s", uid, math.floor(st.prog * 1000 + 0.5), st.stalled and "s" or "b") end
	end
	table.sort(parts)
	Spring.SetTeamRulesParam(teamID, "vbu_list", table.concat(parts, ";"), { allied = true })
	dirty[teamID] = nil
end

-- the unit forge (and the T2 roster) is unlocked for a team that has a finished tier 2 factory
function GG.VB_ForgeUnlocked(teamID)
	if not gate then return true end
	if Spring.IsCheatingEnabled and Spring.IsCheatingEnabled() then return true end
	return Count(teamID) > 0
end

-- is this factory busy being upgraded?  (its production lines wait meanwhile)
function GG.VB_FactoryBusy(unitID) return upg[unitID] ~= nil end

local function Pay(teamID, metal, energy)
	local m = Spring.GetTeamResources(teamID, "metal") or 0
	local e = Spring.GetTeamResources(teamID, "energy") or 0
	if m < metal or e < energy then return false end
	if metal > 0 then Spring.UseTeamResource(teamID, "metal", metal) end
	if energy > 0 then Spring.UseTeamResource(teamID, "energy", energy) end
	return true
end

--------------------------------------------------------------------------------
-- the order button
--------------------------------------------------------------------------------
local function Tooltip(rule)
	local what = rule.tier >= 3 and "Unlocks the slow T3 heavy." or "Unlocks the T2 units and the unit forge."
	return string.format("Upgrade this factory to Tier %d: %d metal + %d energy, %d s. %s Press again to cancel.",
		rule.tier, rule.metal, rule.energy, rule.seconds, what)
end

local function CmdDesc(rule)
	return { id = CMD_UPGRADE, type = CMDTYPE.ICON, name = "Upgrade T" .. rule.tier, action = "vbupgrade", tooltip = Tooltip(rule), params = {} }
end

local function AddButton(unitID, defID)
	local rule = upgradeDefs[defID]
	if not rule or Spring.FindUnitCmdDesc(unitID, CMD_UPGRADE) then return end
	Spring.InsertUnitCmdDesc(unitID, CmdDesc(rule))
end

local function SetLabel(unitID, st)
	local idx = Spring.FindUnitCmdDesc(unitID, CMD_UPGRADE)
	if not idx then return end
	local rule = upgradeDefs[st.def]
	if not rule then return end
	local label, tip
	if st.stalled then
		label = string.format("T%d %d%% stall", rule.tier, math.floor(st.prog * 100))
		tip = string.format("Upgrade to Tier %d is STALLED: not enough metal or energy. Press to cancel and get the payment back.", rule.tier)
	else
		label = string.format("T%d %d%%", rule.tier, math.floor(st.prog * 100))
		tip = string.format("Upgrading to Tier %d. Press to cancel and get the payment back.", rule.tier)
	end
	Spring.EditUnitCmdDesc(unitID, idx, { name = label, tooltip = tip })
end

local function ResetButton(unitID, defID)
	local idx = Spring.FindUnitCmdDesc(unitID, CMD_UPGRADE)
	local rule = upgradeDefs[defID]
	if idx and rule then Spring.EditUnitCmdDesc(unitID, idx, { name = "Upgrade T" .. rule.tier, tooltip = Tooltip(rule) }) end
end

--------------------------------------------------------------------------------
-- start / cancel / finish
--------------------------------------------------------------------------------
local function Start(unitID, defID, teamID)
	local rule = upgradeDefs[defID]
	if not rule then return end
	if Spring.GetUnitIsBeingBuilt and Spring.GetUnitIsBeingBuilt(unitID) then
		Say(teamID, "the factory has to be finished before it can be upgraded"); return
	end
	upg[unitID] = { team = teamID, def = defID, rule = rule, prog = 0, spentM = 0, spentE = 0, lastOk = Spring.GetGameFrame(), stalled = false }
	Spring.SetUnitRulesParam(unitID, "vbu", 0, { allied = true })
	dirty[teamID] = true
	SetLabel(unitID, upg[unitID])
	Say(teamID, string.format("upgrading %s to Tier %d (%d metal + %d energy over %d s)", rule.name, rule.tier, rule.metal, rule.energy, rule.seconds))
end

local function Cancel(unitID, why)
	local st = upg[unitID]
	if not st then return end
	if st.spentM > 0 then Spring.AddTeamResource(st.team, "metal", st.spentM) end
	if st.spentE > 0 then Spring.AddTeamResource(st.team, "energy", st.spentE) end
	upg[unitID] = nil
	dirty[st.team] = true
	Spring.SetUnitRulesParam(unitID, "vbu", nil)
	if Spring.ValidUnitID(unitID) then ResetButton(unitID, st.def) end
	Say(st.team, why or string.format("Tier %d upgrade cancelled, the payment was refunded", st.rule.tier))
end

local function Complete(unitID)
	local st = upg[unitID]
	if not st then return end
	local teamID, oldDef, newDef = st.team, st.def, st.rule.to
	local x, y, z = Spring.GetUnitPosition(unitID)
	local facing = Spring.GetUnitBuildFacing and Spring.GetUnitBuildFacing(unitID) or 0
	local hp, maxHp = Spring.GetUnitHealth(unitID)
	local frac = (hp and maxHp and maxHp > 0) and math.max(0.05, math.min(1, hp / maxHp)) or 1
	upg[unitID] = nil
	dirty[teamID] = true

	-- the old factory leaves without a wreck or a blast; the queue gadget must not refund its lines
	GG.VB_swapping = unitID
	Spring.DestroyUnit(unitID, false, true, nil, true)
	local newID = Spring.CreateUnit(newDef, x, y, z, facing, teamID)
	if not newID then
		newID = Spring.CreateUnit(oldDef, x, y, z, facing, teamID)      -- put the old factory back: never lose it
		GG.VB_swapping = nil
		if st.spentM > 0 then Spring.AddTeamResource(teamID, "metal", st.spentM) end
		if st.spentE > 0 then Spring.AddTeamResource(teamID, "energy", st.spentE) end
		if newID then
			Spring.SetUnitHealth(newID, (select(2, Spring.GetUnitHealth(newID)) or 1) * frac)
			if GG.VB_FactorySwap then GG.VB_FactorySwap(unitID, newID) end
		end
		Say(teamID, string.format("the Tier %d upgrade failed (something blocks the spot); the payment was refunded", st.rule.tier))
		return
	end
	GG.VB_swapping = nil
	local _, newMax = Spring.GetUnitHealth(newID)
	if newMax then Spring.SetUnitHealth(newID, newMax * frac) end
	if GG.VB_FactorySwap then GG.VB_FactorySwap(unitID, newID) end
	local tier = st.rule.tier
	Say(teamID, string.format("%s online: %s", UnitDefs[newDef].humanName or UnitDefs[newDef].name,
		tier >= 3 and "the T3 heavy is unlocked" or "T2 units and the unit forge are unlocked"))
end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
function gadget:Initialize()
	local v = Spring.GetModOptions().vb_forge_needs_t2
	gate = not (v == "0" or v == 0 or v == false or v == "false")
	Spring.SetGameRulesParam("vb_t2_gate", gate and 1 or 0, { public = true })
	for id, ud in pairs(UnitDefs) do
		if type(id) == "number" then
			local cp = ud.customParams or {}
			if cp.upgrade_to and UnitDefNames[cp.upgrade_to] then
				upgradeDefs[id] = { to = UnitDefNames[cp.upgrade_to].id, metal = Num(cp.upgrade_metal, 2000), energy = Num(cp.upgrade_energy, 2800),
					seconds = Num(cp.upgrade_seconds, 45), name = ud.humanName or ud.name,
					tier = math.floor(Num(cp.upgrade_tier, 2)) }
			end
			if cp.kind == "fac2" or cp.kind == "fac3" then t2Defs[id] = true end
			if cp.kind == "fac3" then t3Defs[id] = true end
		end
	end
	-- a game that is reloaded (or this gadget switched on late): pick up the factories that already stand
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local defID, teamID = Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID)
		if not (Spring.GetUnitIsBeingBuilt and Spring.GetUnitIsBeingBuilt(unitID)) then
			if upgradeDefs[defID] then AddButton(unitID, defID) end
			if t2Defs[defID] then t2Units[teamID] = t2Units[teamID] or {}; t2Units[teamID][unitID] = true end
			if t3Defs[defID] then t3Units[teamID] = t3Units[teamID] or {}; t3Units[teamID][unitID] = true end
		end
	end
	for _, teamID in ipairs(Spring.GetTeamList()) do PublishCount(teamID); Publish(teamID) end
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	if upgradeDefs[unitDefID] then AddButton(unitID, unitDefID) end
	if t2Defs[unitDefID] then
		t2Units[teamID] = t2Units[teamID] or {}
		t2Units[teamID][unitID] = true
		if t3Defs[unitDefID] then t3Units[teamID] = t3Units[teamID] or {}; t3Units[teamID][unitID] = true end
		PublishCount(teamID)
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	if upg[unitID] then       -- destroyed while upgrading: what was paid is lost
		local st = upg[unitID]
		upg[unitID] = nil
		dirty[st.team] = true
	end
	if t2Defs[unitDefID] and t2Units[teamID] and t2Units[teamID][unitID] then
		t2Units[teamID][unitID] = nil
		if t3Units[teamID] then t3Units[teamID][unitID] = nil end
		PublishCount(teamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if upg[unitID] then Cancel(unitID, "the factory changed owner: its upgrade was cancelled") end
	if t2Defs[unitDefID] then
		if t2Units[oldTeam] then t2Units[oldTeam][unitID] = nil end
		if t3Units[oldTeam] then t3Units[oldTeam][unitID] = nil end
		t2Units[newTeam] = t2Units[newTeam] or {}
		t2Units[newTeam][unitID] = true
		if t3Defs[unitDefID] then t3Units[newTeam] = t3Units[newTeam] or {}; t3Units[newTeam][unitID] = true end
		PublishCount(oldTeam); PublishCount(newTeam)
	end
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID)
	if cmdID ~= CMD_UPGRADE then return true end
	if upg[unitID] then Cancel(unitID) else Start(unitID, unitDefID, teamID) end
	return false          -- handled here: the order never reaches the factory's own queue
end

function gadget:GameFrame(frame)
	for unitID, st in pairs(upg) do
		if not Spring.ValidUnitID(unitID) then
			upg[unitID] = nil; dirty[st.team] = true
		else
			local rule = st.rule
			local dp = math.min(1 / (rule.seconds * FPS), 1 - st.prog)
			local m, e = rule.metal * dp, rule.energy * dp
			if Pay(st.team, m, e) then
				st.prog = st.prog + dp
				st.spentM, st.spentE = st.spentM + m, st.spentE + e
				st.lastOk = frame
				if st.stalled then st.stalled = false; dirty[st.team] = true; SetLabel(unitID, st) end
				if st.prog >= 0.9999 then
					Complete(unitID)
				elseif frame % 6 == 0 then
					Spring.SetUnitRulesParam(unitID, "vbu", math.floor(st.prog * 1000 + 0.5), { allied = true })
					dirty[st.team] = true
					SetLabel(unitID, st)
				end
			elseif frame - st.lastOk > 20 and not st.stalled then
				st.stalled = true; dirty[st.team] = true; SetLabel(unitID, st)
			end
		end
	end
	for teamID in pairs(dirty) do Publish(teamID) end
end
