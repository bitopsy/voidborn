function gadget:GetInfo()
	return {
		name = "Voidborn craters",
		desc = "Big blasts (a big unit or structure dying, Ctrl+D detonations) dig a crater with a raised rim into the ground",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return end

--------------------------------------------------------------------------------
-- What this does
--   * GG.VB_Crater(x, y, z, blastRadius)  digs a crater.  vb_explode.lua calls it for every Ctrl+D blast.
--   * every explosion of the death weapons vb_med / vb_big (explodeAs / selfDestructAs of the units)
--     that happens on the ground digs one as well.
--   The crater is a smooth bowl (depth falls off with the square of the distance) surrounded by a low
--   rim of the pushed-up earth.  The work is queued and done one crater per frame, so a mass detonation
--   spreads over a few frames instead of hitching one.  Everything runs in synced code (heightmap
--   changes have to), so every player sees the same ground.
--------------------------------------------------------------------------------

local MIN_BLAST       = 60      -- blasts smaller than this (radius in elmos) leave the ground alone
local RADIUS_FRACTION = 0.55    -- crater radius = blast radius * this ...
local MAX_RADIUS      = 240     -- ... but never more than this
local DEPTH_FRACTION  = 0.16    -- crater depth = crater radius * this ...
local MAX_DEPTH       = 48      -- ... but never more than this
local RIM_FRACTION    = 0.22    -- rim height = depth * this
local RIM_WIDTH       = 1.45    -- the rim ends at crater radius * this
local PER_FRAME       = 1       -- craters dug per game frame
local MAX_QUEUE       = 40      -- when more are waiting, the oldest are dropped
local DEATH_WEAPONS   = { "vb_med", "vb_big" }

local SQ = Game.squareSize or 8
local spGetGroundHeight = Spring.GetGroundHeight
local pending = {}              -- { x, z, blast }
local watched = {}              -- weaponDefID -> its area of effect

local function Dig(x, z, blast)
	local R = math.min(MAX_RADIUS, blast * RADIUS_FRACTION)
	local depth = math.min(MAX_DEPTH, R * DEPTH_FRACTION)
	local rimR = R * RIM_WIDTH
	local mx, mz = Game.mapSizeX, Game.mapSizeZ
	local x0 = math.max(0, math.floor((x - rimR) / SQ) * SQ)
	local x1 = math.min(mx, math.ceil((x + rimR) / SQ) * SQ)
	local z0 = math.max(0, math.floor((z - rimR) / SQ) * SQ)
	local z1 = math.min(mz, math.ceil((z + rimR) / SQ) * SQ)
	local rim = depth * RIM_FRACTION
	Spring.SetHeightMapFunc(function()
		for gx = x0, x1, SQ do
			for gz = z0, z1, SQ do
				local dx, dz = gx - x, gz - z
				local d = math.sqrt(dx * dx + dz * dz)
				local dh
				if d < R then
					local t = 1 - (d / R) * (d / R)
					dh = -depth * t * t
				elseif d < rimR then
					dh = rim * math.sin(math.pi * (d - R) / (rimR - R))
				end
				if dh then Spring.AddHeightMap(gx, gz, dh) end
			end
		end
	end)
end

function GG.VB_Crater(x, y, z, blast)
	if not x or not z or (blast or 0) < MIN_BLAST then return end
	local gh = spGetGroundHeight(x, z)
	if not gh or gh < -20 then return end               -- under water: nothing to dig
	if #pending >= MAX_QUEUE then table.remove(pending, 1) end
	pending[#pending + 1] = { x = x, z = z, blast = blast }
end

function gadget:Initialize()
	for _, name in ipairs(DEATH_WEAPONS) do
		local wd = WeaponDefNames[name]
		if wd then
			watched[wd.id] = wd.damageAreaOfEffect or wd.areaOfEffect or 0
			if Script.SetWatchExplosion then Script.SetWatchExplosion(wd.id, true)
			elseif Script.SetWatchWeapon then Script.SetWatchWeapon(wd.id, true) end
		end
	end
end

function gadget:Explosion(weaponDefID, px, py, pz)
	local aoe = watched[weaponDefID]
	if aoe and px then
		local gh = spGetGroundHeight(px, pz)
		if gh and py - gh < aoe * 0.7 then GG.VB_Crater(px, gh, pz, aoe) end   -- not for blasts high in the air
	end
	return false      -- never suppress the engine's own explosion
end

function gadget:GameFrame()
	for _ = 1, PER_FRAME do
		local c = table.remove(pending, 1)
		if not c then return end
		Dig(c.x, c.z, c.blast)
	end
end

function gadget:Shutdown() GG.VB_Crater = nil end
