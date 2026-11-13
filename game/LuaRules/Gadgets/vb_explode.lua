function gadget:GetInfo()
	return {
		name = "Voidborn mass detonation",
		desc = "Ctrl+B: the selected units blow themselves up; each blast radius is proportional to the unit's current health",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = 2, enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
local RADIUS_PER_HP  = 0.20   -- blast radius in elmos per health point  (230 hp -> 46, 1400 hp -> 280, 9500 hp -> 1900)
local DAMAGE_PER_HP  = 1.00   -- damage dealt at the centre = exploding unit's health * this
local EDGE_FRACTION  = 0.10   -- damage at the very edge of the blast, as a fraction of the centre damage (linear falloff)
local MAX_IDS        = 400    -- most unit ids accepted from one message

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local spGetUnitHealth, spGetUnitPosition, spGetUnitTeam = Spring.GetUnitHealth, Spring.GetUnitPosition, Spring.GetUnitTeam
	local spGetUnitsInSphere, spAddUnitDamage, spDestroyUnit = Spring.GetUnitsInSphere, Spring.AddUnitDamage, Spring.DestroyUnit
	local spSpawnCEG, spValidUnitID = Spring.SpawnCEG, Spring.ValidUnitID

	-- Spawn the visual: a CEG sized to the blast, scattered over the blast area for big ones
	local function Visual(x, y, z, radius)
		local ceg = radius < 90 and "vb_boom_small" or (radius < 350 and "vb_boom_med" or "vb_boom_big")
		local n = math.min(14, math.floor(radius / 120) + 1)
		for i = 1, n do
			local a, r = math.random() * 2 * math.pi, (i == 1 and 0 or math.sqrt(math.random()) * radius * 0.6)
			spSpawnCEG(ceg, x + math.cos(a) * r, y + (i == 1 and 0 or math.random() * radius * 0.2), z + math.sin(a) * r, 0, 1, 0, radius)
		end
		SendToUnsynced("vbboom", x, y, z, radius)
	end

	local function Detonate(ids, teamID)
		-- 1. snapshot every exploder (health and position are read before anything is destroyed)
		local blasts, batch = {}, {}
		for i = 1, math.min(#ids, MAX_IDS) do
			local id = ids[i]
			if spValidUnitID(id) and spGetUnitTeam(id) == teamID and not batch[id] then
				local hp = spGetUnitHealth(id)
				local _, _, _, mx, my, mz = spGetUnitPosition(id, true)   -- true = also return the mid-point
				if hp and hp > 0 and mx then
					batch[id] = true
					blasts[#blasts + 1] = { x = mx, y = my, z = mz, hp = hp, radius = hp * RADIUS_PER_HP }
				end
			end
		end
		if #blasts == 0 then return 0 end
		-- 2. remove the exploders without the engine's own death explosion (we make the blast), cleaned up immediately
		for id in pairs(batch) do spDestroyUnit(id, false, true, nil, true) end
		-- 3. apply every blast to the units still alive (exploders are gone, so they are not hit twice)
		for _, b in ipairs(blasts) do
			local r = b.radius
			for _, u in ipairs(spGetUnitsInSphere(b.x, b.y, b.z, r)) do
				if not batch[u] then
					local _, _, _, ux, uy, uz = spGetUnitPosition(u, true)
					if ux then
						local d = math.sqrt((ux - b.x) ^ 2 + (uy - b.y) ^ 2 + (uz - b.z) ^ 2)
						local f = EDGE_FRACTION + (1 - EDGE_FRACTION) * math.max(0, 1 - d / r)
						spAddUnitDamage(u, b.hp * DAMAGE_PER_HP * f, 0, -1)
					end
				end
			end
			Visual(b.x, b.y, b.z, r)
		end
		return #blasts
	end

	-- widget -> "vbexplode:12,45,78"   (the selected unit ids; the gadget checks they belong to the sender's team)
	function gadget:RecvLuaMsg(msg, playerID)
		if msg:sub(1, 10) ~= "vbexplode:" then return end
		local _, _, spec, teamID = Spring.GetPlayerInfo(playerID, false)
		if spec or not teamID then return end
		local ids = {}
		for n in msg:sub(11):gmatch("%d+") do ids[#ids + 1] = tonumber(n) end
		Detonate(ids, teamID)
		return true
	end

--------------------------------------------------------------------------------
else
--------------------------------------------------------------------------------
	function gadget:Initialize()
		gadgetHandler:AddSyncAction("vbboom", function(_, x, y, z, radius)
			Spring.PlaySoundFile("sounds/" .. (radius < 90 and "boom_small" or (radius < 350 and "boom_med" or "boom_big")) .. ".wav",
				1.0, x, y, z, 0, 0, 0, "sfx")
		end)
	end
	function gadget:Shutdown() gadgetHandler:RemoveSyncAction("vbboom") end
end
