function gadget:GetInfo()
	return { name = "Voidborn mex yield", desc = "Gives metal extractors a fixed, map-scaled yield", author = "Voidborn", date = "2026", license = "GPL", layer = 0, enabled = true }
end
if not gadgetHandler:IsSyncedCode() then return false end

local BASE = 2.0           -- metal per second on a standard (value 5.1) spot
local STD = 5.1
local mexDefs = {}

function gadget:Initialize()
	for id, ud in pairs(UnitDefs) do
		if ud.customParams and ud.customParams.kind == "mex" then mexDefs[id] = true end
	end
end

local function Yield(unitID)
	local x, _, z = Spring.GetUnitPosition(unitID)
	local best = 0
	for dx = -1, 2 do
		for dz = -1, 2 do
			local v = Spring.GetMetalAmount(math.floor(x / 16) + dx, math.floor(z / 16) + dz) or 0
			if v > best then best = v end
		end
	end
	return BASE * math.min(best / STD, 3.0)
end

function gadget:UnitFinished(unitID, unitDefID)
	if mexDefs[unitDefID] then
		local y = Yield(unitID)
		Spring.SetUnitResourcing(unitID, "cmm", y)
	end
end
