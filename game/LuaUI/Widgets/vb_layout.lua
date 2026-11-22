function widget:GetInfo()
	return { name = "Voidborn Default Layout", desc = "Default HUD layout for every resolution: tooltip, build menu, dashboard and minimap stacked in one column at the bottom left",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 20, enabled = true }
end

-- THE DEFAULT LAYOUT (what a new player sees)
--
--      +-----------+
--      |  minimap  |   2 x the engine's default size (the engine default is 200 x 200 pixels, kept in the
--      +-----------+   aspect of the map; here 400 x 400 at 1080p)
--      | dashboard |
--      +-----------+
--      | build menu|   expanded
--      +-----------+
--      |  tooltip  |   fixed height, so nothing above it jumps when the text changes
--      +-----------+
--
-- The four share one width: the width of the minimap.  Everything is scaled by the height of the screen
-- relative to 1080p (limited to 0.75 .. 1.6), so the column looks the same on every resolution.
--
-- The panels keep their own sizes while they are docked here: this widget sets their position and width
-- every frame and stacks them from the bottom up, whatever their height is at the moment (the build menu grows
-- with the number of tiles, the dashboard folds).  As soon as the player drags or scales one of the panels,
-- or moves or resizes the minimap, the layout lets go of everything and the player's own arrangement is saved
-- with the other widget settings.
--
--   /vblayout          dock everything in the default layout again
--   /vblayout free     let go of everything (same as dragging a panel)
--
-- A change of the screen resolution re-stacks the column by itself while it is docked (ViewResize); the graphics
-- settings of the dashboard (vb_graphics.lua) call WG.VBLayout.Dock() as well, so the panels also come back
-- together when the player had arranged them by hand for the old resolution.

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local MM_DEFAULT = 200        -- the engine's default minimap size (MiniMapGeometry "2 2 200 200")
local MM_FACTOR  = 2          -- the layout starts with double that
local REF_HEIGHT = 1080       -- screen height the pixel sizes are meant for
local MM_BUTTONS = 18         -- the engine draws the minimap buttons in a strip under the minimap (16 px)

local vsx, vsy = Spring.GetViewGeometry()
local docked = true
local lastH = {}              -- last height seen of each panel (a panel that is closed keeps its place)
local sentKey, sentAt, want = nil, 0, nil
local clock = 0
local fit = 1                -- 0.5 .. 1: how much the whole column is shrunk so that it fits the screen height
local MIN_FIT = 0.5

local function Scale() return max(0.75, min(1.6, vsy / REF_HEIGHT)) end

-- the minimap at the doubled default size; its width is the width of the whole column
local function Geometry()
	local mx, mz = Game.mapSizeX or 1, Game.mapSizeZ or 1
	if mx <= 0 or mz <= 0 then mx, mz = 1, 1 end
	local w = MM_DEFAULT * MM_FACTOR * sqrt(mx / mz) * Scale()
	w = floor(min(w, vsx * 0.33) * fit + 0.5)
	return w, floor(w * mz / mx + 0.5)
end

local function Release(silent)
	if not docked then return end
	docked, want = false, nil
	if WG.VBTooltip and WG.VBTooltip.Release then WG.VBTooltip.Release() end
	if not silent then Spring.Echo("[VB] layout: your own arrangement now (/vblayout puts the default back)") end
end

-- dock everything in the default layout again (what /vblayout does); also used when the resolution is changed
local function Dock(silent)
	docked, sentKey, fit = true, nil, 1
	if not silent then Spring.Echo("[VB] layout: default layout (tooltip, build menu, dashboard, minimap)") end
end

WG.VBLayout = {
	Release = function() Release() end,
	Dock = function() Dock(true) end,
	-- right edge of the column (so other panels can keep clear of it), nil when the layout is not docked
	Right = function()
		if not docked then return nil end
		return floor(8 * Scale() + 0.5) + (Geometry()) + 8
	end,
}

local function MinimapManaged()
	if not Spring.GetMiniMapGeometry then return false end
	if Spring.GetMiniMapDualScreen and Spring.GetMiniMapDualScreen() then return false end
	return Spring.GetMiniMapGeometry() ~= nil
end

local function Stack()
	local k = Scale()
	local W, mmH = Geometry()
	local margin, gap = floor(8 * k + 0.5), floor(6 * k + 0.5)
	local x, y = margin, margin

	local function Panel(name, p)
		if not p then return end
		p.Place(x, y, W)
		local _, _, _, h = p.Box()
		if h then lastH[name] = h end
		h = lastH[name]
		if h and h > 0 then y = y + h + gap end
	end

	-- bottom: the tooltip, a fixed slot
	local tip = WG.VBTooltip
	if tip then
		tip.Place(x, y, W)
		local th = tip.Height()
		if th > 0 then y = y + th + gap end
	end
	Panel("build", WG.VBBuildPanel)
	Panel("dash", WG.VBDashboardHud)

	-- fit the column to the screen: tooltip + build menu + dashboard + minimap must stay inside the height.
	-- Too tall -> shrink the whole column (width, so every panel scales with it); lots of room -> grow back to full size.
	local top_free = vsy - margin
	local used = (y - gap) + MM_BUTTONS + mmH                  -- what the column needs with the sizes of this frame
	if used > top_free then
		fit = max(MIN_FIT, fit * top_free / used)
	elseif fit < 1 and used * 1.03 < top_free then
		fit = min(1, fit * 1.02)
	end

	-- top: the minimap (at the smallest fit it is squeezed in height rather than pushed over the dashboard)
	if MinimapManaged() then
		local bottom = y - gap + MM_BUTTONS
		local mh = mmH
		if bottom + mh > top_free then mh = max(floor(80 * k), floor(top_free - bottom)) end
		local top = floor(max(0, vsy - (bottom + mh)))              -- the engine counts from the top of the screen
		local key = string.format("%d %d %d %d", x, top, W, mh)
		if key ~= sentKey then
			sentKey, sentAt = key, clock
			want = { x = x, bottom = vsy - top - mh, w = W, h = mh, fits = (vsy - (bottom + mh)) >= 0 }
			Spring.SendCommands("minimap geometry " .. key)
		end
	end
end

-- the minimap is moved or resized by the player (drag the strip under it)
local function CheckMinimap()
	if not (want and want.fits) or clock - sentAt < 1 then return end
	local px, py, sx, sy, minimized, maximized = Spring.GetMiniMapGeometry()
	if not px or minimized or maximized then return end
	if math.abs(sx - want.w) > 2 or math.abs(sy - want.h) > 2 or math.abs(px - want.x) > 2 or math.abs(py - want.bottom) > 2 then
		Release()
	end
end

function widget:Update(dt)
	clock = clock + dt
	if not docked then return end
	Stack()
	CheckMinimap()
end

function widget:ViewResize(w, h) vsx, vsy = w, h; sentKey = nil; fit = 1 end

function widget:TextCommand(cmd)
	local word, arg = cmd:match("^(%S+)%s*(%S*)")
	if word ~= "vblayout" then return false end
	if arg == "free" or arg == "off" then
		Release()
	else
		Dock()
	end
	return true
end

function widget:Initialize()
	Spring.Echo("[VB] default layout: " .. (docked and "docked" or "free") .. " (/vblayout, /vblayout free)")
end

function widget:Shutdown() WG.VBLayout = nil end

function widget:GetConfigData() return { docked = docked } end
function widget:SetConfigData(d)
	if type(d) == "table" and d.docked == false then docked = false end
end
