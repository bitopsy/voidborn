-- Voidborn: commander cloak, drained by this gadget.
--
-- The engine's own cloak button (and its upkeep) is replaced by a "Cloak" toggle in the order
-- menu (key K).  While it is on, the commander is cloaked and the team pays COST energy per
-- second.  Out of energy, stunned-to-death or dead: the cloak drops.  Firing the D-gun / Q-gun
-- (see vb_manualfire.lua) drops it too.
--
--   game/LuaRules/Gadgets/vb_cloak.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Cloak", desc = "Commander cloak toggle that drains 300 energy per second",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local COST = 300          -- energy per second while cloaked
local FPS = 30
local CMD_CLOAK = 35002

local cloakDefs = {}      -- unitDefID -> true
local cloaked = {}        -- unitID -> true

local function Say(teamID, msg) Spring.SendMessageToTeam(teamID, "[VB] " .. msg) end

local function SetCloak(uid, on)
	cloaked[uid] = on or nil
	Spring.SetUnitCloak(uid, on and true or false)
	local i = Spring.FindUnitCmdDesc(uid, CMD_CLOAK)
	if i then
		Spring.EditUnitCmdDesc(uid, i, { params = { on and "1" or "0", "Cloak off", "Cloak on" } })
	end
end

GG.VBCloak = { Off = function(uid) if cloaked[uid] then SetCloak(uid, false) end end }

function gadget:Initialize()
	for defID, ud in pairs(UnitDefs) do
		if ud.canCloak then cloakDefs[defID] = true end
	end
	for _, uid in ipairs(Spring.GetAllUnits()) do gadget:UnitCreated(uid, Spring.GetUnitDefID(uid)) end
end

function gadget:Shutdown() GG.VBCloak = nil end

function gadget:UnitCreated(uid, defID)
	if not cloakDefs[defID] then return end
	-- the engine's own Cloak button goes: ours is the only one
	local i = Spring.FindUnitCmdDesc(uid, CMD.CLOAK)
	if i then Spring.RemoveUnitCmdDesc(uid, i) end
	Spring.InsertUnitCmdDesc(uid, {
		id = CMD_CLOAK, type = CMDTYPE.ICON_MODE, name = "Cloak", action = "vbcloak",
		tooltip = "Cloak (K): hides the commander, costs " .. COST .. " energy per second",
		params = { "0", "Cloak off", "Cloak on" },
	})
end

function gadget:UnitDestroyed(uid) cloaked[uid] = nil end

function gadget:AllowCommand(uid, defID, teamID, cmdID, params)
	if cmdID ~= CMD_CLOAK then return true end
	if not cloakDefs[defID] then return false end
	local want = params and params[1] == 1
	if want then
		local cur = Spring.GetTeamResources(teamID, "energy")
		if not cur or cur < COST / FPS then Say(teamID, "Cloak: not enough energy") return false end
	end
	SetCloak(uid, want)
	return false
end

function gadget:GameFrame()
	local perFrame = COST / FPS
	for uid in pairs(cloaked) do
		if not Spring.ValidUnitID(uid) or Spring.GetUnitIsDead(uid) then
			cloaked[uid] = nil
		elseif not Spring.UseTeamResource(Spring.GetUnitTeam(uid), "energy", perFrame) then
			SetCloak(uid, false)
			Say(Spring.GetUnitTeam(uid), "Cloak: out of energy")
		end
	end
end
