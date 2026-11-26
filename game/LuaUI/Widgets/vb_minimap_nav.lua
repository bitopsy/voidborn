function widget:GetInfo()
	return { name = "Voidborn Minimap Navigation", desc = "Left click or drag on the minimap moves the camera on the big map (/vbminimapnav toggles it)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL",
		layer = -100000,   -- first in line: nothing else gets to swallow the click before we see it
		enabled = true }
end

--[[
  MINIMAP NAVIGATION

  Left click on the minimap: the camera jumps there.  Keep the button down and drag: the camera follows.

  It stays out of the way when it should:
    - a command is armed (move, attack, build ...): the engine then gives the order on the minimap, as usual
    - any other mouse button: right click orders, middle click ... are the engine's
    - the minimap is rotated: the engine's own handling is used (only the normal orientation is converted here)

  /vbminimapnav          toggle on / off (saved with the other widget settings)
]]

local spGetMiniMapGeometry = Spring.GetMiniMapGeometry
local spIsAboveMiniMap     = Spring.IsAboveMiniMap
local spGetActiveCommand   = Spring.GetActiveCommand
local spSetCameraTarget    = Spring.SetCameraTarget
local spGetGroundHeight    = Spring.GetGroundHeight
local spGetMiniMapRotation = Spring.GetMiniMapRotation

local enabled = true
local dragging = false

local function Clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

-- screen position over the minimap -> world x, z (nil when the minimap is not where we can tell)
local function ToWorld(mx, my)
	local px, py, sx, sy = spGetMiniMapGeometry()          -- px, py: bottom left corner, measured from the bottom of the screen
	if not px or not sx or sx <= 0 or sy <= 0 then return nil end
	local u = Clamp((mx - px) / sx, 0, 1)
	local v = Clamp((my - py) / sy, 0, 1)
	return u * Game.mapSizeX, (1 - v) * Game.mapSizeZ       -- the top of the minimap is z = 0
end

local function Goto(mx, my, smooth)
	local x, z = ToWorld(mx, my)
	if not x then return false end
	spSetCameraTarget(x, spGetGroundHeight(x, z) or 0, z, smooth or 0)
	return true
end

local function Usable()
	if not enabled then return false end
	if Spring.GetMiniMapDualScreen and Spring.GetMiniMapDualScreen() then return false end
	if spGetMiniMapRotation and (spGetMiniMapRotation() or 0) ~= 0 then return false end
	return true
end

function widget:MousePress(x, y, button)
	if button ~= 1 or not Usable() then return false end
	if not (spIsAboveMiniMap and spIsAboveMiniMap(x, y)) then return false end
	if spGetActiveCommand() then return false end           -- an armed command: the engine gives the order
	if Goto(x, y, 0.1) then dragging = true; return true end
	return false
end

function widget:MouseMove(x, y)
	if dragging then Goto(x, y, 0) end
end

function widget:MouseRelease() dragging = false end

function widget:TextCommand(cmd)
	if cmd ~= "vbminimapnav" then return false end
	enabled = not enabled
	Spring.Echo("[VB] minimap navigation: " .. (enabled and "on" or "off"))
	return true
end

function widget:GetConfigData() return { enabled = enabled } end
function widget:SetConfigData(d) if type(d) == "table" and d.enabled == false then enabled = false end end
