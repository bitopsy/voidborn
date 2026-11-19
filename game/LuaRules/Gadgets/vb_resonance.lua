-- Voidborn 0.16: RESONANCE, the trick of the Tympan Conclave (the Ear).
--
-- A sound that arrives from many places at once rings louder.  Every weapon of the Conclave that carries
-- customParams.vb_resonance gets a bonus when OTHER Tympan units hit the same target within the last
-- WINDOW seconds: each distinct attacker adds STEP (12%) to the damage of the hit, up to MAX_STACKS (4)
-- other attackers, i.e. +48%.  One Tympan unit alone does no extra damage: the faction is built to focus fire.
--
-- Not affected: the commander's D-gun and Q-gun (they are not resonance weapons), friendly fire, units of
-- other factions.  The two numbers can be changed in the lobby (mod options resonance_step, resonance_max).
--
--   game/LuaRules/Gadgets/vb_resonance.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Resonance", desc = "Tympan weapons hit harder when several of them hit the same target",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local FPS = 30
local WINDOW = 1.5 * FPS            -- frames a hit counts as "recent"
local opts = Spring.GetModOptions() or {}
local STEP = tonumber(opts.resonance_step) or 0.12
local MAX_STACKS = tonumber(opts.resonance_max) or 4

local resWeapon = {}     -- weaponDefID -> true
local recent = {}        -- targetID -> { [attackerID] = frame of its last hit }

function gadget:Initialize()
	for id, wd in pairs(WeaponDefs) do
		local cp = wd.customParams
		if cp and (cp.vb_resonance == "1" or cp.vb_resonance == "true") then resWeapon[id] = true end
	end
	if next(resWeapon) == nil then gadgetHandler:RemoveGadget(self) end
end

-- the stack count the next hit would get (other attackers that are still "ringing")
local function Stacks(targetID, attackerID, frame)
	local r = recent[targetID]
	if not r then return 0 end
	local n = 0
	for a, f in pairs(r) do
		if a ~= attackerID and frame - f <= WINDOW then n = n + 1 end
	end
	return math.min(n, MAX_STACKS)
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if not resWeapon[weaponDefID] or not attackerID or paralyzer then return damage end
	if attackerTeam and unitTeam and Spring.AreTeamsAllied(attackerTeam, unitTeam) then return damage end
	local frame = Spring.GetGameFrame()
	local n = Stacks(unitID, attackerID, frame)
	local r = recent[unitID]
	if not r then r = {}; recent[unitID] = r end
	r[attackerID] = frame
	if n > 0 then
		Spring.SetUnitRulesParam(unitID, "vb_resonance", n)       -- for the interface (shown by the health bars / unit stats later)
		return damage * (1 + n * STEP)
	end
	return damage
end

function gadget:UnitDestroyed(unitID)
	recent[unitID] = nil
	for _, r in pairs(recent) do r[unitID] = nil end
end

function gadget:GameFrame(frame)
	if frame % 90 ~= 0 then return end
	for t, r in pairs(recent) do        -- forget old hits so that the table does not grow
		local alive = false
		for a, f in pairs(r) do
			if frame - f > WINDOW then r[a] = nil else alive = true end
		end
		if not alive then recent[t] = nil; if Spring.ValidUnitID(t) then Spring.SetUnitRulesParam(t, "vb_resonance", 0) end end
	end
end
