-- Voidborn: cloak toggle for commanders and constructors, drained by this gadget.
--
-- The engine's own cloak button (and its upkeep) is replaced by a "Cloak" toggle in the order
-- menu / build panel (key K).  While it is on, the unit is cloaked and the team pays energy per
-- second:  commanders 250 E/s,  constructors 100 E/s.
--
-- The cloak drops when: the team runs out of energy, the unit dies, it fires a manual gun
-- (see vb_manualfire.lua) or it is given an explicit attack order.  While cloaked the unit is put
-- on "hold fire" so it does not open fire by itself and give itself away; the old fire state is
-- restored when the cloak drops.
--
--   game/LuaRules/Gadgets/vb_cloak.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Cloak", desc = "Cloak toggle: commanders 250 E/s, constructors 100 E/s",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local COST_BY_KIND = { com = 250, con = 100 }   -- energy per second, by customParams.kind
local FPS = 30
local CMD_CLOAK = 35002
-- SetUnitCloak level: 3 = free (we charge the energy ourselves) and no decloaking by the engine
-- (proximity / timeout), except while stunned.  A plain boolean only sets the engine's "want cloak"
-- flag, which the engine then undoes whenever the unit fires or an enemy is near.
local CLOAK_LEVEL = 3

local cloakCost = {}      -- unitDefID -> energy per second
local hasWeapons = {}     -- unitDefID -> true
local cloaked = {}        -- unitID -> true
local savedFire = {}      -- unitID -> fire state to restore

local function Say(teamID, msg) Spring.SendMessageToTeam(teamID, "[VB] " .. msg) end

local function GetFireState(uid)
	local st = Spring.GetUnitStates(uid)
	if type(st) == "table" then return st.firestate end
	return st
end

local function SetCloak(uid, on)
	local defID = Spring.GetUnitDefID(uid)
	if on then
		if not cloaked[uid] and hasWeapons[defID] then
			savedFire[uid] = GetFireState(uid)
			Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { 0 }, 0)      -- hold fire while hidden
		end
		cloaked[uid] = true
		Spring.SetUnitCloak(uid, CLOAK_LEVEL, 0)
	else
		cloaked[uid] = nil
		Spring.SetUnitCloak(uid, 0)        -- clears the level set above ...
		Spring.SetUnitCloak(uid, false)    -- ... and the engine's own want-cloak flag
		local fs = savedFire[uid]
		savedFire[uid] = nil
		if fs and Spring.ValidUnitID(uid) then Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { fs }, 0) end
	end
	local i = Spring.FindUnitCmdDesc(uid, CMD_CLOAK)
	if i then
		Spring.EditUnitCmdDesc(uid, i, { params = { on and "1" or "0", "Cloak off", "Cloak on" } })
	end
end

GG.VBCloak = { Off = function(uid) if cloaked[uid] then SetCloak(uid, false) end end }

function gadget:Initialize()
	for defID, ud in pairs(UnitDefs) do
		local kind = ud.customParams and ud.customParams.kind
		if COST_BY_KIND[kind] then cloakCost[defID] = COST_BY_KIND[kind] end
		if ud.weapons and #ud.weapons > 0 then hasWeapons[defID] = true end
	end
	for _, uid in ipairs(Spring.GetAllUnits()) do gadget:UnitCreated(uid, Spring.GetUnitDefID(uid)) end
end

function gadget:Shutdown() GG.VBCloak = nil end

function gadget:UnitCreated(uid, defID)
	local cost = cloakCost[defID]
	if not cost then return end
	-- the engine's own Cloak button goes: ours is the only one
	local i = Spring.FindUnitCmdDesc(uid, CMD.CLOAK)
	if i then Spring.RemoveUnitCmdDesc(uid, i) end
	if Spring.FindUnitCmdDesc(uid, CMD_CLOAK) then return end
	Spring.InsertUnitCmdDesc(uid, {
		id = CMD_CLOAK, type = CMDTYPE.ICON_MODE, name = "Cloak", action = "vbcloak",
		queueing = false, hidden = false,
		tooltip = "Cloak (K): hides this unit, costs " .. cost .. " energy per second",
		params = { "0", "Cloak off", "Cloak on" },
	})
end

function gadget:UnitDestroyed(uid) cloaked[uid] = nil; savedFire[uid] = nil end
function gadget:UnitTaken(uid) if cloaked[uid] then SetCloak(uid, false) end end

function gadget:AllowCommand(uid, defID, teamID, cmdID, params)
	if cmdID == CMD.ATTACK then
		if cloaked[uid] then SetCloak(uid, false) end     -- an attack order gives the unit away
		return true
	end
	if cmdID ~= CMD_CLOAK then return true end
	local cost = cloakCost[defID]
	if not cost or Spring.GetUnitIsBeingBuilt(uid) then return false end
	local want = params and tonumber(params[1]) == 1
	if want then
		local cur = Spring.GetTeamResources(teamID, "energy")
		if not cur or cur < cost / FPS then Say(teamID, "Cloak: not enough energy") return false end
	end
	if want ~= (cloaked[uid] == true) then SetCloak(uid, want) end
	return false
end

function gadget:GameFrame()
	for uid in pairs(cloaked) do
		if not Spring.ValidUnitID(uid) or Spring.GetUnitIsDead(uid) then
			cloaked[uid] = nil; savedFire[uid] = nil
		else
			local teamID = Spring.GetUnitTeam(uid)
			local perFrame = cloakCost[Spring.GetUnitDefID(uid)] / FPS
			if not Spring.UseTeamResource(teamID, "energy", perFrame) then
				SetCloak(uid, false)
				Say(teamID, "Cloak: out of energy")
			end
		end
	end
end
