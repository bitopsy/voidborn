-- LuaUI/Headers/vb_values.h.lua
-- Shared unit-value rules for the Voidborn widgets, so that every widget agrees on what "army value" (AV),
-- "defence value" (DV) and "build power" (BP) mean:
--
--   AV  armed units that can move              value = metal cost x health fraction
--   DV  armed structures (not builders)         value = metal cost x health fraction
--   BP  everything with a build speed           value = the unit's buildSpeed
--
-- This is exactly the rule gui_hud_histogram.lua always used (it now loads it from here); the Force Map
-- (vb_forcemap.lua) uses it as well, and adds the weapon range of every unit.
--
-- Use:  local V = VFS.Include("LuaUI/Headers/vb_values.h.lua")
--       local info = V.Defs()[unitDefID]     -- nil, or { cost, isBP, isArmy, isDef, bp, range }
--       V.IsMex()[unitDefID]                 -- true for metal extractors
--       V.Num(12345)                         -- "12.3k"

local V = {}

local defs, mex

function V.Defs()
	if defs then return defs end
	defs = {}
	for udid, ud in pairs(UnitDefs) do
		if type(udid) == "number" then
			local cost = ud.metalCost or 0
			local bp = (ud.buildSpeed and ud.buildSpeed > 0) and ud.buildSpeed or 0
			local isBP = bp > 0
			local canAttack = ud.weapons and #ud.weapons > 0
			local isStatic = (not ud.canMove) or (ud.speed == 0)
			local isDef = canAttack and isStatic and not isBP or false
			local isArmy = canAttack and ud.canMove and ud.speed and ud.speed > 0 or false
			if cost > 0 and (isBP or isArmy or isDef) then
				local range = ud.maxWeaponRange or 0
				if range <= 0 and ud.weapons then
					for _, w in pairs(ud.weapons) do
						local wd = w.weaponDef and WeaponDefs[w.weaponDef]
						if wd and (wd.range or 0) > range then range = wd.range end
					end
				end
				defs[udid] = { cost = cost, isBP = isBP, isArmy = isArmy, isDef = isDef, bp = bp, range = range }
			end
		end
	end
	return defs
end

function V.IsMex()
	if mex then return mex end
	mex = {}
	for udid, ud in pairs(UnitDefs) do
		if type(udid) == "number" then
			local cp = ud.customParams
			if (ud.extractsMetal or 0) > 0 or (cp and cp.kind == "mex") then mex[udid] = true end
		end
	end
	return mex
end

function V.Num(v)
	v = v or 0
	local a = math.abs(v)
	if a >= 100000 then return string.format("%dk", math.floor(v / 1000 + 0.5))
	elseif a >= 1000 then return string.format("%.1fk", v / 1000)
	else return string.format("%d", math.floor(v + 0.5)) end
end

return V
