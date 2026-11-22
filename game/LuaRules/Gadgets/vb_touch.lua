-- Voidborn 0.17: TOUCH, the tricks of the Haptic Grasp (the Hand).
--
-- The Grasp does not see far and does not shoot far.  What it does is hit harder the closer the enemy is:
--   * PROXIMITY.  A weapon with customParams.vb_touch deals up to +TOUCH_BONUS (75%) more damage at point-blank range.  The bonus is
--     full at TOUCH_NEAR (80) elmos or less between the two units' surfaces and fades in a straight line to nothing at the weapon's
--     maximum range.  A target that is hit from far away takes the weapon's plain damage.
--   * KAMIKAZE.  A unit whose unitdef carries customParams.vb_kami_dmg / vb_kami_aoe / vb_kami_grip (the Clutch, the Strangler) bursts the
--     moment an enemy is within TOUCH_REACH (70) elmos of it: the touched enemy takes vb_kami_dmg, every other enemy within vb_kami_aoe
--     takes a part of it (60% at the middle of the burst fading to 15% at the edge; the touched one takes it all), and the unit dies.
--     The blast is dealt here with Spring.AddUnitDamage and credited to the kamikaze (experience counts); the engine's own explosion
--     of the unit (selfDestructAs) is only the picture and does no damage.  A kamikaze that is shot down pops small instead (explodeAs).
--   * GRIP.  Everything a burst reaches is GRIPPED for vb_kami_grip seconds: Haptic touch weapons deal GRIP_BONUS (25%) more to it,
--     on top of the proximity bonus.
-- Friendly fire never counts: no bonus on a unit of the shooter's own side, and a burst never hurts or grips an ally.
-- Mod options: touch_bonus (0.75; 0 = off), touch_near (80), grip_bonus (0.25; 0 = off), kami_scale (1.0 = burst damage multiplier; 0 = no burst).
--
--   game/LuaRules/Gadgets/vb_touch.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Touch", desc = "Haptic weapons hit harder up close; Haptic kamikazes burst on touch and grip what they reach",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local FPS = 30
local TICK = 3                                    -- the kamikazes look for something to touch every this many frames
local opts = Spring.GetModOptions() or {}
local function num(v, d) v = tonumber(v); if v == nil then return d end return v end
local TOUCH_BONUS = num(opts.touch_bonus, 0.75)
local TOUCH_NEAR = num(opts.touch_near, 80)
local GRIP_BONUS = num(opts.grip_bonus, 0.25)
local KAMI_SCALE = num(opts.kami_scale, 1.0)
local TOUCH_REACH = 70                            -- surface distance at which a kamikaze counts as touching

local touchW = {}        -- weaponDefID -> maximum range
local kamiDef = {}       -- unitDefID -> { dmg, aoe, grip }
local kamis = {}         -- unitID -> true (living kamikazes)
local gripped = {}       -- unitID -> frame the grip ends

function gadget:Initialize()
	for id, wd in pairs(WeaponDefs) do
		local cp = wd.customParams
		if cp and (cp.vb_touch == "1" or cp.vb_touch == "true") then touchW[id] = tonumber(wd.range) or 0 end
	end
	for id, ud in pairs(UnitDefs) do
		local cp = ud.customParams
		if cp and cp.vb_kami_dmg then
			kamiDef[id] = { dmg = tonumber(cp.vb_kami_dmg) or 0, aoe = tonumber(cp.vb_kami_aoe) or 60, grip = tonumber(cp.vb_kami_grip) or 6 }
		end
	end
	if next(touchW) == nil and next(kamiDef) == nil then gadgetHandler:RemoveGadget(self) return end
	for _, u in ipairs(Spring.GetAllUnits() or {}) do
		if kamiDef[Spring.GetUnitDefID(u)] then kamis[u] = true end
	end
end

-- distance between the surfaces of two units (centre distance minus the target's radius, never below 0); nil if one has no position
local function Sep(a, b)
	local ax, ay, az = Spring.GetUnitPosition(a)
	local bx, by, bz = Spring.GetUnitPosition(b)
	if not (ax and bx) then return nil end
	local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
	local r = Spring.GetUnitRadius and Spring.GetUnitRadius(b) or 0
	return math.max(0, d - (r or 0))
end

local function Enemy(teamA, teamB) return teamA and teamB and not Spring.AreTeamsAllied(teamA, teamB) end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	local far = touchW[weaponDefID]
	if not far or not attackerID or paralyzer then return damage end
	if not Enemy(attackerTeam, unitTeam) then return damage end
	local mult = 1
	if TOUCH_BONUS > 0 then
		local d = Sep(attackerID, unitID)
		if d then
			local span = math.max(far - TOUCH_NEAR, 1)
			local k = math.max(0, math.min(1, (far - d) / span))
			mult = mult + TOUCH_BONUS * k
		end
	end
	local g = gripped[unitID]
	if g and GRIP_BONUS > 0 and Spring.GetGameFrame() < g then mult = mult * (1 + GRIP_BONUS) end
	if mult ~= 1 then return damage * mult end
	return damage
end

local function Burst(kid, target, def)
	local x, y, z = Spring.GetUnitPosition(kid)
	local team = Spring.GetUnitTeam(kid)
	local frame = Spring.GetGameFrame()
	kamis[kid] = nil
	local near = Spring.GetUnitsInSphere(x, y, z, def.aoe + 150) or {}
	for _, u in ipairs(near) do
		if u ~= kid and Spring.ValidUnitID(u) and not Spring.GetUnitIsDead(u) and Enemy(team, Spring.GetUnitTeam(u)) then
			local dmg
			if u == target then dmg = def.dmg
			else
				local s = Sep(kid, u)
				if s and s <= def.aoe then dmg = def.dmg * (0.6 - 0.45 * (s / def.aoe)) end
			end
			if dmg and dmg > 0 then
				if KAMI_SCALE > 0 then Spring.AddUnitDamage(u, dmg * KAMI_SCALE, 0, kid) end
				if GRIP_BONUS > 0 then
					gripped[u] = frame + def.grip * FPS
					Spring.SetUnitRulesParam(u, "vb_grip", 1)
				end
			end
		end
	end
	Spring.DestroyUnit(kid, true, false)         -- selfDestructAs: the picture of the burst
end

function gadget:UnitCreated(unitID, unitDefID) if kamiDef[unitDefID] then kamis[unitID] = true end end

function gadget:UnitDestroyed(unitID)
	kamis[unitID] = nil; gripped[unitID] = nil
end

function gadget:GameFrame(frame)
	if frame % TICK == 0 then
		for kid in pairs(kamis) do
			if not Spring.ValidUnitID(kid) or Spring.GetUnitIsDead(kid) then kamis[kid] = nil
			elseif not Spring.GetUnitIsBeingBuilt(kid) then
				local x, y, z = Spring.GetUnitPosition(kid)
				local team = Spring.GetUnitTeam(kid)
				local best, bestD
				for _, u in ipairs(Spring.GetUnitsInSphere(x, y, z, TOUCH_REACH + 160) or {}) do
					if u ~= kid and Spring.ValidUnitID(u) and Enemy(team, Spring.GetUnitTeam(u)) then
						local s = Sep(kid, u)
						if s and s <= TOUCH_REACH and (not bestD or s < bestD) then best, bestD = u, s end
					end
				end
				if best then Burst(kid, best, kamiDef[Spring.GetUnitDefID(kid)]) end
			end
		end
	end
	if frame % 30 == 0 then
		for u, untilFrame in pairs(gripped) do
			if frame >= untilFrame or not Spring.ValidUnitID(u) then
				gripped[u] = nil
				if Spring.ValidUnitID(u) then Spring.SetUnitRulesParam(u, "vb_grip", 0) end
			end
		end
	end
end
