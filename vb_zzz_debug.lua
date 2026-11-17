-- TEMPORARY debug gadget (not part of the release): checks the cloak command plumbing.
function gadget:GetInfo()
	return {
		name = "VB Debug Cloak", desc = "temporary debug for the cloak command",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local testUID = nil
local frames = 0

function gadget:Initialize()
	Spring.Echo("[DBG] --- cloak debug start (Initialize) ---")
	Spring.Echo("[DBG] GG.VBCloak=" .. tostring(GG.VBCloak))
end

function gadget:Update()
	frames = frames + 1
	if frames == 2 then
		Spring.Echo("[DBG] frame 2: GG.VBCloak=" .. tostring(GG.VBCloak))
		testUID = Spring.CreateUnit("ch_hierophant", 0, 0, 0, 0, 0)
		Spring.Echo("[DBG] created unit id=" .. tostring(testUID))
		if testUID then
			Spring.Echo("[DBG] FindUnitCmdDesc(35002) = " .. tostring(Spring.FindUnitCmdDesc(testUID, 35002)))
			Spring.Echo("[DBG] FindUnitCmdDesc(CMD.CLOAK=" .. tostring(CMD.CLOAK) .. ") = " .. tostring(Spring.FindUnitCmdDesc(testUID, CMD.CLOAK)))
		end
	end
	if frames == 4 then
		Spring.Echo("[DBG] frame 4: FindUnitCmdDesc(35002) = " .. tostring(Spring.FindUnitCmdDesc(testUID, 35002)))
		Spring.Echo("[DBG] frame 4: FindUnitCmdDesc(CMD.CLOAK) = " .. tostring(Spring.FindUnitCmdDesc(testUID, CMD.CLOAK)))
		local cmds = Spring.GetUnitCmdDescs(testUID, 1, 60) or {}
		for k, c in ipairs(cmds) do
			if c.id == 35002 or c.id == CMD.CLOAK then
				Spring.Echo("[DBG] cmd [" .. k .. "] id=" .. tostring(c.id) .. " action=" .. tostring(c.action) .. " params=" .. tostring(c.params and c.params[1]))
			end
		end
		-- the order path the K hotkey uses
		Spring.GiveOrderToUnit(testUID, 35002, { 1 }, {})
		Spring.Echo("[DBG] GiveOrderToUnit(35002, {1}) sent")
	end
	if frames == 7 then
		Spring.Echo("[DBG] after 3 frames: GetUnitIsCloaked=" .. tostring(Spring.GetUnitIsCloaked(testUID)))
		local st = Spring.GetUnitStates(testUID)
		if type(st) == "table" then Spring.Echo("[DBG] states now: firestate=" .. tostring(st.firestate) .. " cloak=" .. tostring(st.cloak)) end
		local cmds = Spring.GetUnitCmdDescs(testUID, 1, 60) or {}
		for k, c in ipairs(cmds) do
			if c.id == 35002 then Spring.Echo("[DBG] cloak desc params now = " .. tostring(c.params and c.params[1])) end
		end
		Spring.Echo("[DBG] --- cloak debug end ---")
		Spring.DestroyUnit(testUID)
	end
end
