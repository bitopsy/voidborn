-- Voidborn: the Destabilisation Gun (the commander's third weapon).
--
-- The commander fires a slow shell at the mouse position (D, then click: the
-- engine's manual-fire command).  Where it explodes, a wave spreads out.
-- Every enemy the wave touches is destabilised: it wriggles inside an electric
-- shield and cannot move or shoot.  Nine seconds at the centre, one at the rim.
-- While destabilised it loses 20% of its current health every second (compounding).
--
-- The shell, the aiming and the energy cost are the WEAPON's job (see the
-- weapondef notes at the bottom).  This gadget does the wave, the stun and
-- the visuals.
--
--   game/LuaRules/Gadgets/vb_dgun.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Destabilisation Gun",
		desc = "The commander's D-gun: a wave of destabilisation that stuns everything it touches, longer the closer it was",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 2, enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
local RADIUS   = 240   -- how far the wave reaches (elmos)
local SPEED    = 300   -- how fast the front travels (elmos per second)
local MAX_STUN = 9     -- seconds at the very centre of the wave
local MIN_STUN = 1     -- seconds at the rim
local MAX_WAVES = 8    -- waves alive at the same time
local FPS      = 30    -- simulation frames per second
local DOT_RATE = 0.20  -- share of its CURRENT health a destabilised unit loses every second (compounding)
local DOT_TICK = 3     -- the loss is applied every this many frames

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local dgunWeapons = {}   -- weaponDefID -> true
	local isCom = {}         -- unitDefID -> true: commanders are immune to the commander guns
	local immuneWeapons = {} -- weaponDefID -> true: every manualFire weapon of a commander (D-gun, Q-gun)
	local waves   = {}       -- { x, y, z, r, ally, hit = {unitID = true} }
	local stunned = {}       -- unitID -> { untilFrame, rot = {pitch, yaw, roll} }
	local gaiaAlly = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID(), false))

	-- which weapons are "the D-gun"?  Any weapondef with customParams.vb_dgun,
	-- or whose name contains dgun / disintegrator.
	local function LooksLikeDgun(wd)
		local cp = wd.customParams
		if cp and (cp.vb_dgun == "1" or cp.vb_dgun == "true" or cp.vb_dgun == true) then return true end
		local n = string.lower(wd.name or "")
		return n:find("dgun", 1, true) or n:find("d_gun", 1, true) or n:find("disintegrator", 1, true)
	end

	function gadget:Initialize()
		for defID, ud in pairs(UnitDefs) do
			local cp = ud.customParams
			if cp and cp.kind == "com" then
				isCom[defID] = true
				for _, w in pairs(ud.weapons or {}) do
					local wd = w.weaponDef and WeaponDefs[w.weaponDef]
					if wd and wd.manualFire then immuneWeapons[w.weaponDef] = true end
				end
			end
		end
		for id, wd in pairs(WeaponDefs) do
			if LooksLikeDgun(wd) then dgunWeapons[id] = true end
		end
		-- fallback: the paralyzing weapon of a commander (customParams.kind == "com")
		if next(dgunWeapons) == nil then
			for _, ud in pairs(UnitDefs) do
				local cp = ud.customParams
				if cp and cp.kind == "com" then
					for _, w in pairs(ud.weapons or {}) do
						local wd = w.weaponDef and WeaponDefs[w.weaponDef]
						if wd and wd.paralyzer then dgunWeapons[w.weaponDef] = true end
					end
				end
			end
		end
		if next(dgunWeapons) == nil then
			Spring.Echo("[vb_dgun] no D-gun weapon found: give the weapondef customParams.vb_dgun = '1'")
			gadgetHandler:RemoveGadget(self)
			return
		end
		local watch = Script.SetWatchExplosion or Script.SetWatchWeapon
		for id in pairs(dgunWeapons) do
			watch(id, true)
			Spring.Echo("[vb_dgun] watching weapon " .. tostring(WeaponDefs[id].name))
		end
	end

	-- the commander guns never hurt (or stun) a commander
	function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID)
		if isCom[unitDefID] and (immuneWeapons[weaponDefID] or dgunWeapons[weaponDefID]) then
			return 0, 0
		end
		return damage
	end

	-- the shell exploded: start the wave right there
	function gadget:Explosion(weaponDefID, px, py, pz, ownerID)
		if not dgunWeapons[weaponDefID] then return false end
		if #waves >= MAX_WAVES then table.remove(waves, 1) end
		local ally = ownerID and Spring.GetUnitAllyTeam(ownerID) or nil
		waves[#waves + 1] = { x = px, y = py, z = pz, r = 0, ally = ally, owner = ownerID, hit = {} }
		SendToUnsynced("vbdgun", "w", px, py, pz, Spring.GetGameFrame())
		return false
	end

	-- the stun depends on how close the unit was to the impact
	local function StunFor(dist)
		local t = 1 - math.min(1, dist / RADIUS)   -- 1 in the centre, 0 at the rim
		return MIN_STUN + (MAX_STUN - MIN_STUN) * (t * t)
	end

	-- the engine's own paralysis: damage that is paralyze damage only fills the unit's stun meter,
	-- it takes no health, and the meter drains by itself.  (The old code forced the meter every 4
	-- frames with SetUnitHealth; the engine's native path is the safe one.)
	local function Paralyze(uid, secs)
		local _, maxhp = Spring.GetUnitHealth(uid)
		if maxhp then
			Spring.AddUnitDamage(uid, maxhp * (1 + secs / 40), secs)
		end
	end

	local function Stun(uid, dist, owner)
		local frame = Spring.GetGameFrame()
		local secs = StunFor(dist)
		local untilFrame = frame + math.floor(secs * FPS)
		local s = stunned[uid]
		if s then
			if untilFrame > s.untilFrame then s.untilFrame = untilFrame; Paralyze(uid, secs) end
		else
			local ok, p, y, r = pcall(Spring.GetUnitRotation, uid)
			s = { untilFrame = untilFrame, owner = owner, rot = ok and p and { p, y, r } or nil }
			stunned[uid] = s
			Paralyze(uid, secs)
		end
		SendToUnsynced("vbdgun", "s", uid, s.untilFrame)
	end

	local function Release(uid, s)
		stunned[uid] = nil
		if Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid) then
			if s.rot then pcall(Spring.SetUnitRotation, uid, s.rot[1], s.rot[2], s.rot[3]) end
		end
		SendToUnsynced("vbdgun", "u", uid)
	end

	function gadget:UnitDestroyed(uid)
		if stunned[uid] then
			stunned[uid] = nil
			SendToUnsynced("vbdgun", "u", uid)
		end
	end

	function gadget:GameFrame(frame)
		-- the waves grow; everybody they pass is destabilised
		local step = SPEED / FPS
		for i = #waves, 1, -1 do
			local w = waves[i]
			w.r = w.r + step
			for _, uid in ipairs(Spring.GetUnitsInCylinder(w.x, w.z, w.r) or {}) do
				if not w.hit[uid] and not isCom[Spring.GetUnitDefID(uid)] then
					local ally = Spring.GetUnitAllyTeam(uid)
					if ally ~= w.ally and ally ~= gaiaAlly then
						local x, _, z = Spring.GetUnitPosition(uid)
						if x then
							w.hit[uid] = true
							Stun(uid, math.sqrt((x - w.x) ^ 2 + (z - w.z) ^ 2), w.owner)
						end
					end
				end
			end
			if w.r >= RADIUS then table.remove(waves, i) end
		end

		-- keep the victims paralyzed, wiggle them, release them when done
		for uid, s in pairs(stunned) do
			if frame >= s.untilFrame or not Spring.ValidUnitID(uid) then
				Release(uid, s)
			elseif Spring.GetUnitIsDead(uid) or (Spring.GetUnitHealth(uid) or 1) <= 0 then
				stunned[uid] = nil   -- dying: leave it alone, let it die
				SendToUnsynced("vbdgun", "u", uid)
			else
				-- destabilised: lose DOT_RATE of the current health per second, so the loss shrinks
				-- as the health does (100 -> 80 -> 64 -> 51 ...)
				if frame % DOT_TICK == 0 then
					local hp = Spring.GetUnitHealth(uid)
					if hp and hp > 0 then
						local owner = s.owner and Spring.ValidUnitID(s.owner) and s.owner or nil
						Spring.AddUnitDamage(uid, hp * (1 - (1 - DOT_RATE) ^ (DOT_TICK / FPS)), 0, owner)
					end
				end
				if s.rot then
					local a = frame * 1.9 + uid
					pcall(Spring.SetUnitRotation, uid,
						s.rot[1],
						s.rot[2] + 0.10 * math.sin(a),
						s.rot[3] + 0.06 * math.sin(a * 1.7))
				end
			end
		end
	end

--------------------------------------------------------------------------------
else
--------------------------------------------------------------------------------
	-- the unsynced side draws the wave and the electric shields
	local waves   = {}   -- { x, y, z, born }
	local shields = {}   -- unitID -> the frame the shield is gone

	local spGetGroundHeight = Spring.GetGroundHeight

	local function Ring(x, z, r, alpha, c)
		if r <= 3 then return end
		local seg = 48
		gl.Color(c[1], c[2], c[3], alpha)
		gl.BeginEnd(GL.TRIANGLE_STRIP, function()
			for i = 0, seg do
				local a = i / seg * 2 * math.pi
				local ca, sa = math.cos(a), math.sin(a)
				local x1, z1 = x + ca * (r - 3), z + sa * (r - 3)
				local x2, z2 = x + ca * (r + 3), z + sa * (r + 3)
				gl.Vertex(x1, spGetGroundHeight(x1, z1) + 4, z1)
				gl.Vertex(x2, spGetGroundHeight(x2, z2) + 4, z2)
			end
		end)
	end

	local function SpherePoint(x, y, z, radius, p, th, t, seed)
		-- the sphere jitters: that is the wiggle
		local j = 1 + 0.10 * math.sin(th * 7 + t * 23 + seed) * math.sin(p * 5 + t * 31 + seed * 2)
		return x + math.sin(p) * math.cos(th) * radius * j,
		       y + math.cos(p) * radius * j,
		       z + math.sin(p) * math.sin(th) * radius * j
	end

	local function Shield(x, y, z, radius, t, seed)
		gl.Color(0.55, 0.8, 1.0, 0.22)
		local rings, segs = 6, 12
		gl.BeginEnd(GL.TRIANGLES, function()
			for i = 0, rings - 1 do
				for s = 0, segs - 1 do
					local p1 = i / rings * math.pi
					local p2 = (i + 1) / rings * math.pi
					local t1 = s / segs * 2 * math.pi
					local t2 = (s + 1) / segs * 2 * math.pi
					local ax, ay, az = SpherePoint(x, y, z, radius, p1, t1, t, seed)
					local bx, by, bz = SpherePoint(x, y, z, radius, p1, t2, t, seed)
					local cx, cy, cz = SpherePoint(x, y, z, radius, p2, t2, t, seed)
					local dx, dy, dz = SpherePoint(x, y, z, radius, p2, t1, t, seed)
					gl.Vertex(ax, ay, az); gl.Vertex(bx, by, bz); gl.Vertex(cx, cy, cz)
					gl.Vertex(ax, ay, az); gl.Vertex(cx, cy, cz); gl.Vertex(dx, dy, dz)
				end
			end
		end)
		-- a few lightning arcs on the surface
		gl.LineWidth(2)
		gl.Color(0.85, 0.95, 1.0, 0.9)
		for _ = 1, 4 do
			local p = math.random() * math.pi
			local th = math.random() * 2 * math.pi
			gl.BeginEnd(GL.LINE_STRIP, function()
				for k = 0, 4 do
					local ax, ay, az = SpherePoint(x, y, z, radius * 1.02,
						p + (math.random() - 0.5) * 0.5 + k * 0.15,
						th + (math.random() - 0.5) * 0.5 + k * 0.2, t, seed)
					gl.Vertex(ax, ay, az)
				end
			end)
		end
		gl.LineWidth(1)
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("vbdgun", function(_, what, a, b, c, d)
			if what == "w" then
				waves[#waves + 1] = { x = a, y = b, z = c, born = d }
			elseif what == "s" then
				shields[a] = b
			elseif what == "u" then
				shields[a] = nil
			end
		end)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("vbdgun")
	end

	function gadget:DrawWorld()
		if #waves == 0 and next(shields) == nil then return end
		local frame = Spring.GetGameFrame()
		local t = os.clock()

		gl.DepthTest(false)
		gl.Blending(GL.SRC_ALPHA, GL.ONE)

		-- the wave fronts (same speed as the synced side, driven by the game frame)
		for i = #waves, 1, -1 do
			local w = waves[i]
			local r = (frame - w.born) * SPEED / FPS
			if r > RADIUS + 10 then
				table.remove(waves, i)
			else
				Ring(w.x, w.z, r,        0.55, { 0.55, 0.8, 1.0 })
				Ring(w.x, w.z, r * 0.72, 0.28, { 0.4, 0.6, 1.0 })
				Ring(w.x, w.z, r * 0.45, 0.14, { 0.7, 0.85, 1.0 })
			end
		end

		-- the electric shields around the stunned units
		local seed = 0
		for uid, untilFrame in pairs(shields) do
			if frame >= untilFrame then
				shields[uid] = nil
			else
				seed = seed + 1
				local x, y, z = Spring.GetUnitPosition(uid)
				if x then
					local defID = Spring.GetUnitDefID(uid)
					local ud = defID and UnitDefs[defID]
					local r = (ud and ud.radius) or 20
					Shield(x, y + r * 0.5, z, r * 1.3, t, seed * 1.7)
				end
			end
		end

		gl.Color(1, 1, 1, 1)
		gl.Blending(true)
		gl.DepthTest(true)
	end
end

--------------------------------------------------------------------------------
-- WEAPONDEF CHECKLIST (the gadget cannot do this part for you)
--
--   * commandFire = true      -> the unit gets the "Manual fire" command,
--                                bound to the D key in the default uikeys
--                                (press D, then click: that is the mouse aim)
--   * energyPerShot = 900     -> the 900 energy cost
--   * a slow projectile (e.g. a plasma/cannon type, ~1.6 s flight time),
--     with an explosion, and customParams.vb_dgun = "1"
--   * the weapon must be on a unit whose customParams.kind == "com"
--     only if you rely on the fallback detection
--------------------------------------------------------------------------------
