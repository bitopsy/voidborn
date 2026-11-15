--[[
  Voidborn cost rules: what a custom unit costs.

  A unit built with the forge (or with /vbcreate) is stronger than its base
  unit, so it has to be more expensive - otherwise the extra power is free.
  The rules are relative to the cost of the base unit, so a cheap unit stays
  cheap and an expensive one stays expensive.

  This file is used by two sides that never talk to each other directly:

    * LuaRules/Gadgets/vb_dev_units.lua  - puts the price on the spawned unit
    * LuaUI/Widgets/vb_forge.lua         - shows the price while you design

  So both sides always agree on what a unit costs.
]]

local C = {}

--------------------------------------------------------------------------------
-- the rates
--------------------------------------------------------------------------------
-- Every rate is a share of the metal cost of the BASE unit, so the price of a
-- custom unit always stays in the same ballpark as the price of the unit it
-- was built from.
C.RATE = {
	hp     = 1.00,   -- the extra health costs what the health it replaces costs
	speed  = 0.60,   -- per multiplier point (0.6 = +60% of the base cost)
	range  = 0.80,
	dmg    = 1.20,   -- damage is the most valuable thing on a unit
	reload = 0.50,
	sight  = 0.50,   -- the extra sight costs what the base sight costs
	prim   = 0.15,   -- per primitive of the custom body
	lua    = 0.50,   -- a custom script on the unit
	alt    = 0.01,   -- energy per elmo of extra altitude (share of the base energy)
}
-- how much of the base build time the premium adds (a stronger unit takes longer)
C.BUILD_FACTOR = 0.60
-- the build time penalty never grows past this multiple of the base build time
C.MAX_RATIO = 8
-- buildTime is in BUILD POINTS, not seconds: a builder with workerTime W adds W points per second
-- (the Voidborn factories have workerTime 100).  The production queue builds at this rate, so a
-- 468 point unit takes 4.7 s, exactly as it does in a factory.  Raise it to make the queue faster.
C.BUILD_POWER = 100

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function ArmorIndex()
	local arm = (Game and Game.armorTypes and Game.armorTypes.default) or 0
	return arm
end

-- the damage of one shot volley of the unit
function C.BaseDamage(ud)
	if not ud then return 0 end
	local arm = ArmorIndex()
	local sum = 0
	for _, w in ipairs(ud.weapons or {}) do
		local wd = w.weaponDef and WeaponDefs[w.weaponDef]
		if wd then
			local d = (wd.damages and (wd.damages[arm] or wd.damages[0] or wd.damages[1])) or 0
			sum = sum + d * (wd.salvoSize or 1) * (wd.projectiles or 1)
		end
	end
	return sum
end

-- the longest weapon range of the unit
function C.BaseRange(ud)
	if not ud then return 0 end
	local r = 0
	for _, w in ipairs(ud.weapons or {}) do
		local wd = w.weaponDef and WeaponDefs[w.weaponDef]
		if wd then r = math.max(r, wd.range or 0) end
	end
	return r
end

-- how many primitives the encoded shape has
function C.Primitives(shape)
	if type(shape) ~= "string" or shape == "" then return 0 end
	local n = 0
	for _ in shape:gmatch("[^;]+") do n = n + 1 end
	return n
end

--------------------------------------------------------------------------------
-- the price of a custom unit
--------------------------------------------------------------------------------
-- spec: the requested changes (the same table the gadget receives)
-- ud:   the unit def of the base unit
-- returns { metal, energy, build, premium, count }
function C.Cost(spec, ud)
	spec = spec or {}
	if not ud then return nil end
	local baseMetal  = ud.metalCost  or 0
	local baseEnergy = ud.energyCost or 0
	local baseBuild  = ud.buildTime  or 1
	local premium, epremium = 0, 0

	-- health: only what is added on top of the base unit costs
	local hp = tonumber(spec.hp) or 0
	local baseHP = ud.health or 0
	if hp > baseHP and baseHP > 0 then
		premium = premium + (hp - baseHP) * (baseMetal / baseHP) * C.RATE.hp
	end

	-- speed (a multiplier of the base speed): only a faster unit costs more
	local speed = tonumber(spec.speed)
	if speed and speed > 1 then premium = premium + (speed - 1) * baseMetal * C.RATE.speed end

	-- range (a multiplier of the longest weapon range)
	local range = tonumber(spec.range)
	if range and range > 1 then premium = premium + (range - 1) * baseMetal * C.RATE.range end

	-- damage (a multiplier of one volley)
	local dmg = tonumber(spec.dmg)
	if dmg and dmg > 1 then premium = premium + (dmg - 1) * baseMetal * C.RATE.dmg end

	-- reload (a multiplier: below 1 is faster, so that is what costs more)
	local reload = tonumber(spec.reload)
	if reload and reload < 1 then
		premium = premium + (1 - reload) * baseMetal * C.RATE.reload * 2
	end

	-- sight (an absolute radius, priced like the health)
	local sight = tonumber(spec.sight)
	local baseSight = ud.losRadius or 0
	if sight and sight > baseSight and baseSight > 0 then
		premium = premium + (sight - baseSight) * (baseMetal / baseSight) * C.RATE.sight
	end

	-- altitude (an absolute height, paid in energy)
	local alt = tonumber(spec.alt)
	if alt and alt > 0 then
		epremium = epremium + alt * math.max(20, baseEnergy) * C.RATE.alt
	end

	-- the custom body
	local prims = C.Primitives(spec.shape)
	if prims > 0 then premium = premium + prims * baseMetal * C.RATE.prim end

	-- a custom script on the unit
	if spec.lua and spec.lua ~= "" then premium = premium + baseMetal * C.RATE.lua end

	local count = math.max(1, math.floor(tonumber(spec.count) or 1))
	local metal  = ((tonumber(spec.metal)  and tonumber(spec.metal)  > 0 and tonumber(spec.metal))  or baseMetal)  + premium
	local energy = ((tonumber(spec.energy) and tonumber(spec.energy) > 0 and tonumber(spec.energy)) or baseEnergy) + epremium
	-- the build time: the base time plus a penalty for the extra power
	local ratio = baseMetal > 0 and (premium / baseMetal) or 0
	if ratio > C.MAX_RATIO then ratio = C.MAX_RATIO end
	local build = ((tonumber(spec.buildtime) and tonumber(spec.buildtime) > 0 and tonumber(spec.buildtime)) or baseBuild)
		+ baseBuild * C.BUILD_FACTOR * ratio
	-- every unit of a group is built and paid for on its own
	metal = metal * count
	build = build * count

	return {
		metal   = math.floor(metal),
		energy  = math.floor(energy),
		build   = math.max(1, math.floor(build)),                    -- build POINTS
		seconds = math.max(0.5, build / C.BUILD_POWER),             -- what the queue really takes
		premium = math.floor(premium),
		count   = count,
	}
end

return C
