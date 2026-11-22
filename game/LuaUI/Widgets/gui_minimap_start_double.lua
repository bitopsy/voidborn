function widget:GetInfo()
	return {
		name    = "Minimap Start Double",
		desc    = "Doubles the minimap size at game start (and after a resolution change).",
		author  = "goddot",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 100000, -- load after other minimap widgets so we get the last word
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local SCALE      = 1.4   -- size multiplier
local DELAY      = 1.5   -- seconds to wait so the main minimap widget finishes its own setup
local MAX_WIDTH  = 0.60  -- never exceed this fraction of screen width
local MAX_HEIGHT = 0.60  -- never exceed this fraction of screen height

--------------------------------------------------------------------------------

local spGetMiniMapGeometry = Spring.GetMiniMapGeometry
local spGetViewGeometry    = Spring.GetViewGeometry
local spSendCommands       = Spring.SendCommands

local timer = 0
local pending = true

local function apply()
	local vsx, vsy = spGetViewGeometry()
	-- px, py: bottom-left corner of the minimap, py measured from the bottom of the screen
	local px, py, sx, sy = spGetMiniMapGeometry()
	if not sx or sx <= 0 then return false end

	local nw = sx * SCALE
	local nh = sy * SCALE

	-- keep it inside the allowed fraction of the screen, preserving aspect ratio
	local k = math.min(1, (vsx * MAX_WIDTH) / nw, (vsy * MAX_HEIGHT) / nh)
	nw, nh = math.floor(nw * k), math.floor(nh * k)

	-- the "minimap geometry" command wants y from the TOP of the screen
	-- grow upwards/rightwards, keeping the bottom-left corner where it is
	local topY = vsy - (py + nh)
	spSendCommands(string.format("minimap geometry %d %d %d %d", px, math.max(0, topY), nw, nh))
	return true
end

function widget:Update(dt)
	if not pending then return end
	timer = timer + dt
	if timer >= DELAY then
		if apply() then pending = false end
	end
end

function widget:ViewResize()
	-- resolution changed: size will be reset by the engine / main minimap widget, redo it
	pending = true
	timer = 0
end
