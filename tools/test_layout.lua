-- Smoke test of LuaUI/Widgets/vb_layout.lua and the tooltip slot with a mock engine.
-- Run: python3 tools/test_layout.py
local noop = function() end
local failures = 0
local function check(cond, msg) if not cond then failures = failures + 1; print("FAILED: " .. msg) end end

local vsx, vsy = 1920, 1080
local cmds = {}
local mm = { 2, 878, 200, 200 }     -- minimap geometry as the engine reports it (bottom left origin): the engine default at 1080p
gl = setmetatable({}, { __index = function() return noop end })
GL = setmetatable({}, { __index = function() return 0 end })
Game = { mapSizeX = 5120, mapSizeZ = 5120 }
Spring = setmetatable({
	GetViewGeometry = function() return vsx, vsy end,
	SendCommands = function(c)
		local x, top, w, h = c:match("minimap geometry (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)")
		if x then cmds[#cmds + 1] = c; mm = { tonumber(x), vsy - tonumber(top) - tonumber(h), tonumber(w), tonumber(h) } end
	end,
	GetMiniMapGeometry = function() if mm then return mm[1], mm[2], mm[3], mm[4], false, false end end,
	GetMiniMapDualScreen = function() return false end,
	GetCurrentTooltip = function() return "Position: 100, 200\nElevation: 3\nTerrain type: asteroid\nA long line of text that has to be wrapped inside the narrow plate of the default layout column" end,
	IsGUIHidden = function() return false end,
	Echo = noop,
}, { __index = function() return noop end })
VFS = { Include = function(p) return dofile(ROOT .. "/game/" .. p) end }
WG = {}

local function load(name)
	local w = setmetatable({}, { __index = _G }); w.widget = w
	local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/" .. name)); setfenv(chunk, w); chunk()
	if w.Initialize then w:Initialize() end
	return w
end

-- stub panels: fixed sizes, they record where the layout put them
local placed = {}
-- the stubs scale with the column width like the real panels (h is the height at a 400 px wide column)
local function Stub(name, h) WG[name] = { Place = function(x, y, w) placed[name] = { x, y, w } end, Box = function() return 0, 0, 0, h * ((placed[name] and placed[name][3] or 400) / 400) end } end
Stub("VBBuildPanel", 300); Stub("VBDashboardHud", 200)

local tip = load("vb_tooltip.lua")
local lay = load("vb_layout.lua")

local function step() lay:Update(0.1) end
step()
local W = placed.VBBuildPanel[3]
check(W == 400, "column width at 1080p is the doubled default minimap, 400 (got " .. tostring(W) .. ")")
check(placed.VBDashboardHud[3] == W, "dashboard has the column width")
local tipH = WG.VBTooltip.Height()
check(placed.VBBuildPanel[2] > 8 + tipH - 1, "build menu is above the tooltip")
check(placed.VBDashboardHud[2] > placed.VBBuildPanel[2] + 300 - 1, "dashboard is above the build menu")
check(mm and mm[3] == 400 and mm[4] == 400, "minimap is 400 x 400 (twice the engine default of 200 x 200)")
check(mm and mm[2] >= placed.VBDashboardHud[2] + 200, "minimap is above the dashboard")
check(mm and mm[2] + mm[4] <= vsy, "minimap fits on the screen at 1080p")
check(#cmds == 1, "the minimap geometry is sent once while nothing changes (sent " .. #cmds .. ")")
step(); step()
check(#cmds == 1, "no repeated geometry commands")

-- tooltip: fixed slot, wrapped to the column width
tip:Update(); tip:DrawScreen()

-- other resolutions
for _, r in ipairs({ { 1280, 720, 300 }, { 2560, 1440, 533 }, { 3840, 2160, 640 } }) do
	vsx, vsy = r[1], r[2]; lay:ViewResize(vsx, vsy); for _ = 1, 40 do step() end
	local w = placed.VBBuildPanel[3]
	-- the column is as wide as designed, or shrinks when the stack would not fit the screen height
	check(w == r[3] or (w < r[3] and w >= r[3] * 0.5), r[1] .. "x" .. r[2] .. ": column width " .. r[3] .. " or fitted (got " .. tostring(w) .. ")")
	check(mm[3] == w and math.abs(mm[4] - w) <= 1, r[1] .. "x" .. r[2] .. ": square minimap, as wide as the column")
	check(mm[2] + mm[4] <= vsy, r[1] .. "x" .. r[2] .. ": the minimap stays on the screen")
	local dashTop = placed.VBDashboardHud[2] + 200 * (w / 400)
	check(mm[2] >= dashTop - 2, r[1] .. "x" .. r[2] .. ": the minimap does not cover the dashboard")
end

-- a wide map keeps the aspect ratio of the map
vsx, vsy = 1920, 1080; lay:ViewResize(vsx, vsy); Game.mapSizeX, Game.mapSizeZ = 10240, 5120; for _ = 1, 40 do step() end
check(mm[4] * 2 == mm[3] or math.abs(mm[4] * 2 - mm[3]) <= 1, "2:1 map: minimap keeps 2:1")
Game.mapSizeX, Game.mapSizeZ = 5120, 5120; for _ = 1, 40 do step() end

-- the player moves a panel: the layout lets go
local before = #cmds
WG.VBLayout.Release()
vsx, vsy = 1600, 900; lay:ViewResize(vsx, vsy); step()
check(#cmds == before, "no commands once the layout is released")
check(WG.VBLayout.Right() == nil, "Right() is nil when not docked")
vsx, vsy = 1920, 1080; lay:ViewResize(vsx, vsy)
lay:TextCommand("vblayout")
step()
check(#cmds > before, "/vblayout docks it again")

-- the player resizes the minimap by hand: the layout lets go
mm = { mm[1], mm[2], mm[3] + 80, mm[4] + 80 }
lay:Update(2); lay:Update(2)
check(WG.VBLayout.Right() == nil, "a minimap resized by the player releases the layout")

if failures > 0 then error(failures .. " check(s) failed") end
print("layout test OK")
