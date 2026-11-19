-- Voidborn 0.16: POISON and SCENT, the tricks of the Miasma Bloom (the Nose).
--
-- A weapon with customParams.vb_poison_dps / vb_poison_secs poisons what it hits:
--   * every hit adds a poison STACK worth vb_poison_dps damage per second; at most MAX_STACKS (5) stacks
--     per unit (the oldest drops out) and all of them last until vb_poison_secs after the LAST hit;
--   * the damage is dealt twice a second as plain damage credited to the poisoner (experience counts);
--   * and the target is SCENTED: for SCENT_SECS (10) the poisoner's side sees it (position, type) through
--     the fog of war.  The mark is made with Spring.SetUnitLosState + Spring.SetUnitLosMask, which keeps the
--     state fixed; it is removed again when the scent runs out or the unit dies.
-- Friendly fire does not poison.  Mod options: poison_scale (damage multiplier, 1.0), scent_secs (10; 0 = no scent).
--
--   game/LuaRules/Gadgets/vb_miasma.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Miasma", desc = "Miasma weapons poison what they hit and scent it for the Bloom",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local FPS = 30
local TICK = 15                                   -- poison is applied every this many frames
local MAX_STACKS = 5
local opts = Spring.GetModOptions() or {}
local SCALE = tonumber(opts.poison_scale) or 1.0
local SCENT_SECS = tonumber(opts.scent_secs) or 10

local poisonW = {}        -- weaponDefID -> { dps, secs }
local poisoned = {}       -- unitID -> { stacks = { dps, ... }, untilFrame, by = attackerID, byTeam = teamID }
local scented = {}        -- unitID -> { [allyTeam] = untilFrame }

function gadget:Initialize()
	for id, wd in pairs(WeaponDefs) do
		local cp = wd.customParams
		if cp and cp.vb_poison_dps then
			poisonW[id] = { dps = tonumber(cp.vb_poison_dps) or 0, secs = tonumber(cp.vb_poison_secs) or 6 }
		end
	end
	if next(poisonW) == nil then gadgetHandler:RemoveGadget(self) end
end

-- keep a unit visible to an ally team (or let go of it); every call is guarded: a missing or changed engine call must not break the game
local function Mark(uid, allyTeam, on)
	if not (Spring.SetUnitLosState and Spring.SetUnitLosMask) then return end
	pcall(function()
		if on then
			local st = { los = true, radar = true, prevLos = true, contRadar = true }
			Spring.SetUnitLosState(uid, allyTeam, st)
			Spring.SetUnitLosMask(uid, allyTeam, st)
		else
			Spring.SetUnitLosMask(uid, allyTeam, 0)
		end
	end)
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	local w = poisonW[weaponDefID]
	if not w or paralyzer or (damage or 0) <= 0 then return end
	if attackerTeam and unitTeam and Spring.AreTeamsAllied(attackerTeam, unitTeam) then return end
	local frame = Spring.GetGameFrame()
	local p = poisoned[unitID]
	if not p then p = { stacks = {} }; poisoned[unitID] = p end
	p.stacks[#p.stacks + 1] = w.dps
	if #p.stacks > MAX_STACKS then table.remove(p.stacks, 1) end
	p.untilFrame = frame + w.secs * FPS
	p.by, p.byTeam = attackerID, attackerTeam
	Spring.SetUnitRulesParam(unitID, "vb_poison", #p.stacks)
	if SCENT_SECS > 0 and attackerTeam then
		local ally = select(6, Spring.GetTeamInfo(attackerTeam, false))
		if ally then
			local s = scented[unitID]
			if not s then s = {}; scented[unitID] = s end
			if not s[ally] then Mark(unitID, ally, true) end
			s[ally] = frame + SCENT_SECS * FPS
		end
	end
end

local function Clear(uid)
	poisoned[uid] = nil
	local s = scented[uid]
	if s then
		if Spring.ValidUnitID(uid) then for ally in pairs(s) do Mark(uid, ally, false) end end
		scented[uid] = nil
	end
end

function gadget:UnitDestroyed(unitID)
	poisoned[unitID] = nil; scented[unitID] = nil
	for _, p in pairs(poisoned) do if p.by == unitID then p.by = nil end end
end

function gadget:GameFrame(frame)
	if frame % TICK ~= 0 then return end
	for uid, p in pairs(poisoned) do
		if not Spring.ValidUnitID(uid) or Spring.GetUnitIsDead(uid) then
			poisoned[uid] = nil
		elseif frame >= p.untilFrame then
			p.stacks = {}
			Spring.SetUnitRulesParam(uid, "vb_poison", 0)
			poisoned[uid] = nil
		else
			local sum = 0
			for _, d in ipairs(p.stacks) do sum = sum + d end
			local by = p.by
			if by and not Spring.ValidUnitID(by) then by = nil end
			Spring.AddUnitDamage(uid, sum * SCALE * TICK / FPS, 0, by)     -- weaponDefID stays unset: this damage never poisons again
		end
	end
	for uid, s in pairs(scented) do
		if not Spring.ValidUnitID(uid) then
			scented[uid] = nil
		else
			local any = false
			for ally, untilFrame in pairs(s) do
				if frame >= untilFrame then s[ally] = nil; Mark(uid, ally, false) else any = true end
			end
			if not any then scented[uid] = nil end
		end
	end
end
