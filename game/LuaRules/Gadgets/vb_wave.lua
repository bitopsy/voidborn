-- Voidborn 0.19: SINE WAVE, the snaking shells of the Miasma Bloom (the Nose).
--
-- A weapon with customParams.vb_wave_amp (elmos) and vb_wave_len (elmos) flies in a sine wave: the shell swings out to the side by up to
-- `amp` and back once every `len` elmos of its flight, starting at the middle of its path.  The swing is added on top of whatever the engine
-- does to the shell (gravity, speed), so the shell still lands where it was aimed, give or take `amp`.  Successive shells swing to
-- opposite sides first.  The shells are slow and the wave makes them easy to sidestep: they are balanced by hitting harder (see
-- tools/gen_specials.py), and their trail (vb_miasma_wave) keeps the snaking path visible.
--
--   game/LuaRules/Gadgets/vb_wave.lua

function gadget:GetInfo()
	return {
		name = "Voidborn Wave", desc = "Miasma wave shells fly in a sine wave",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local waveW = {}              -- weaponDefID -> { amp, len }
local live = {}               -- projectileID -> { amp, om, rx, rz, age, off, sign }
local flip = 1

function gadget:Initialize()
	for id, wd in pairs(WeaponDefs) do
		local cp = wd.customParams
		if cp and cp.vb_wave_amp then
			waveW[id] = { amp = tonumber(cp.vb_wave_amp) or 0, len = math.max(tonumber(cp.vb_wave_len) or 100, 20) }
			if Script.SetWatchWeapon then Script.SetWatchWeapon(id, true) end
		end
	end
	if next(waveW) == nil then gadgetHandler:RemoveGadget(self) end
end

function gadget:ProjectileCreated(proID, proOwnerID, weaponDefID)
	local w = waveW[weaponDefID]
	if not w or w.amp <= 0 then return end
	local vx, _, vz = Spring.GetProjectileVelocity(proID)
	if not vx then return end
	local sp = math.sqrt(vx * vx + vz * vz)               -- elmos per frame along the ground
	if sp < 0.5 then return end
	flip = -flip
	live[proID] = { amp = w.amp, om = 2 * math.pi * sp / w.len, rx = vz / sp, rz = -vx / sp, age = 0, off = 0, sign = flip }
end

function gadget:ProjectileDestroyed(proID) live[proID] = nil end

function gadget:GameFrame()
	for id, p in pairs(live) do
		local x, y, z = Spring.GetProjectilePosition(id)
		if not x then
			live[id] = nil
		else
			p.age = p.age + 1
			local off = p.sign * p.amp * math.sin(p.om * p.age)
			local d = off - p.off
			p.off = off
			Spring.SetProjectilePosition(id, x + p.rx * d, y, z + p.rz * d)
		end
	end
end
