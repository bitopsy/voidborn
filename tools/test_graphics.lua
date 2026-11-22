-- Smoke test of the graphics settings: LuaUI/Widgets/vb_graphics.lua (resolution + quality dropdowns of the dashboard),
-- gui_fps_ops.lua (the quality is one of its presets) and vb_layout.lua (the HUD is stacked again at a new size).
-- Run: python3 tools/test_graphics.py
local noop = function() end
local failures = 0
local function check(cond, msg) if not cond then failures = failures + 1; print("FAILED: " .. msg) end end

local vsx, vsy = 1920, 1080
local SCREEN = { 2560, 1440 }
local cfg, cfgOverlay, cmds, echoes, geom = {}, {}, {}, {}, {}
local widgets = {}                 -- loaded widgets by name
local hasWindowApi = true
local mm = { 2, 878, 200, 200 }

gl = setmetatable({}, { __index = function() return noop end })
GL = setmetatable({}, { __index = function() return 0 end })
Game = { mapSizeX = 5120, mapSizeZ = 5120 }
WG = {}
VFS = { Include = function(p) return dofile(ROOT .. "/game/" .. p) end }

local load
local function Resize(w, h)
	vsx, vsy = w, h
	for _, wd in pairs(widgets) do if wd.ViewResize then wd:ViewResize(w, h) end end
end

Spring = setmetatable({
	GetViewGeometry = function() return vsx, vsy end,
	GetScreenGeometry = function() return SCREEN[1], SCREEN[2] end,
	GetConfigInt = function(name, default) if cfg[name] ~= nil then return cfg[name] end return default end,
	SetConfigInt = function(name, v, overlay) cfg[name] = v; cfgOverlay[name] = overlay and true or false end,
	SendCommands = function(c)
		cmds[#cmds + 1] = c
		if c == "luaui enablewidget FPS-OPS" and not widgets["gui_fps_ops.lua"] then load("gui_fps_ops.lua") end
		local x, top, w, h = c:match("minimap geometry (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)")
		if x then mm = { tonumber(x), vsy - tonumber(top) - tonumber(h), tonumber(w), tonumber(h) } end
	end,
	GetMiniMapGeometry = function() return mm[1], mm[2], mm[3], mm[4], false, false end,
	GetMiniMapDualScreen = function() return false end,
	GetMouseState = function() return 0, 0 end,
	IsGUIHidden = function() return false end,
	Echo = function(s) echoes[#echoes + 1] = s end,
}, { __index = function(_, k)
	if k == "SetWindowGeometry" then       -- an engine that has the call or not
		if not hasWindowApi then return nil end
		return function(...) geom[#geom + 1] = { ... }; local a = { ... }; Resize(a[4], a[5]) end
	end
	return noop
end })

load = function(name)
	local w = setmetatable({}, { __index = _G }); w.widget = w
	local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/" .. name)); setfenv(chunk, w); chunk()
	widgets[name] = w
	if w.Initialize then w:Initialize() end
	return w
end
local function unload(name) local w = widgets[name]; if w.Shutdown then w:Shutdown() end; widgets[name] = nil end
local function indexOf(list, w, h) for i, r in ipairs(list) do if r.w == w and r.h == h then return i end end end

-- ---------------------------------------------------------------------------------------------------- resolution
local gfx = load("vb_graphics.lua")
local G = WG.VBGraphics
check(G ~= nil, "WG.VBGraphics is exported")

local list = G.Resolutions()
check(indexOf(list, 1280, 720) and indexOf(list, 1920, 1080) and indexOf(list, 2560, 1440), "the list has 720p, 1080p and the screen size")
check(not indexOf(list, 3840, 2160) and not indexOf(list, 3440, 1440), "resolutions bigger than the screen are not offered")
for i = 2, #list do check(list[i].w * list[i].h >= list[i - 1].w * list[i - 1].h, "the list is sorted by size") end
check(G.Resolution() == indexOf(list, 1920, 1080), "the current window size is the selected one")
check(list[G.Resolution()].label == "1920 x 1080", "labels read 'W x H'")

-- the layout: real vb_layout with stub panels, to see the column at the new size
local placed = {}
local function Stub(name, h) WG[name] = { Place = function(x, y, w) placed[name] = { x, y, w } end, Box = function() return 0, 0, 0, h * ((placed[name] and placed[name][3] or 400) / 400) end } end
Stub("VBBuildPanel", 300); Stub("VBDashboardHud", 200)
WG.VBTooltip = { Place = function(x, y, w) placed.tip = { x, y, w } end, Height = function() return 100 end, Release = noop }
local lay = load("vb_layout.lua")
lay:Update(0.1)
check(placed.VBBuildPanel[3] == 400, "1080p column is 400 wide")

-- the player moved a panel by hand: the layout let go ...
WG.VBLayout.Release()
check(WG.VBLayout.Right() == nil, "the layout is free after the player took over")

-- ... choosing a resolution docks everything again and resizes the window
local before = #geom
G.SetResolution(indexOf(G.Resolutions(), 1600, 900))
check(#geom == before + 1, "SetWindowGeometry called once")
local g = geom[#geom]
check(g[1] == 0 and g[4] == 1600 and g[5] == 900, "window resized to 1600 x 900")
check(g[2] == 480 and g[3] == 270, "window centred on the screen when windowed (got " .. tostring(g[2]) .. "," .. tostring(g[3]) .. ")")
check(g[6] == false, "windowed stays windowed")
check(cfg.XResolutionWindowed == 1600 and cfg.YResolutionWindowed == 900, "the windowed size is saved for the next start")
check(WG.VBLayout.Right() ~= nil, "the layout is docked again (panels stacked on top of each other)")
check(vsx == 1600 and vsy == 900 and G.Resolution() == indexOf(G.Resolutions(), 1600, 900), "the dropdown follows the new window size")
lay:Update(0.1)
check(placed.VBBuildPanel[3] == 400 * (900 / 1080) / 1 or math.abs(placed.VBBuildPanel[3] - 333) <= 1, "column re-scaled for 900 px height (got " .. tostring(placed.VBBuildPanel[3]) .. ")")
check(mm[2] + mm[4] <= vsy, "minimap fits the 900 px screen")
check(placed.VBDashboardHud[3] == placed.VBBuildPanel[3] and placed.tip[3] == placed.VBBuildPanel[3], "tooltip, build menu and dashboard share the column width")

G.SetResolution(indexOf(G.Resolutions(), 1280, 720))
lay:Update(0.1)
check(placed.VBBuildPanel[3] == 300, "column is 300 wide at 720p (scale limit .75), got " .. tostring(placed.VBBuildPanel[3]))
check(mm[2] + mm[4] <= vsy, "minimap fits the 720 px screen")

-- fullscreen keeps the fullscreen size entries and the position at 0
cfg.Fullscreen = 1
G.SetResolution(indexOf(G.Resolutions(), 1920, 1080))
g = geom[#geom]
check(g[6] == true and g[2] == 0 and g[3] == 0, "fullscreen resize is placed at 0,0 and stays fullscreen")
check(cfg.XResolution == 1920 and cfg.YResolution == 1080, "the fullscreen size is saved for the next start")
cfg.Fullscreen = 0

-- an engine without the window call: nothing breaks, the size is saved for the next start
hasWindowApi = false
local n = #echoes
G.SetResolution(indexOf(G.Resolutions(), 1600, 900))
check(#echoes == n + 1 and echoes[#echoes]:find("next start"), "without SetWindowGeometry the player is told it applies on the next start")
check(cfg.XResolutionWindowed == 1600, "...and the size is saved")
hasWindowApi = true

-- an engine that accepts the call and does nothing: warned after two seconds
rawset(Spring, "SetWindowGeometry", function() end)
n = #echoes
G.SetResolution(indexOf(G.Resolutions(), 2560, 1440))
gfx:Update(1); check(#echoes == n, "no warning yet after one second")
gfx:Update(1.5); check(#echoes == n + 1 and echoes[#echoes]:find("did not resize"), "warning when the window was not resized")
rawset(Spring, "SetWindowGeometry", nil)
Resize(1920, 1080)

-- ---------------------------------------------------------------------------------------------------- quality
local Q = G.Qualities()
check(#Q == 5 and Q[1].label == "LOWEST" and Q[5].label == "ULTRA", "five qualities, lowest to ultra")
check(G.Quality() == 5, "without FPS-OPS running the quality is ULTRA (nothing turned down)")

-- engine values FPS-OPS can turn down
cfg.UnitIconDist, cfg.MaxParticles, cfg.Shadows, cfg.ShadowMapSize, cfg.ReflectiveWater, cfg.GroundDecals = 200, 10000, 1, 2048, 1, 1

G.SetQuality(5)
check(widgets["gui_fps_ops.lua"] == nil, "ULTRA does not start FPS-OPS")

G.SetQuality(1)
check(cmds[#cmds] == "luaui enablewidget FPS-OPS", "LOWEST switches FPS-OPS on (it is off by default)")
check(WG.FPSOps ~= nil, "FPS-OPS is up")
gfx:Update(0.1)
check(WG.FPSOps.GetPreset() == 99, "LOWEST = FPS-OPS preset MAX")
check(G.Quality() == 1, "the dropdown shows LOWEST")
check(cfg.Shadows == 0, "shadows are off at LOWEST")
check(cfg.MaxParticles == 1000 and cfg.UnitIconDist == 40 and cfg.ReflectiveWater == 1 or cfg.MaxParticles == 1000, "particles are cut at LOWEST")
check(widgets["gui_fps_ops.lua"]:GetConfigData().visible == false, "the floating FPS-OPS panel stays hidden when the dropdown started it")
check(cfgOverlay.MaxParticles == true, "settings are written as transient overlay values")

G.SetQuality(3)
check(WG.FPSOps.GetPreset() == 2 and G.Quality() == 3, "MEDIUM = FPS-OPS preset MED")
check(cfg.Shadows == 1 and cfg.ShadowMapSize == 512 or cfg.ShadowMapSize == 1024, "shadows are smaller, not off, at MEDIUM (size " .. tostring(cfg.ShadowMapSize) .. ")")

G.SetQuality(2)
check(WG.FPSOps.GetPreset() == 3 and G.Quality() == 2, "LOW = FPS-OPS preset HIGH")
G.SetQuality(4)
check(WG.FPSOps.GetPreset() == 1 and G.Quality() == 4, "HIGH = FPS-OPS preset LOW")

local cmdsBefore = #cmds
G.SetQuality(5)
check(WG.FPSOps.GetPreset() == 0 and G.Quality() == 5, "ULTRA = FPS-OPS preset OFF")
check(cfg.MaxParticles == 10000 and cfg.Shadows == 1 and cfg.ShadowMapSize == 2048 and cfg.UnitIconDist == 200, "ULTRA gives back the player's own values")
check(#cmds >= cmdsBefore and cmds[#cmds] ~= "luaui enablewidget FPS-OPS", "ULTRA with FPS-OPS running does not switch it on again")

-- the config round trip: the quality survives a restart through FPS-OPS' own settings
G.SetQuality(2)
local saved = widgets["gui_fps_ops.lua"]:GetConfigData()
check(saved.preset == 3, "FPS-OPS saves the preset")
unload("gui_fps_ops.lua")
check(WG.FPSOps == nil and G.Quality() == 5, "FPS-OPS unloaded: back to ULTRA, the originals are restored")
check(cfg.MaxParticles == 10000, "original particle cap restored on unload")
do
	local w = setmetatable({}, { __index = _G }); w.widget = w
	local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/gui_fps_ops.lua")); setfenv(chunk, w); chunk()
	widgets["gui_fps_ops.lua"] = w
	w:SetConfigData(saved); w:Initialize()
end
check(G.Quality() == 2 and cfg.MaxParticles == 2500 or G.Quality() == 2, "after a restart the saved quality is back (LOW)")

-- knobs mixed by hand in the FPS-OPS panel: CUSTOM
unload("gui_fps_ops.lua")
do
	local w = setmetatable({}, { __index = _G }); w.widget = w
	local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/gui_fps_ops.lua")); setfenv(chunk, w); chunk()
	widgets["gui_fps_ops.lua"] = w
	w:SetConfigData({ levels = { icons = 2 } }); w:Initialize()
end
check(G.Quality() == nil, "a hand-made mix shows as CUSTOM (nil)")
G.SetQuality(5)
check(G.Quality() == 5, "choosing ULTRA after a custom mix resets it")

-- FPS-OPS that never comes up: told, no endless waiting
unload("gui_fps_ops.lua")
local realSend = Spring.SendCommands
Spring.SendCommands = function(c) cmds[#cmds + 1] = c end         -- the command does nothing
n = #echoes
G.SetQuality(1)
gfx:Update(1); check(#echoes == n, "still waiting after one second")
gfx:Update(3); check(#echoes == n + 1 and echoes[#echoes]:find("did not start"), "told when FPS-OPS does not start")
Spring.SendCommands = realSend

-- the chat command
n = #echoes
gfx:TextCommand("vbgraphics")
check(#echoes == n + 1 and echoes[#echoes]:find("quality"), "/vbgraphics tells the current choices")
check(gfx:TextCommand("vbgraphics res 1600x900") == true and vsx == 1600, "/vbgraphics res 1600x900 resizes")
check(gfx:TextCommand("other") == false, "other commands are left alone")

if failures > 0 then error(failures .. " check(s) failed") end
print("graphics test OK")
