-- Voidborn 0.19: BRANCHING ARC, the short-range lightning of the Haptic Grasp (the Hand).
--
-- A weapon with customParams.vb_branch = N is an arc: when it hits, the lightning BRANCHES to up to N more enemies standing within
-- vb_branch_range elmos of the first one.  Each of them takes vb_branch_pct of the damage the first target took (so the proximity bonus of
-- vb_touch carries over), credited to the shooter (experience counts), and a line of sparks is drawn from the first target to each.
-- Only the first hit of a shot branches (the explosion damages every unit in its area, which must not branch again), and only enemies are
-- ever branched to.
--
--   game/LuaRules/Gadgets/vb_arc.lua
--   weapons: tools/gen_specials.py    sparks: vb_haptic_arcspark in game/effects/vb_effects_019.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Arc", desc = "Haptic arc weapons branch to enemies around the first target",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local branchW = {}            -- weaponDefID -> { n, pct, range }
local lastShot = {}           -- attackerID -> frame of its last branching hit (one branch event per frame and shooter)
local SPARK = "vb_haptic_arcspark"
local STEP = 14               -- elmos between two sparks on a branch line
local MAX_SPARKS = 10

function gadget:Initialize()
	for id, wd in pairs(WeaponDefs) do
		local cp = wd.customParams
		if cp and cp.vb_branch then
			branchW[id] = { n = tonumber(cp.vb_branch) or 0, pct = tonumber(cp.vb_branch_pct) or 0.35, range = tonumber(cp.vb_branch_range) or 90 }
		end
	end
	if next(branchW) == nil then gadgetHandler:RemoveGadget(self) end
end

local function Spark(x1, y1, z1, x2, y2, z2)
	local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	local n = math.max(1, math.min(MAX_SPARKS, math.floor(len / STEP)))
	for i = 0, n do
		local u = i / n
		local j = (i == 0 or i == n) and 0 or 6                 -- the line wanders a little between its ends
		Spring.SpawnCEG(SPARK, x1 + dx * u + (math.random() - 0.5) * j, y1 + dy * u + (math.random() - 0.5) * j, z1 + dz * u + (math.random() - 0.5) * j)
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	local b = branchW[weaponDefID]
	if not b or not attackerID or paralyzer or (damage or 0) <= 0 or b.n <= 0 then return end
	if attackerTeam and unitTeam and Spring.AreTeamsAllied(attackerTeam, unitTeam) then return end
	local frame = Spring.GetGameFrame()
	if lastShot[attackerID] == frame then return end
	lastShot[attackerID] = frame

	local x, y, z = Spring.GetUnitPosition(unitID, true)
	if not x then return end
	local found = {}
	for _, id in ipairs(Spring.GetUnitsInSphere(x, y, z, b.range) or {}) do
		if id ~= unitID and not Spring.GetUnitIsDead(id) then
			local team = Spring.GetUnitTeam(id)
			if team and attackerTeam and not Spring.AreTeamsAllied(attackerTeam, team) then
				local ux, uy, uz = Spring.GetUnitPosition(id, true)
				if ux then found[#found + 1] = { id = id, d = (ux - x) ^ 2 + (uy - y) ^ 2 + (uz - z) ^ 2, x = ux, y = uy, z = uz } end
			end
		end
	end
	table.sort(found, function(a, c) return a.d < c.d end)
	for i = 1, math.min(b.n, #found) do
		local f = found[i]
		Spring.AddUnitDamage(f.id, damage * b.pct, 0, attackerID, -1)   -- plain damage (no weapon): no proximity bonus on the branch itself
		Spark(x, y, z, f.x, f.y, f.z)
	end
end

function gadget:UnitDestroyed(unitID) lastShot[unitID] = nil end
