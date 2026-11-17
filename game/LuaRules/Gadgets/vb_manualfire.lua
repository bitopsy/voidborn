-- Voidborn: manual-fire commands for FLYING commanders.
--
-- The engine's air command handler never offers the "manualfire" (D-gun) command, so a
-- commander with canFly = true cannot use its manualFire weapons the normal way.  This
-- gadget gives such units two custom map-target commands instead:
--
--   vbdgun   (key D)  -> the unit's FIRST  manualFire weapon  (Devour)
--   vbdestab (key Q)  -> the unit's SECOND manualFire weapon  (Destabilisation Gun, "Q-Gun")
--
-- The shot is a projectile of that weapon spawned at the unit's muzzle, flying at the clicked
-- point.  Energy cost, reload and range are taken from the weapondef.  The commands fire
-- immediately and are not queued.
--
--   game/LuaRules/Gadgets/vb_manualfire.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Manual Fire", desc = "D-gun commands for flying commanders",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local FPS = 30
local CMD_BASE = 35000   -- slot 1 -> 35000, slot 2 -> 35001
local SLOTS = {
	{ action = "vbdgun",   name = "D-Gun",      tip = "Devour: fire the D-gun at a point (D)" },
	{ action = "vbdestab", name = "Q-Gun",      tip = "Q-Gun (Destabilisation Gun): stun everything around a point (Q)" },
}

local unitSlots = {}   -- unitDefID -> { [slot] = weaponNumber }
local cmdSlot = {}     -- cmdID -> slot
local nextFire = {}    -- unitID -> { [slot] = frame }

local function Say(teamID, msg) Spring.SendMessageToTeam(teamID, "[VB] " .. msg) end

function gadget:Initialize()
	for i = 1, #SLOTS do cmdSlot[CMD_BASE + i - 1] = i end
	for defID, ud in pairs(UnitDefs) do
		if ud.canFly then
			local slot = 0
			for wn, w in ipairs(ud.weapons or {}) do
				local wd = w.weaponDef and WeaponDefs[w.weaponDef]
				if wd and wd.manualFire and slot < #SLOTS then
					slot = slot + 1
					unitSlots[defID] = unitSlots[defID] or {}
					unitSlots[defID][slot] = wn
				end
			end
		end
	end
	for _, uid in ipairs(Spring.GetAllUnits()) do gadget:UnitCreated(uid, Spring.GetUnitDefID(uid)) end
end

function gadget:UnitCreated(uid, defID)
	local slots = unitSlots[defID]
	if not slots then return end
	for slot in pairs(slots) do
		Spring.InsertUnitCmdDesc(uid, {
			id = CMD_BASE + slot - 1, type = CMDTYPE.ICON_MAP, name = SLOTS[slot].name,
			action = SLOTS[slot].action, cursor = "Attack", tooltip = SLOTS[slot].tip, hidden = false,
		})
	end
end

function gadget:UnitDestroyed(uid) nextFire[uid] = nil end

local function Fire(uid, defID, teamID, slot, tx, ty, tz)
	local wn = unitSlots[defID][slot]
	local wdID = UnitDefs[defID].weapons[wn].weaponDef
	local wd = WeaponDefs[wdID]
	local frame = Spring.GetGameFrame()

	if select(2, Spring.GetUnitIsStunned(uid)) then return end
	local nf = nextFire[uid]
	if nf and nf[slot] and frame < nf[slot] then
		Say(teamID, SLOTS[slot].name .. " is reloading (" .. string.format("%.1f", (nf[slot] - frame) / FPS) .. "s)")
		return
	end

	-- muzzle position
	local px, py, pz
	local pieces = Spring.GetUnitPieceMap(uid)
	if pieces and pieces.muzzle then px, py, pz = Spring.GetUnitPiecePosDir(uid, pieces.muzzle) end
	if not px then local _, _, _, mx, my, mz = Spring.GetUnitPosition(uid, true); px, py, pz = mx, my, mz end

	local dx, dy, dz = tx - px, ty - py, tz - pz
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	local range = wd.range or 300
	local ux, _, uz = Spring.GetUnitPosition(uid)
	if math.sqrt((tx - ux) ^ 2 + (tz - uz) ^ 2) > range then
		Say(teamID, SLOTS[slot].name .. ": target out of range (" .. math.floor(range) .. ")")
		return
	end
	if dist < 1 then return end

	-- energy
	local cost = wd.energyCost or wd.energyPerShot or 0
	if cost > 0 then
		local cur = Spring.GetTeamResources(teamID, "energy")
		if not cur or cur < cost or not Spring.UseTeamResource(teamID, "energy", cost) then
			Say(teamID, SLOTS[slot].name .. ": not enough energy (" .. cost .. ")")
			return
		end
	end

	-- speed in elmos per frame
	local v = wd.projectilespeed or wd.projectileSpeed or ((wd.weaponVelocity or 300) / FPS)
	if v > 30 then v = v / FPS end
	local ttl = wd.noExplode and math.ceil(range / v) or (math.ceil(dist / v) + 15)

	if GG.VBCloak then GG.VBCloak.Off(uid) end   -- firing gives the commander away
	Spring.SpawnProjectile(wdID, {
		pos = { px, py, pz }, speed = { dx / dist * v, dy / dist * v, dz / dist * v },
		owner = uid, team = teamID, ttl = ttl, gravity = 0, maxRange = range,
	})
	nextFire[uid] = nextFire[uid] or {}
	nextFire[uid][slot] = frame + math.floor((wd.reload or 1) * FPS)
	Spring.PlaySoundFile(wd.soundStart or "", 1.0, px, py, pz)
end

function gadget:AllowCommand(uid, defID, teamID, cmdID, params, opts, tag, fromSynced)
	local slot = cmdSlot[cmdID]
	if not slot then return true end
	if unitSlots[defID] and unitSlots[defID][slot] and params and params[3] then
		Fire(uid, defID, teamID, slot, params[1], params[2], params[3])
	end
	return false   -- never queued: the shot has been fired (or refused) right now
end
