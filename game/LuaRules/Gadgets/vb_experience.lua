function gadget:GetInfo()
	return {
		name = "Voidborn experience growth + split",
		desc = "Units grow as they gain experience; at the split threshold they split into two normal-sized units (see /vbsettings)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
-- The host (or any player in a single player game) can change these at runtime
-- with the /vbsettings panel; the values are also exposed as mod options so a
-- lobby can set them before the game starts.
local DEFAULTS = {
	split_xp   = 0.14,    -- experience at which a unit splits in two
	max_growth = 1.00,    -- at xp == split_xp the unit is (1 + max_growth) times its normal size (1.0 = double size)
}
local LIMITS = {
	split_xp   = { 0.01, 2.00, 0.01 },   -- min, max, step
	max_growth = { 0.00, 4.00, 0.05 },
}
local POLL_FRAMES  = 10      -- how often experience is checked (30 frames = 1 second)
local STEP         = 0.02    -- only re-scale when the size changed by at least this much (saves network/draw updates)
local MIN_UNIT_GAP = 5       -- never split if the team has fewer than this many unit slots left
-- Units that never grow or split: commanders (a second commander would break the game-end rule) and all non-mobile units.
local function Eligible(unitDef)
	if not unitDef or not unitDef.canMove or unitDef.speed <= 0 then return false end
	local cp = unitDef.customParams
	if cp and cp.iscommander == "true" then return false end
	if unitDef.isFactory or unitDef.isBuilding then return false end
	return true
end

local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local spGetUnitExperience, spSetUnitExperience = Spring.GetUnitExperience, Spring.SetUnitExperience
	local tracked = {}          -- unitID -> { scale, radius, height }
	local frameOffset = 0

	-- the live values of the two tunables (changed by the /vbsettings panel)
	local splitXP   = DEFAULTS.split_xp
	local maxGrowth = DEFAULTS.max_growth

	-- publish them so the settings panel can show the current numbers
	local function Publish()
		Spring.SetGameRulesParam("vb_split_xp", splitXP)
		Spring.SetGameRulesParam("vb_max_growth", maxGrowth)
	end

	-- a lobby can set them before the game starts
	local function ReadModOptions()
		local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
		local v = tonumber(mo.split_xp)
		if v then splitXP = Clamp(v, LIMITS.split_xp[1], LIMITS.split_xp[2]) end
		v = tonumber(mo.max_growth)
		if v then maxGrowth = Clamp(v, LIMITS.max_growth[1], LIMITS.max_growth[2]) end
	end

	-- the host may change them while the game runs:  "vbexp:split_xp=0.2,max_growth=1.5"
	local function Allowed(playerID)
		if Spring.IsCheatingEnabled() then return true end
		local humans = 0
		for _, pid in ipairs(Spring.GetPlayerList()) do
			local _, active, spectator = Spring.GetPlayerInfo(pid, false)
			if active and not spectator then humans = humans + 1 end
		end
		if humans <= 1 then return true end
		-- the host leads the team with the lowest number
		local bestTeam
		for _, teamID in ipairs(Spring.GetTeamList()) do
			local leader = Spring.GetTeamLeader(teamID)
			if leader and leader >= 0 then
				if not bestTeam or teamID < bestTeam then bestTeam = teamID end
			end
		end
		if bestTeam then return Spring.GetTeamLeader(bestTeam) == playerID end
		return false
	end

	-- set the size of a unit (and tell the unsynced side about it)
	local function ApplyScale(unitID, t, scale)
		t.scale = scale
		Spring.SetUnitRulesParam(unitID, "vb_scale", scale, { public = true })
		if t.radius then pcall(Spring.SetUnitRadiusAndHeight, unitID, t.radius * scale, t.height * scale) end
		SendToUnsynced("vbscale", unitID, scale)
	end

	function gadget:RecvLuaMsg(msg, playerID)
		local PREFIX = "vbexp:"
		if type(msg) ~= "string" or msg:sub(1, #PREFIX) ~= PREFIX then return end
		local body = msg:sub(#PREFIX + 1)
		if body == "get" then Publish(); return true end
		if not Allowed(playerID) then
			Spring.Echo("[VB] changing the split settings needs the host (or /cheat)")
			return true
		end
		local changed = false
		for k, v in body:gmatch("([%w_]+)=([%-%d%.]+)") do
			local n = tonumber(v)
			if n then
				if k == "split_xp" then splitXP = Clamp(n, LIMITS.split_xp[1], LIMITS.split_xp[2]); changed = true
				elseif k == "max_growth" then maxGrowth = Clamp(n, LIMITS.max_growth[1], LIMITS.max_growth[2]); changed = true end
			end
		end
		if changed then
			Publish()
			-- re-apply the new growth to the units that already grew
			for unitID, t in pairs(tracked) do
				local xp = spGetUnitExperience(unitID) or 0
				if xp < splitXP then
					ApplyScale(unitID, t, 1 + maxGrowth * (xp / splitXP))
				end
			end
			Spring.Echo(string.format("[VB] split threshold %.3f, growth %.2fx", splitXP, maxGrowth))
		end
		return true
	end

	function gadget:UnitCreated(unitID, unitDefID)
		local ud = UnitDefs[unitDefID]
		if not Eligible(ud) then return end
		tracked[unitID] = { scale = 1, radius = Spring.GetUnitRadius(unitID), height = Spring.GetUnitHeight(unitID) }
	end

	function gadget:UnitDestroyed(unitID) tracked[unitID] = nil end

	function gadget:Initialize()
		ReadModOptions()
		Publish()
		for _, unitID in ipairs(Spring.GetAllUnits()) do gadget:UnitCreated(unitID, Spring.GetUnitDefID(unitID)) end
	end

	-- copy everything we can from `src` onto the freshly created `dst`
	local function Inherit(src, dst)
		-- /vbcreate modifications (hp, speed, range, damage, ...) and public rules params (png, name, template)
		local spec = GG.VB_unitSpec and GG.VB_unitSpec[src]
		if spec and GG.VB_ApplySpec then GG.VB_unitSpec[dst] = spec; GG.VB_ApplySpec(dst, spec) end
		local params = Spring.GetUnitRulesParams and Spring.GetUnitRulesParams(src)
		if params then
			for name, value in pairs(params) do
				if name:sub(1, 3) == "vb_" and name ~= "vb_scale" and type(value) ~= "table" then
					Spring.SetUnitRulesParam(dst, name, value, { public = true })
				end
			end
		end
		-- health FRACTION (both halves keep it, they are not halved)
		local hp, maxhp = Spring.GetUnitHealth(src)
		if hp and maxhp and maxhp > 0 then
			local _, dmax = Spring.GetUnitHealth(dst)
			if dmax then Spring.SetUnitHealth(dst, dmax * hp / maxhp) end
		end
		-- orders and stances
		local states = Spring.GetUnitStates(src)
		if states then
			if states.firestate then Spring.GiveOrderToUnit(dst, CMD.FIRE_STATE, { states.firestate }, 0) end
			if states.movestate then Spring.GiveOrderToUnit(dst, CMD.MOVE_STATE, { states.movestate }, 0) end
			if states["repeat"] ~= nil then Spring.GiveOrderToUnit(dst, CMD.REPEAT, { states["repeat"] and 1 or 0 }, 0) end
		end
		local cmds = Spring.GetUnitCommands(src, -1)
		if cmds then
			for i = 1, #cmds do
				local c = cmds[i]
				if c.id and c.id ~= CMD.STOP and c.params then
					Spring.GiveOrderToUnit(dst, c.id, c.params, c.options and c.options.coded or 0)
				end
			end
		end
		local group = Spring.GetUnitGroup and Spring.GetUnitGroup(src)
		if group and Spring.SetUnitGroup then pcall(Spring.SetUnitGroup, dst, group) end
		-- a unit that was transporting / being built etc. is out of scope; velocity and heading are kept
		local vx, vy, vz = Spring.GetUnitVelocity(src)
		if vx and Spring.SetUnitVelocity then pcall(Spring.SetUnitVelocity, dst, vx, vy, vz) end
	end

	local function Split(unitID, t)
		local defID, teamID = Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID)
		if not (defID and teamID) then return false end
		local limit = Spring.GetTeamMaxUnits(teamID)
		if limit and select(1, Spring.GetTeamUnitCount(teamID)) + MIN_UNIT_GAP > limit then return false end
		local x, y, z = Spring.GetUnitPosition(unitID)
		local dx, _, dz = Spring.GetUnitDirection(unitID)
		dx, dz = dx or 1, dz or 0
		local r = (t.radius or 24)
		-- the two halves end up on either side of the original position, perpendicular to its heading
		local px, pz = -dz, dx
		local len = math.sqrt(px * px + pz * pz); if len < 0.01 then px, pz, len = 1, 0, 1 end
		px, pz = px / len, pz / len
		local off = r * 0.9
		local bx, bz = x + px * off, z + pz * off
		local facing = Spring.GetUnitBuildFacing and Spring.GetUnitBuildFacing(unitID) or 0
		local newID = Spring.CreateUnit(defID, bx, y, bz, facing, teamID)
		if not newID then return false end
		Spring.SetUnitPosition(unitID, x - px * off, y, z - pz * off)   -- keep altitude (these units fly)
		Inherit(unitID, newID)
		-- both halves are normal sized again with experience reset, otherwise they would split again at once
		spSetUnitExperience(unitID, 0); spSetUnitExperience(newID, 0)
		ApplyScale(unitID, t, 1)
		tracked[newID] = { scale = 1, radius = Spring.GetUnitRadius(newID), height = Spring.GetUnitHeight(newID) }
		Spring.SetUnitRulesParam(newID, "vb_scale", 1, { public = true })
		Spring.SetUnitRulesParam(unitID, "vb_splits", (Spring.GetUnitRulesParam(unitID, "vb_splits") or 0) + 1, { public = true })
		Spring.SetUnitRulesParam(newID, "vb_splits", Spring.GetUnitRulesParam(unitID, "vb_splits"), { public = true })
		SendToUnsynced("vbsplit", x, y, z)
		return true
	end

	function gadget:GameFrame(n)
		if n % POLL_FRAMES ~= 0 then return end
		for unitID, t in pairs(tracked) do
			local xp = spGetUnitExperience(unitID) or 0
			if xp >= splitXP then
				Split(unitID, t)
			else
				local want = 1 + maxGrowth * (xp / splitXP)
				if math.abs(want - t.scale) >= STEP then ApplyScale(unitID, t, want) end
			end
		end
	end

--------------------------------------------------------------------------------
else  -- UNSYNCED: draw the scaled model and play the split sound
--------------------------------------------------------------------------------
	local scaleOf = {}
	local glPushMatrix, glPopMatrix, glScale, glUnitRaw = gl.PushMatrix, gl.PopMatrix, gl.Scale, gl.UnitRaw

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("vbscale", function(_, unitID, scale)
			if scale and math.abs(scale - 1) > 0.001 then scaleOf[unitID] = scale else scaleOf[unitID] = nil end
			if Spring.UnitRendering and Spring.UnitRendering.SetUnitLuaDraw then
				pcall(Spring.UnitRendering.SetUnitLuaDraw, unitID, scaleOf[unitID] ~= nil)
			end
		end)
		gadgetHandler:AddSyncAction("vbsplit", function(_, x, y, z)
			Spring.PlaySoundFile("sounds/split_pop.wav", 0.8, x, y, z, 0, 0, 0, "sfx")
		end)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("vbscale"); gadgetHandler:RemoveSyncAction("vbsplit")
		for unitID in pairs(scaleOf) do pcall(Spring.UnitRendering.SetUnitLuaDraw, unitID, false) end
	end

	function gadget:UnitDestroyed(unitID) scaleOf[unitID] = nil end

	-- called by the engine (after the unit transform is set) for units that have luaDraw enabled
	function gadget:DrawUnit(unitID, drawMode)
		local s = scaleOf[unitID]
		if not s then return false end
		glPushMatrix()
		glScale(s, s, s)
		glUnitRaw(unitID, true)      -- draw the model untransformed (we are already inside its transform); skips this callin
		glPopMatrix()
		return true
	end
end
