function widget:GetInfo()
	return { name = "Voidborn Graphics", desc = "Screen resolution and graphics quality (lowest .. ultra, built on FPS-OPS) for the GRAPHICS panel of the dashboard settings; /vbgraphics",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 21, enabled = true }
end

-- GRAPHICS SETTINGS
--
-- Two dropdowns in the SETTINGS page of the dashboard (Ctrl+Shift+D), both driven from here through WG.VBGraphics:
--
--   RESOLUTION  resizes the window.  The HUD is stacked again in the default layout column (vb_layout.lua) at the
--               new size, also when the player had moved the panels by hand for the old resolution.
--   QUALITY     LOWEST  LOW  MEDIUM  HIGH  ULTRA, one FPS-OPS preset each (gui_fps_ops.lua): the lower the quality,
--               the more of its knobs are turned down (icons from afar, draw distances, particles, shadows, water,
--               decals, effect widgets).  ULTRA turns nothing down: the player's own engine settings.
--               FPS-OPS is a widget that is off by default; choosing a quality switches it on (without its floating
--               panel; /fpsops shows that, with the benchmark).
--
--   /vbgraphics                          list the choices
--   /vbgraphics quality lowest|low|medium|high|ultra
--   /vbgraphics res 1600x900
--
-- WHEN THE GAME LOADS  (and again at the game start, when the loading screen is gone) the HUD is stacked in the
-- default layout column at the real window size, and every widget is told that size (ViewResize), so none of them keeps
-- positions or sizes that were worked out for an earlier resolution.  A moment is waited first, so that the layout
-- widget and the others are there.
--
-- Nothing here is saved by this widget: FPS-OPS keeps the quality with its own settings.  The window size is never
-- remembered from an earlier session either: whenever the window really has a size, that size is written to BOTH
-- config pairs (windowed and fullscreen), so no old value is left behind for the next start to pick up.

local floor, max, min = math.floor, math.max, math.min

--------------------------------------------------------------------------------
-- quality: lowest .. ultra  ->  FPS-OPS preset (0 = nothing turned down, 99 = everything turned down)
--------------------------------------------------------------------------------
local QUALITIES = {
	{ id = "lowest", label = "LOWEST", preset = 99, tip = { "FPS-OPS at maximum: units are icons early, short draw distances,", "few particles, no shadows or decals, basic water, effect widgets off" } },
	{ id = "low",    label = "LOW",    preset = 3,  tip = { "FPS-OPS at level 3 of every setting" } },
	{ id = "medium", label = "MEDIUM", preset = 2,  tip = { "FPS-OPS at level 2 of every setting" } },
	{ id = "high",   label = "HIGH",   preset = 1,  tip = { "FPS-OPS at level 1: a light touch" } },
	{ id = "ultra",  label = "ULTRA",  preset = 0,  tip = { "Nothing turned down: your own engine settings" } },
}
local ULTRA = #QUALITIES
local START_WAIT = 3              -- seconds FPS-OPS gets to start after it was switched on

local want = nil                  -- preset waiting for FPS-OPS to come up
local wantAge = 0
local startedByUs = false         -- FPS-OPS was off and this widget switched it on: keep its panel hidden

local function QualityIndex()
	local F = WG.FPSOps
	if not F then return ULTRA end                      -- FPS-OPS is not running: nothing is turned down
	local p = F.GetPreset()
	for i, q in ipairs(QUALITIES) do if q.preset == p then return i end end
	return nil                                          -- the player mixed the knobs by hand in the FPS-OPS panel
end

local function ApplyQuality(preset)
	local F = WG.FPSOps
	if startedByUs then F.SetVisible(false); startedByUs = false end
	if F.SetPreset(preset) == false then
		Spring.Echo("[VB] graphics: FPS-OPS is running its benchmark, choose the quality again when it is done")
	end
	want = nil
end

local function SetQuality(i)
	local q = QUALITIES[i]
	if not q then return end
	if WG.FPSOps then ApplyQuality(q.preset); return end
	if q.preset == 0 then want = nil; return end        -- nothing to turn down, FPS-OPS is not needed
	-- FPS-OPS is off: switch it on, the preset is applied as soon as it is there (Update)
	want, wantAge, startedByUs = q.preset, 0, true
	Spring.SendCommands("luaui enablewidget FPS-OPS")
end

--------------------------------------------------------------------------------
-- resolution
--------------------------------------------------------------------------------
local CANDIDATES = { { 1280, 720 }, { 1366, 768 }, { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 }, { 3440, 1440 }, { 3840, 2160 } }

local vsx, vsy = Spring.GetViewGeometry()
local resolutions = {}
local pending = nil               -- { w, h, age }: a resize that was asked for and not seen yet

-- the size of the screen the window is on (what the list is cut to).  In real fullscreen the engine may report the
-- CURRENT video mode instead of the monitor, which would cut every larger size out of the list: so the monitor size
-- is only believed when it is larger than the window, and otherwise the list is not cut at all (4K).
local function ScreenSize()
	if Spring.GetScreenGeometry then
		local ok, w, h = pcall(Spring.GetScreenGeometry)
		if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 and (w > vsx or h > vsy) then return w, h end
	end
	return max(vsx, 3840), max(vsy, 2160)
end

-- write the size to every config key that holds one, so that nothing of an earlier size stays in there
local function StoreSize(w, h)
	for _, kv in ipairs({ { "XResolution", w }, { "YResolution", h }, { "XResolutionWindowed", w }, { "YResolutionWindowed", h } }) do
		pcall(Spring.SetConfigInt, kv[1], kv[2])
	end
end

local function Rebuild()
	local sw, sh = ScreenSize()
	local seen, list = {}, {}
	local function Add(w, h)
		w, h = floor(w), floor(h)
		local key = w .. "x" .. h
		if seen[key] then return end
		seen[key] = true
		list[#list + 1] = { w = w, h = h, label = w .. " x " .. h }
	end
	for _, r in ipairs(CANDIDATES) do
		if r[1] <= sw and r[2] <= sh then Add(r[1], r[2]) end
	end
	Add(sw, sh)                                           -- the screen itself
	Add(vsx, vsy)                                         -- and wherever the window is now
	table.sort(list, function(a, b)
		local aa, bb = a.w * a.h, b.w * b.h
		if aa ~= bb then return aa < bb end
		return a.w < b.w
	end)
	resolutions = list
end

local function ResolutionIndex()
	for i, r in ipairs(resolutions) do
		if r.w == vsx and r.h == vsy then return i end
	end
end

local function SetResolution(i)
	local r = resolutions[i]
	if not r then return end
	local fullscreen = Spring.GetConfigInt("Fullscreen", 0) == 1
	local borderless = Spring.GetConfigInt("WindowBorderless", 0) == 1

	-- the next start uses this size, whatever the running engine does with the request
	StoreSize(r.w, r.h)
	if not fullscreen then
		local sw, sh = ScreenSize()
		pcall(Spring.SetConfigInt, "WindowPosX", max(0, floor((sw - r.w) / 2)))   -- a stale position can leave the window off screen
		pcall(Spring.SetConfigInt, "WindowPosY", max(0, floor((sh - r.h) / 2)))
	end

	-- the panels come back together, also when the player had arranged them by hand for the old size
	if WG.VBLayout and WG.VBLayout.Dock then WG.VBLayout.Dock() end

	if r.w == vsx and r.h == vsy then return end          -- nothing to resize
	local applied = false
	if Spring.SetWindowGeometry then
		local sw, sh = ScreenSize()
		local px, py = 0, 0
		if not fullscreen then px, py = max(0, floor((sw - r.w) / 2)), max(0, floor((sh - r.h) / 2)) end
		applied = pcall(Spring.SetWindowGeometry, 0, px, py, r.w, r.h, fullscreen, borderless)
	end
	pending = { w = r.w, h = r.h, age = 0, requested = applied }
	if not applied then
		pending = nil
		Spring.Echo("[VB] graphics: this engine cannot resize the window while running; " .. r.w .. " x " .. r.h .. " is saved for the next start")
	end
end

-- bring every widget up to date with the real window size
local REFRESH_WAIT = 1.0          -- seconds after the load / the game start
local refreshIn = REFRESH_WAIT
local function Refresh()
	vsx, vsy = Spring.GetViewGeometry()
	Rebuild()
	StoreSize(vsx, vsy)
	if WG.VBLayout and WG.VBLayout.Dock then WG.VBLayout.Dock() end
	if widgetHandler and widgetHandler.ViewResize then                 -- each widget's ViewResize(w, h) is called once
		pcall(widgetHandler.ViewResize, widgetHandler, { viewSizeX = vsx, viewSizeY = vsy })
	end
end

function widget:GameStart() refreshIn = REFRESH_WAIT end

function widget:ViewResize(w, h)
	local changed = (w ~= vsx or h ~= vsy)
	vsx, vsy = w, h
	Rebuild()
	if pending and pending.w == w and pending.h == h then pending = nil end
	if changed then
		StoreSize(w, h)                                    -- the size the window really has is the one that is kept
		if WG.VBLayout and WG.VBLayout.Dock then WG.VBLayout.Dock() end   -- and the HUD is stacked again at THIS size
	end
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------
function widget:Update(dt)
	if refreshIn then
		refreshIn = refreshIn - dt
		if refreshIn <= 0 then refreshIn = nil; Refresh() end
	end
	if want then
		wantAge = wantAge + dt
		if WG.FPSOps then
			ApplyQuality(want)
		elseif wantAge > START_WAIT then
			want, startedByUs = nil, false
			Spring.Echo("[VB] graphics: FPS-OPS did not start (is the widget gui_fps_ops.lua in LuaUI/Widgets?)")
		end
	end
	if pending then
		pending.age = pending.age + dt
		if pending.age > 2 then
			Spring.Echo("[VB] graphics: the engine did not resize the window to " .. pending.w .. " x " .. pending.h .. "; it is saved for the next start")
			pending = nil
		end
	end
end

local function Find(list, word)
	word = word:lower()
	for i, q in ipairs(list) do if q.id == word then return i end end
end

function widget:TextCommand(cmd)
	local word, rest = cmd:match("^(%S+)%s*(.*)$")
	if word ~= "vbgraphics" then return false end
	local arg, val = rest:match("^(%S*)%s*(.*)$")
	if arg == "quality" and Find(QUALITIES, val) then
		SetQuality(Find(QUALITIES, val))
	elseif arg == "res" or arg == "resolution" then
		local w, h = val:match("^(%d+)%s*[xX]%s*(%d+)$")
		local idx
		for i, r in ipairs(resolutions) do if tostring(r.w) == w and tostring(r.h) == h then idx = i end end
		if idx then SetResolution(idx) else Spring.Echo("[VB] graphics: /vbgraphics res <width>x<height> (one of the list in the dashboard settings)") end
	else
		local q, r = QualityIndex(), ResolutionIndex()
		Spring.Echo(string.format("[VB] graphics: quality %s, resolution %s.  /vbgraphics quality lowest|low|medium|high|ultra   /vbgraphics res 1600x900",
			q and QUALITIES[q].label or "CUSTOM (FPS-OPS)", r and resolutions[r].label or (vsx .. " x " .. vsy)))
	end
	return true
end

function widget:Initialize()
	vsx, vsy = Spring.GetViewGeometry()
	Rebuild()
	StoreSize(vsx, vsy)                                    -- start from what the window is, not from what an old config says
	WG.VBGraphics = {
		Qualities     = function() return QUALITIES end,
		Quality       = QualityIndex,                     -- index into Qualities, nil = mixed by hand in FPS-OPS
		SetQuality    = SetQuality,
		Resolutions   = function() return resolutions end, -- { w, h, label } sorted by size
		Resolution    = ResolutionIndex,                  -- index into Resolutions of the current window size
			SetResolution = SetResolution,
	}
end

function widget:Shutdown() WG.VBGraphics = nil end
