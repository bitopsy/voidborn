function gadget:GetInfo()
	return {
		name = "Voidborn mass detonation",
		desc = "Ctrl+B: the selected units blow themselves up after a five second countdown; each blast radius is proportional to the unit's current health",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 2, enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
local RADIUS_PER_HP  = 0.20   -- blast radius in elmos per health point  (230 hp -> 46, 1400 hp -> 280, 9500 hp -> 1900)
local DAMAGE_PER_HP  = 1.00   -- damage dealt at the centre = exploding unit's health * this
local EDGE_FRACTION  = 0.10   -- damage at the very edge of the blast, as a fraction of the centre damage (linear falloff)
local MAX_IDS        = 400    -- most unit ids accepted from one message
local COUNTDOWN      = 5      -- seconds between the order and the blast

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local spGetUnitHealth, spGetUnitPosition, spGetUnitTeam = Spring.GetUnitHealth, Spring.GetUnitPosition, Spring.GetUnitTeam
	local spGetUnitsInSphere, spAddUnitDamage, spDestroyUnit = Spring.GetUnitsInSphere, Spring.AddUnitDamage, Spring.DestroyUnit
	local spSpawnCEG, spValidUnitID = Spring.SpawnCEG, Spring.ValidUnitID

	local armed = {}         -- unitID -> the frame the blast goes off
	local armedTeam = {}     -- teamID of the player that armed them

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
	-- the blast does not go off right away: the units are armed for five seconds
	function gadget:RecvLuaMsg(msg, playerID)
		if msg == "vbexplode:cancel" then
			local _, _, spec, teamID = Spring.GetPlayerInfo(playerID, false)
			if spec or not teamID then return end
			local n = 0
			for id, t in pairs(armedTeam) do
				if t == teamID then armed[id] = nil; armedTeam[id] = nil; n = n + 1 end
			end
			if n > 0 then
				SendToUnsynced("vbarm", "cancel")
				Spring.SendMessageToPlayer(playerID, "[VB] detonation cancelled")
			end
			return true
		end
		if msg:sub(1, 10) ~= "vbexplode:" then return end
		local _, _, spec, teamID = Spring.GetPlayerInfo(playerID, false)
		if spec or not teamID then return end
		local ids = {}
		for n in msg:sub(11):gmatch("%d+") do ids[#ids + 1] = tonumber(n) end
		local frame = Spring.GetGameFrame()
		local count = 0
		for _, id in ipairs(ids) do
			if spValidUnitID(id) and spGetUnitTeam(id) == teamID then
				armed[id] = frame + COUNTDOWN * 30
				armedTeam[id] = teamID
				SendToUnsynced("vbarm", "arm", id, armed[id])
				count = count + 1
			end
		end
		if count > 0 then
			Spring.SendMessageToPlayer(playerID, "[VB] " .. count .. " unit(s) detonate in " .. COUNTDOWN .. " seconds")
		end
		return true
	end

	-- the clock runs out
	function gadget:Update()
		local frame = Spring.GetGameFrame()
		local ready = {}
		for id, at in pairs(armed) do
			if frame >= at then
				ready[#ready + 1] = id
			elseif not spValidUnitID(id) then
				armed[id] = nil
				armedTeam[id] = nil
			end
		end
		if #ready > 0 then
			-- group the ready units by team, they all belong to one player
			local byTeam = {}
			for _, id in ipairs(ready) do
				local t = armedTeam[id] or spGetUnitTeam(id)
				armed[id] = nil
				armedTeam[id] = nil
				if t then byTeam[t] = byTeam[t] or {}; byTeam[t][#byTeam[t] + 1] = id end
			end
			for t, ids in pairs(byTeam) do Detonate(ids, t) end
		end
	end

--------------------------------------------------------------------------------
else
--------------------------------------------------------------------------------
	local armed = {}       -- unitID -> the frame the blast goes off (for the warning ring)

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("vbboom", function(_, x, y, z, radius)
			Spring.PlaySoundFile("sounds/" .. (radius < 90 and "boom_small" or (radius < 350 and "boom_med" or "boom_big")) .. ".wav",
				1.0, x, y, z, 0, 0, 0, "sfx")
		end)
		gadgetHandler:AddSyncAction("vbarm", function(_, what, id, frame)
			if what == "cancel" then
				armed = {}
			else
				armed[id] = frame
			end
		end)
	end
	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("vbboom")
		gadgetHandler:RemoveSyncAction("vbarm")
	end

	-- a pulsing warning ring under every unit that is about to go off
	function gadget:DrawWorld()
		if next(armed) == nil then return end
		local frame = Spring.GetGameFrame()
		local t = Spring.GetLastUpdateSeconds()
		local left = 0
		for id, at in pairs(armed) do
			local x, y, z = Spring.GetUnitPosition(id)
			if x then
				left = math.max(left, at - frame)
				local pulse = 0.5 + 0.5 * math.sin(t * (6 + (at - frame) * 0.5))
				local r = 26 + pulse * 8
				gl.Color(1, 0.35 + pulse * 0.4, 0.15, 0.55 + pulse * 0.35)
				gl.BeginEnd(GL.TRIANGLE_STRIP, function()
					for i = 0, 32 do
						local a = i / 32 * 2 * math.pi
						local c, s = math.cos(a), math.sin(a)
						gl.Vertex(x + c * (r - 3), y + 1, z + s * (r - 3))
						gl.Vertex(x + c * (r + 3), y + 1, z + s * (r + 3))
					end
				end)
			else
				armed[id] = nil
			end
		end
	end
end
