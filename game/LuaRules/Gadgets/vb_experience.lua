function gadget:GetInfo()
	return {
		name = "Voidborn experience growth + split",
		desc = "Units grow as they gain experience; at SPLIT_XP they split into two normal-sized units",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
local SPLIT_XP     = 0.07    -- experience at which a unit splits in two
local MAX_GROWTH   = 0.45    -- at xp == SPLIT_XP the unit is (1 + MAX_GROWTH) times its normal size
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

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local spGetUnitExperience, spSetUnitExperience = Spring.GetUnitExperience, Spring.SetUnitExperience
	local tracked = {}          -- unitID -> { scale, radius, height }
	local frameOffset = 0

	local function ApplyScale(unitID, t, scale)
		t.scale = scale
		Spring.SetUnitRulesParam(unitID, "vb_scale", scale, { public = true })
		if t.radius then pcall(Spring.SetUnitRadiusAndHeight, unitID, t.radius * scale, t.height * scale) end
		SendToUnsynced("vbscale", unitID, scale)
	end

	function gadget:UnitCreated(unitID, unitDefID)
		local ud = UnitDefs[unitDefID]
		if not Eligible(ud) then return end
		tracked[unitID] = { scale = 1, radius = Spring.GetUnitRadius(unitID), height = Spring.GetUnitHeight(unitID) }
	end

	function gadget:UnitDestroyed(unitID) tracked[unitID] = nil end

	function gadget:Initialize()
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
			if xp >= SPLIT_XP then
				Split(unitID, t)
			else
				local want = 1 + MAX_GROWTH * (xp / SPLIT_XP)
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
