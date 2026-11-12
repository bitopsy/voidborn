function gadget:GetInfo()
	return { name = "Voidborn commander end", desc = "A team without a commander is eliminated", author = "Voidborn", date = "2026", license = "GPL", layer = 0, enabled = true }
end
if not gadgetHandler:IsSyncedCode() then return false end

local enabled = true
local commanders = {}   -- defID -> true

function gadget:Initialize()
	local opt = Spring.GetModOptions().commander_ends
	if opt == "0" or opt == 0 or opt == false then enabled = false end
	for id, ud in pairs(UnitDefs) do
		if ud.customParams and ud.customParams.iscommander == "true" then commanders[id] = true end
	end
end

local function CountCommanders(teamID)
	local n = 0
	for id in pairs(commanders) do n = n + Spring.GetTeamUnitDefCount(teamID, id) end
	return n
end

local pending = {}
function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	if enabled and commanders[unitDefID] then pending[teamID] = Spring.GetGameFrame() + 2 end
end

function gadget:GameFrame(f)
	for teamID, when in pairs(pending) do
		if f >= when then
			pending[teamID] = nil
			if CountCommanders(teamID) == 0 and not select(3, Spring.GetTeamInfo(teamID, false)) then
				Spring.Echo("[Voidborn] Team " .. teamID .. " lost its commander and is eliminated")
				for _, u in ipairs(Spring.GetTeamUnits(teamID)) do Spring.DestroyUnit(u, true, false) end
				Spring.KillTeam(teamID)
			end
		end
	end
end
