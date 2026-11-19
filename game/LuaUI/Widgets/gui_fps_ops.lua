--------------------------------------------------------------------------------
-- FPS-OPS  -  floating FPS optimiser + gain estimator for Beyond All Reason
-- author: goddot
--
-- Install: put this file in  <BAR data folder>/LuaUI/Widgets/gui_fps_ops.lua
--          then enable "FPS-OPS" in the widget list (F11).
--
-- Chat commands:  /fpsops            show / hide the panel
--                 /fpsops reset      move panel back + all knobs to default
--                 /fpsops bench      start the A/B benchmark
--                 /fpsops deep       start the deep (per-knob) benchmark
--
-- All engine settings are written as *transient* (overlay) config values and the
-- original values are restored when the widget is unloaded, so nothing is left
-- permanently changed in springsettings.cfg.
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name    = "FPS-OPS",
		desc    = "Draggable FPS optimiser: units->icons, fewer features/particles/shadows/etc, with A/B benchmark that measures the fps gain",
		author  = "goddot",
		date    = "2026-11-18",
		license = "GNU GPL, v2 or later",
		layer   = 1000,
		enabled = true,
		handler = true, -- needed for widgetHandler (toggling heavy FX widgets)
	}
end

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
local WIDGET_NAME        = "FPS-OPS"
local BENCH_SEC          = 4.0   -- measuring time per benchmark segment
local WARM_SEC           = 1.5   -- discarded time after every settings switch (shader reloads / hitches)
local MIN_FRAMES         = 40    -- a segment is extended until it has this many frames (max 3x BENCH_SEC)
local HITCH_DT           = 0.5   -- frames longer than this are treated as switch-hitches and ignored
local BENCH_DISABLE_VSYNC = true -- VSync hides fps gains, so it is switched off during the benchmark

-- Widgets that the "FX widgets" knob may disable (case-insensitive substring match on widget name).
-- Each level is cumulative on top of the previous one. Edit to taste.
local FX_WIDGET_LEVELS = {
	{ "light effects", "distortion", "deferred lights" },
	{ "bloom" },
	{ "grass", "cloud" },
	{ "lups" },
}

--------------------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------------------
local spGetConfigInt     = Spring.GetConfigInt
local spSetConfigInt     = Spring.SetConfigInt
local spSendCommands     = Spring.SendCommands
local spGetViewGeometry  = Spring.GetViewGeometry
local spGetMouseState    = Spring.GetMouseState
local spIsGUIHidden      = Spring.IsGUIHidden
local spEcho             = Spring.Echo

local glColor = gl.Color
local glRect  = gl.Rect
local glText  = gl.Text

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format = string.format

local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

local function setCfgInt(name, v)
	-- 3rd arg = useOverlay: value is NOT persisted into springsettings.cfg
	pcall(spSetConfigInt, name, floor(v + 0.5), true)
end

local function cmd(str)
	pcall(spSendCommands, str)
end

--------------------------------------------------------------------------------
-- Heavy FX widget toggling
--------------------------------------------------------------------------------
local disabledByUs = {}

local function setHeavyWidgets(patterns)
	if not (widgetHandler and widgetHandler.knownWidgets) then return end
	local want = {}
	if patterns then
		for name in pairs(widgetHandler.knownWidgets) do
			if name ~= WIDGET_NAME then
				local lname = name:lower()
				for _, p in ipairs(patterns) do
					if lname:find(p, 1, true) then
						want[name] = true
						break
					end
				end
			end
		end
	end
	for name in pairs(want) do
		local info = widgetHandler.knownWidgets[name]
		if info and info.active and not disabledByUs[name] then
			pcall(widgetHandler.DisableWidget, widgetHandler, name)
			disabledByUs[name] = true
		end
	end
	for name in pairs(disabledByUs) do
		if not want[name] then
			pcall(widgetHandler.EnableWidget, widgetHandler, name)
			disabledByUs[name] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Knob definitions
--   read()           -> returns the ORIGINAL value (captured once in Initialize)
--   write(v, orig)   -> applies value v (v == orig for level 0 = "default")
--   levels[i].v      -> value for level i, label shown in the UI
--------------------------------------------------------------------------------
local knobs = {}
local function addKnob(def) def.level = 0; knobs[#knobs + 1] = def end

-- 1) Units -> icons at closer distance. Engine "UnitIconDist": LOWER = icons appear closer to the camera.
addKnob{
	id = "icons", name = "Units -> icons",
	tip = "Units turn into icons at a closer camera distance (lower number = closer). Big win in large fights.",
	read  = function() return spGetConfigInt("UnitIconDist", 200) end,
	write = function(v, orig) v = min(v, orig); setCfgInt("UnitIconDist", v); cmd("disticon " .. floor(v)) end,
	levels = {
		{ label = "dist 160", v = 160 }, { label = "dist 120", v = 120 }, { label = "dist 90", v = 90 },
		{ label = "dist 60", v = 60 },   { label = "dist 40", v = 40 },
	},
}

-- 2) Features (wrecks, rocks, trees) draw distance
addKnob{
	id = "features", name = "Feature draw dist",
	tip = "Wrecks, rocks and trees are only drawn closer to the camera.",
	read  = function()
		return { draw = spGetConfigInt("FeatureDrawDistance", 6000), fade = spGetConfigInt("FeatureFadeDistance", 4500) }
	end,
	write = function(v, orig)
		local d = min(v.draw, orig.draw)
		local f = min(v.fade, orig.fade, d - 1)
		setCfgInt("FeatureDrawDistance", d)
		setCfgInt("FeatureFadeDistance", max(0, f))
	end,
	levels = {
		{ label = "4000", v = { draw = 4000, fade = 3000 } }, { label = "2500", v = { draw = 2500, fade = 1800 } },
		{ label = "1200", v = { draw = 1200, fade = 800 } },  { label = "500",  v = { draw = 500,  fade = 300 } },
	},
}

-- 3) Max particles
addKnob{
	id = "particles", name = "Max particles",
	tip = "Caps smoke, explosions and other projectile particles.",
	read  = function() return spGetConfigInt("MaxParticles", 10000) end,
	write = function(v, orig) v = min(v, orig); setCfgInt("MaxParticles", v); cmd("maxparticles " .. floor(v)) end,
	levels = { { label = "8000", v = 8000 }, { label = "5000", v = 5000 }, { label = "2500", v = 2500 }, { label = "1000", v = 1000 } },
}

-- 4) Nano (construction beam) particles
addKnob{
	id = "nano", name = "Nano particles",
	tip = "Caps the build/repair beam particles.",
	read  = function() return spGetConfigInt("MaxNanoParticles", 2000) end,
	write = function(v, orig) v = min(v, orig); setCfgInt("MaxNanoParticles", v); cmd("maxnanoparticles " .. floor(v)) end,
	levels = { { label = "1000", v = 1000 }, { label = "500", v = 500 }, { label = "150", v = 150 }, { label = "off", v = 0 } },
}

-- 5) Unit model LOD distance
addKnob{
	id = "lod", name = "Unit LOD dist",
	tip = "Distance at which units switch to cheaper rendering. Effect depends on engine version - the DEEP bench shows if it does anything.",
	read  = function() return spGetConfigInt("UnitLodDist", 200) end,
	write = function(v, orig) v = min(v, orig); setCfgInt("UnitLodDist", v); cmd("distdraw " .. floor(v)) end,
	levels = { { label = "dist 150", v = 150 }, { label = "dist 100", v = 100 }, { label = "dist 60", v = 60 } },
}

-- 6) Shadows
addKnob{
	id = "shadows", name = "Shadows",
	tip = "Lower shadow map resolution, or turn shadows off.",
	read  = function() return { mode = spGetConfigInt("Shadows", 1), size = spGetConfigInt("ShadowMapSize", 2048) } end,
	write = function(v, orig)
		if orig.mode == 0 then return end -- shadows already off, nothing to optimise
		local mode = v.mode
		local size = min(v.size or orig.size, orig.size)
		cmd(format("shadows %d %d", mode, size))
		setCfgInt("Shadows", mode)
		setCfgInt("ShadowMapSize", size)
	end,
	levels = { { label = "1024", v = { mode = 1, size = 1024 } }, { label = "512", v = { mode = 1, size = 512 } }, { label = "off", v = { mode = 0 } } },
}

-- 7) Water quality
addKnob{
	id = "water", name = "Water",
	tip = "Cheaper water rendering (0 = basic, 1 = reflective).",
	read  = function() return spGetConfigInt("ReflectiveWater", 1) end,
	write = function(v, orig) v = min(v, orig); cmd("water " .. floor(v)); setCfgInt("ReflectiveWater", v) end,
	levels = { { label = "reflective", v = 1 }, { label = "basic", v = 0 } },
}

-- 8) Ground decals
addKnob{
	id = "decals", name = "Ground decals",
	tip = "Scorch marks / tracks on the ground.",
	read  = function() return spGetConfigInt("GroundDecals", 1) end,
	write = function(v, orig) v = min(v, orig); setCfgInt("GroundDecals", v); cmd("grounddecals " .. floor(v)) end,
	levels = { { label = "off", v = 0 } },
}

-- 9) Heavy FX widgets (bloom, lights, distortion, grass, lups ...)
addKnob{
	id = "fxwidgets", name = "FX widgets",
	tip = "Disables heavy visual-effect widgets (see FX_WIDGET_LEVELS at the top of the file). They are re-enabled when set back to default or when this widget unloads.",
	read  = function() return false end,
	write = function(v)
		if not v then setHeavyWidgets(nil) return end
		local pats = {}
		for i = 1, v do
			for _, p in ipairs(FX_WIDGET_LEVELS[i] or {}) do pats[#pats + 1] = p end
		end
		setHeavyWidgets(pats)
	end,
	levels = { { label = "lights", v = 1 }, { label = "+bloom", v = 2 }, { label = "+grass/cloud", v = 3 }, { label = "+lups", v = 4 } },
}

local PRESETS = { { "OFF", 0 }, { "LOW", 1 }, { "MED", 2 }, { "HIGH", 3 }, { "MAX", 99 } }

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local vsx, vsy = 1920, 1080
local S = {
	px = nil, py = nil,         -- panel top-left (screen coords, y up)
	ui = 1, collapsed = false, visible = true,
	dragging = false, dirty = true,
	ema = 1 / 60, low1 = nil, msg = nil,
	inited = false,
}
local G = nil                   -- cached geometry
local applied = {}              -- level currently applied to the engine per knob
local bench = nil               -- running benchmark
local result = nil              -- last benchmark result

local ring, ringI, ringN = {}, 0, 0
local RING_MAX = 300
local low1Timer = 0

local function userLevels()
	local t = {}
	for i, k in ipairs(knobs) do t[i] = k.level end
	return t
end

local function zeroLevels()
	local t = {}
	for i = 1, #knobs do t[i] = 0 end
	return t
end

local function applyKnob(i, lvl)
	local k = knobs[i]
	local v
	if lvl == 0 then v = k.orig else v = k.levels[lvl].v end
	pcall(k.write, v, k.orig)
	applied[i] = lvl
end

local function applyLevels(arr)
	for i = 1, #knobs do
		if applied[i] ~= arr[i] then applyKnob(i, arr[i]) end
	end
end

local function setKnob(i, lvl)
	if bench then S.msg = "Locked while benchmark is running"; return end
	local k = knobs[i]
	lvl = clamp(lvl, 0, #k.levels)
	k.level = lvl
	applyKnob(i, lvl)
	S.msg = nil
end

local function applyPreset(p)
	if bench then S.msg = "Locked while benchmark is running"; return end
	for i, k in ipairs(knobs) do
		local n = #k.levels
		local lvl = (p == 0) and 0 or min(p, n)
		k.level = lvl
		applyKnob(i, lvl)
	end
	S.msg = nil
end

--------------------------------------------------------------------------------
-- Statistics / benchmark
--------------------------------------------------------------------------------
local function copyArr(t) local r = {} for i = 1, #t do r[i] = t[i] end return r end

local function calcStats(dts)
	local n = #dts
	if n == 0 then return nil end
	local T = 0
	for i = 1, n do T = T + dts[i] end
	local s = copyArr(dts)
	table.sort(s)
	local p99 = s[max(1, ceil(0.99 * n))]
	return { n = n, T = T, fps = n / T, ms = 1000 * T / n, low1 = 1 / p99 }
end

local function buildPlan(deep)
	local user = userLevels()
	local any = false
	for i = 1, #user do if user[i] > 0 then any = true end end
	if not any then return nil end
	local zero = zeroLevels()
	local plan = {}
	local function seg(key, levels, label) plan[#plan + 1] = { key = key, levels = levels, label = label } end
	-- symmetric order (A B ... B A) cancels linear drift (loading, camera, unit count changes)
	seg("A", zero, "baseline (all OFF)")
	seg("B", user, "optimised (your setup)")
	if deep then
		for i, k in ipairs(knobs) do
			if user[i] > 0 then
				local l = copyArr(user)
				l[i] = 0
				seg("L" .. i, l, "without: " .. k.name)
			end
		end
	end
	seg("B", user, "optimised (repeat)")
	seg("A", zero, "baseline (repeat)")
	return plan, user
end

local function startBench(deep)
	if bench then return end
	local plan, user = buildPlan(deep)
	if not plan then
		S.msg = "Turn on at least one knob first (or pick a preset)"
		return
	end
	bench = { plan = plan, user = user, deep = deep, i = 1, started = false, t = 0, warm = true, cur = {}, data = {}, hitches = 0 }
	if BENCH_DISABLE_VSYNC then
		local vs = spGetConfigInt("VSync", 0)
		if vs ~= 0 then bench.vsync = vs; cmd("vsync 0") end
	end
	S.msg = nil
	S.dirty = true
end

local function endBench()
	if not bench then return end
	applyLevels(bench.user)
	if bench.vsync then cmd("vsync " .. bench.vsync) end
	bench = nil
	S.dirty = true
end

local function finishBench()
	local b = bench
	local st = {}
	for key, d in pairs(b.data) do
		local s = calcStats(d.dts)
		if s then s.segfps = d.segfps; st[key] = s end
	end
	local A, B = st.A, st.B
	if A and B then
		local function spread(s)
			if #s.segfps < 2 then return 0 end
			local a, c = s.segfps[1], s.segfps[2]
			return abs(a - c) / ((a + c) / 2)
		end
		local noise = max(spread(A), spread(B))
		local gain = B.fps / A.fps - 1
		local conf
		if gain > 0.02 and gain >= 3 * noise then conf = "high"
		elseif gain > 0 and gain >= 1.5 * noise then conf = "medium"
		else conf = "low (within noise)" end

		local kg = {}
		if b.deep then
			for i = 1, #knobs do
				local L = st["L" .. i]
				if L then kg[i] = B.fps / L.fps - 1 end
			end
		end
		result = {
			fpsA = A.fps, fpsB = B.fps, gain = gain,
			lowA = A.low1, lowB = B.low1, gain1 = B.low1 / A.low1 - 1,
			msA = A.ms, msB = B.ms,
			noise = noise, conf = conf, levels = copyArr(b.user),
			deep = b.deep, knobGain = kg, hitches = b.hitches,
		}
		spEcho(format("[FPS-OPS] baseline %.0f fps -> optimised %.0f fps (%+.0f%%), 1%% low %.0f -> %.0f (%+.0f%%), noise +-%.1f%%, confidence: %s",
			A.fps, B.fps, gain * 100, A.low1, B.low1, result.gain1 * 100, noise * 100, conf))
		if b.deep then
			for i, k in ipairs(knobs) do
				if kg[i] then spEcho(format("[FPS-OPS]   %-18s %+.1f%%", k.name, kg[i] * 100)) end
			end
		end
	else
		S.msg = "Benchmark failed (no frames recorded)"
	end
	endBench()
end

local function cancelBench()
	if bench then
		endBench()
		S.msg = "Benchmark cancelled"
	end
end

local function benchUpdate(dt)
	local b = bench
	local seg = b.plan[b.i]
	if not b.started then
		applyLevels(seg.levels)
		b.started, b.t, b.warm, b.cur = true, 0, true, {}
		return
	end
	b.t = b.t + dt
	if b.warm then
		if b.t >= WARM_SEC then b.warm = false; b.t = 0 end
		return
	end
	if dt < HITCH_DT then b.cur[#b.cur + 1] = dt else b.hitches = b.hitches + 1 end
	local enoughTime = b.t >= BENCH_SEC
	local enoughFrames = #b.cur >= MIN_FRAMES or b.t >= BENCH_SEC * 3
	if enoughTime and enoughFrames then
		local d = b.data[seg.key]
		if not d then d = { dts = {}, segfps = {} }; b.data[seg.key] = d end
		local T = 0
		for i = 1, #b.cur do d.dts[#d.dts + 1] = b.cur[i]; T = T + b.cur[i] end
		if T > 0 then d.segfps[#d.segfps + 1] = #b.cur / T end
		b.i = b.i + 1
		b.started = false
		if b.i > #b.plan then finishBench() end
	end
end

-- Estimated gain for the CURRENT knob setup, from the last benchmark.
-- returns gain (0.25 = +25%), isModel (extrapolated from per-knob data), isPartial
local function currentGainEstimate()
	if not result then return nil end
	local same = true
	for i, k in ipairs(knobs) do
		if k.level ~= result.levels[i] then same = false break end
	end
	if same then return result.gain, false, false end
	if result.deep then
		local g, partial = 1, false
		for i, k in ipairs(knobs) do
			if k.level > 0 then
				if k.level == result.levels[i] and result.knobGain[i] then
					g = g * (1 + max(0, result.knobGain[i]))
				else
					partial = true
				end
			end
		end
		return g - 1, true, partial
	end
	return nil
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------
local W, HEADER_H, STAT_LINE, STAT_H, PRESET_H, ROW, BTN_H, STATUS_H = 350, 26, 16, 72, 30, 22, 32, 36

local function inRect(r, x, y) return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end

local function rebuild()
	local ui = S.ui
	local w = W * ui
	local ph
	if S.collapsed then
		ph = HEADER_H * ui
	else
		ph = (HEADER_H + STAT_H + PRESET_H + #knobs * ROW + BTN_H + STATUS_H + 4) * ui
	end
	if not S.px then S.px = vsx - w - 20 end
	if not S.py then S.py = vsy - 140 end
	S.px = clamp(S.px, 0, max(0, vsx - w))
	S.py = clamp(S.py, ph, vsy)

	local g = {}
	local x1, top = S.px, S.py
	g.w, g.h, g.x1, g.top = w, ph, x1, top
	g.panel = { x1, top - ph, x1 + w, top }
	g.header = { x1, top - HEADER_H * ui, x1 + w, top }
	g.btnCollapse = { x1 + w - 26 * ui, top - HEADER_H * ui + 4 * ui, x1 + w - 4 * ui, top - 4 * ui }
	g.btnClose    = { x1 + w - 52 * ui, top - HEADER_H * ui + 4 * ui, x1 + w - 30 * ui, top - 4 * ui }

	if not S.collapsed then
		local y = top - HEADER_H * ui
		g.statTop = y
		y = y - STAT_H * ui

		-- presets
		local pad = 8 * ui
		local gap = 4 * ui
		local bw = (w - 2 * pad - (#PRESETS - 1) * gap) / #PRESETS
		g.presets = {}
		for i = 1, #PRESETS do
			local bx = x1 + pad + (i - 1) * (bw + gap)
			g.presets[i] = { bx, y - PRESET_H * ui + 4 * ui, bx + bw, y - 3 * ui }
		end
		y = y - PRESET_H * ui

		-- knob rows
		g.rows = {}
		for i = 1, #knobs do
			local r = { all = { x1, y - ROW * ui, x1 + w, y }, yc = y - ROW * ui / 2 }
			r.minus = { x1 + 165 * ui, y - ROW * ui + 3 * ui, x1 + 183 * ui, y - 3 * ui }
			r.val   = { x1 + 185 * ui, y - ROW * ui + 3 * ui, x1 + 275 * ui, y - 3 * ui }
			r.plus  = { x1 + 277 * ui, y - ROW * ui + 3 * ui, x1 + 295 * ui, y - 3 * ui }
			g.rows[i] = r
			y = y - ROW * ui
		end

		-- bench buttons
		local bw3 = (w - 2 * pad - 2 * gap) / 3
		g.btnBench  = { x1 + pad,                     y - BTN_H * ui + 4 * ui, x1 + pad + bw3,                  y - 4 * ui }
		g.btnDeep   = { x1 + pad + bw3 + gap,         y - BTN_H * ui + 4 * ui, x1 + pad + 2 * bw3 + gap,        y - 4 * ui }
		g.btnCancel = { x1 + pad + 2 * (bw3 + gap),   y - BTN_H * ui + 4 * ui, x1 + w - pad,                    y - 4 * ui }
		y = y - BTN_H * ui

		g.statusTop = y
		g.status1 = { x1 + pad, y - 16 * ui, x1 + w - pad, y - 2 * ui }
	end
	G = g
	S.dirty = false
end

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------
local function col(c, a) glColor(c[1], c[2], c[3], a or c[4] or 1) end
local C_BG     = { 0.05, 0.06, 0.08, 0.90 }
local C_HEAD   = { 0.10, 0.32, 0.52, 0.95 }
local C_BTN    = { 0.17, 0.19, 0.24, 0.95 }
local C_BTN_H  = { 0.28, 0.34, 0.45, 1.00 }
local C_BTN_ON = { 0.15, 0.45, 0.25, 1.00 }
local C_ROW    = { 1, 1, 1, 0.04 }
local C_TXT    = { 0.92, 0.94, 0.97, 1 }
local C_DIM    = { 0.62, 0.66, 0.72, 1 }
local C_GOOD   = { 0.40, 1.00, 0.55, 1 }
local C_WARN   = { 1.00, 0.78, 0.30, 1 }
local C_BAD    = { 1.00, 0.45, 0.40, 1 }

local function rect(r, c) col(c); glRect(r[1], r[2], r[3], r[4]) end

local function border(r, c, t)
	col(c)
	glRect(r[1], r[4] - t, r[3], r[4])
	glRect(r[1], r[2], r[3], r[2] + t)
	glRect(r[1], r[2], r[1] + t, r[4])
	glRect(r[3] - t, r[2], r[3], r[4])
end

local function text(str, x, y, size, opts, c)
	col(c or C_TXT)
	glText(str, x, y, size * S.ui, opts or "vo")
end

local function button(r, label, hot, on, enabled)
	local c = C_BTN
	if on then c = C_BTN_ON end
	if hot and enabled ~= false then c = C_BTN_H end
	rect(r, c)
	border(r, { 1, 1, 1, 0.10 }, 1)
	text(label, (r[1] + r[3]) / 2, (r[2] + r[4]) / 2, 12, "cvo", enabled == false and C_DIM or C_TXT)
end

local function fmtGain(g) return format("%+.0f%%", g * 100) end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------
function widget:DrawScreen()
	if not S.visible or spIsGUIHidden() then return end
	if S.dirty or not G then rebuild() end

	local ui = S.ui
	local mx, my = spGetMouseState()

	rect(G.panel, C_BG)
	border(G.panel, { 1, 1, 1, 0.18 }, 1)
	rect(G.header, C_HEAD)
	text("FPS-OPS", G.x1 + 8 * ui, G.top - HEADER_H * ui / 2, 15, "vo")
	text("by goddot", G.x1 + 80 * ui, G.top - HEADER_H * ui / 2, 10, "vo", { 0.75, 0.85, 1, 0.8 })
	button(G.btnClose, "x", inRect(G.btnClose, mx, my), false, true)
	button(G.btnCollapse, S.collapsed and "+" or "-", inRect(G.btnCollapse, mx, my), false, true)

	if S.collapsed then
		-- compact fps readout in the header
		text(format("%d fps", floor(1 / S.ema + 0.5)), G.x1 + 150 * ui, G.top - HEADER_H * ui / 2, 12, "vo", C_GOOD)
		glColor(1, 1, 1, 1)
		return
	end

	-- ---- stats block --------------------------------------------------------
	local fps = 1 / S.ema
	local lx = G.x1 + 10 * ui
	local ly = G.statTop - STAT_LINE * ui * 0.8
	text(format("FPS %d    %.1f ms    1%% low %d", floor(fps + 0.5), S.ema * 1000, floor((S.low1 or fps) + 0.5)),
		lx, ly, 14, "vo", C_GOOD)
	ly = ly - STAT_LINE * ui

	if result then
		text(format("Measured: %.0f -> %.0f fps  (%s)    1%% low %s",
			result.fpsA, result.fpsB, fmtGain(result.gain), fmtGain(result.gain1)),
			lx, ly, 12, "vo", result.gain > 0 and C_GOOD or C_BAD)
		ly = ly - STAT_LINE * ui
		local cc = (result.conf == "high") and C_GOOD or ((result.conf == "medium") and C_WARN or C_BAD)
		text(format("Noise +-%.1f%%   confidence: %s%s", result.noise * 100, result.conf,
			result.deep and "   (per-knob data)" or ""), lx, ly, 11, "vo", cc)
		ly = ly - STAT_LINE * ui

		local g, isModel, partial = currentGainEstimate()
		if g then
			local base = fps / (1 + g)
			text(format("Without OPS now: ~%d fps  (OPS = %s)%s", floor(base + 0.5), fmtGain(g),
				partial and "  partial" or (isModel and "  model" or "")), lx, ly, 12, "vo", C_TXT)
		else
			text("Settings changed since bench - re-run (DEEP gives per-knob model)", lx, ly, 11, "vo", C_WARN)
		end
	else
		text("No benchmark yet.", lx, ly, 12, "vo", C_DIM)
		ly = ly - STAT_LINE * ui
		text("Pick a preset, then press BENCH to measure the fps gain.", lx, ly, 11, "vo", C_DIM)
		ly = ly - STAT_LINE * ui
		text("Tip: bench in a busy scene and keep the camera still.", lx, ly, 11, "vo", C_DIM)
	end

	-- ---- presets --------------------------------------------------------------
	for i, p in ipairs(PRESETS) do
		button(G.presets[i], p[1], inRect(G.presets[i], mx, my), false, not bench)
	end

	-- ---- knob rows ----------------------------------------------------------
	for i, k in ipairs(knobs) do
		local r = G.rows[i]
		if i % 2 == 0 then rect(r.all, C_ROW) end
		text(k.name, G.x1 + 10 * ui, r.yc, 12, "vo", k.level > 0 and C_TXT or C_DIM)
		button(r.minus, "<", inRect(r.minus, mx, my), false, not bench)
		button(r.plus, ">", inRect(r.plus, mx, my), false, not bench)
		rect(r.val, k.level > 0 and { 0.12, 0.30, 0.20, 0.95 } or { 0.10, 0.11, 0.14, 0.95 })
		border(r.val, { 1, 1, 1, 0.10 }, 1)
		text(k.level == 0 and "default" or k.levels[k.level].label,
			(r.val[1] + r.val[3]) / 2, r.yc, 11, "cvo", k.level > 0 and C_GOOD or C_DIM)
		if result and result.knobGain[i] and k.level == result.levels[i] and k.level > 0 then
			local kgv = result.knobGain[i]
			local noisy = kgv < max(0.005, result.noise)
			text(noisy and "~0" or fmtGain(kgv), G.x1 + G.w - 8 * ui, r.yc, 11, "rvo", noisy and C_DIM or C_GOOD)
		end
	end

	-- ---- bench buttons ------------------------------------------------------
	button(G.btnBench, "BENCH A/B", inRect(G.btnBench, mx, my), bench and not bench.deep, not bench)
	button(G.btnDeep, "DEEP BENCH", inRect(G.btnDeep, mx, my), bench and bench.deep, not bench)
	button(G.btnCancel, "CANCEL", inRect(G.btnCancel, mx, my), false, bench ~= nil)

	-- ---- status -------------------------------------------------------------
	local s1 = G.status1
	if bench then
		local seg = bench.plan[bench.i]
		local frac = bench.warm and 0 or min(bench.t / BENCH_SEC, 1)
		local overall = ((bench.i - 1) + frac) / #bench.plan
		local bar = { s1[1], s1[2], s1[1] + (s1[3] - s1[1]) * overall, s1[4] }
		rect(bar, { 0.15, 0.45, 0.25, 0.6 })
		border(s1, { 1, 1, 1, 0.12 }, 1)
		local left = (#bench.plan - bench.i + 1) * (WARM_SEC + BENCH_SEC)
		text(format("%s %d/%d  %s  (~%ds left)", bench.warm and "warming" or "measuring", bench.i, #bench.plan, seg.label, floor(left)),
			s1[1] + 4 * ui, (s1[2] + s1[4]) / 2, 10.5, "vo")
	elseif S.msg then
		text(S.msg, s1[1] + 2 * ui, (s1[2] + s1[4]) / 2, 11, "vo", C_WARN)
	end
	local warn
	if spGetConfigInt("VSync", 0) ~= 0 and not bench then
		warn = "VSync is ON: fps is capped (bench switches it off temporarily)"
	end
	if warn then text(warn, s1[1] + 2 * ui, s1[2] - 8 * ui, 10, "vo", C_DIM) end

	glColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- Update (frame timing + benchmark state machine)
--------------------------------------------------------------------------------
function widget:Update(dt)
	if not dt or dt <= 0 then return end

	-- live frame-time EMA (hitches are clamped so one stall does not wreck the readout)
	S.ema = S.ema * 0.96 + min(dt, 0.25) * 0.04

	ringI = ringI % RING_MAX + 1
	ring[ringI] = dt
	if ringN < RING_MAX then ringN = ringN + 1 end

	low1Timer = low1Timer + dt
	if low1Timer > 1.0 then
		low1Timer = 0
		local tmp = {}
		for i = 1, ringN do tmp[i] = ring[i] end
		table.sort(tmp)
		local p99 = tmp[max(1, ceil(0.99 * ringN))]
		if p99 and p99 > 0 then S.low1 = 1 / p99 end
	end

	if bench then benchUpdate(dt) end
end

--------------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------------
function widget:IsAbove(x, y)
	return S.visible and G ~= nil and inRect(G.panel, x, y)
end

function widget:GetTooltip(x, y)
	if not (S.visible and G and G.rows and not S.collapsed) then return nil end
	for i, r in ipairs(G.rows) do
		if inRect(r.all, x, y) then return knobs[i].tip end
	end
	if inRect(G.btnBench, x, y) then
		return "A/B benchmark: baseline (all default) vs your setup, ABBA order, ~" .. floor(4 * (WARM_SEC + BENCH_SEC)) .. "s. Keep the camera still in a busy scene."
	elseif inRect(G.btnDeep, x, y) then
		return "Also measures every active knob alone (leave-one-out) to show each knob's own fps contribution. Takes longer."
	end
	return nil
end

function widget:MousePress(x, y, button)
	if not S.visible or not G or spIsGUIHidden() then return false end
	if not inRect(G.panel, x, y) then return false end

	if inRect(G.btnClose, x, y) then
		S.visible = false
		return true
	elseif inRect(G.btnCollapse, x, y) then
		S.collapsed = not S.collapsed
		S.dirty = true
		return true
	elseif inRect(G.header, x, y) then
		S.dragging = true
		return true
	end
	if S.collapsed then return true end

	if bench then
		if inRect(G.btnCancel, x, y) then cancelBench() end
		return true
	end

	for i, p in ipairs(PRESETS) do
		if inRect(G.presets[i], x, y) then applyPreset(p[2]) return true end
	end
	for i, r in ipairs(G.rows) do
		if inRect(r.all, x, y) then
			local k = knobs[i]
			if button == 3 then
				setKnob(i, 0)
			elseif inRect(r.minus, x, y) then
				setKnob(i, k.level - 1)
			elseif inRect(r.plus, x, y) then
				setKnob(i, k.level + 1)
			else
				setKnob(i, (k.level + 1) % (#k.levels + 1))
			end
			return true
		end
	end
	if inRect(G.btnBench, x, y) then startBench(false)
	elseif inRect(G.btnDeep, x, y) then startBench(true) end
	return true
end

function widget:MouseMove(x, y, dx, dy)
	if S.dragging then
		S.px = S.px + dx
		S.py = S.py + dy
		S.dirty = true
	end
end

function widget:MouseRelease(x, y, button)
	S.dragging = false
	return true
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
function widget:TextCommand(command)
	local c = command:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if c == "fpsops" then
		S.visible = not S.visible
		return true
	elseif c == "fpsops reset" then
		cancelBench()
		applyPreset(0)
		S.px, S.py, S.collapsed, S.visible, result = nil, nil, false, true, nil
		S.dirty = true
		return true
	elseif c == "fpsops bench" then
		S.visible = true
		startBench(false)
		return true
	elseif c == "fpsops deep" then
		S.visible = true
		startBench(true)
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Lifecycle / persistence
--------------------------------------------------------------------------------
function widget:ViewResize(x, y)
	vsx, vsy = x, y
	S.ui = clamp(vsy / 1080, 0.85, 1.5)
	S.dirty = true
end

function widget:Initialize()
	vsx, vsy = spGetViewGeometry()
	S.ui = clamp(vsy / 1080, 0.85, 1.5)

	-- capture ORIGINAL engine values before we change anything
	for _, k in ipairs(knobs) do k.orig = k.read() end
	applied = {}

	local any = false
	for _, k in ipairs(knobs) do if k.level > 0 then any = true end end
	if any then applyLevels(userLevels()) end

	S.inited = true
	S.dirty = true
end

function widget:Shutdown()
	if bench then
		if bench.vsync then cmd("vsync " .. bench.vsync) end
		bench = nil
	end
	-- restore originals (knob.level is kept so GetConfigData can still save the user's setup)
	for i = 1, #knobs do
		if knobs[i].orig ~= nil then pcall(applyKnob, i, 0) end
	end
	pcall(setHeavyWidgets, nil)
end

function widget:GetConfigData()
	local lv = {}
	for _, k in ipairs(knobs) do lv[k.id] = k.level end
	return { px = S.px, py = S.py, collapsed = S.collapsed, visible = S.visible, levels = lv }
end

function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	S.px, S.py = d.px, d.py
	if d.collapsed ~= nil then S.collapsed = d.collapsed end
	if d.visible ~= nil then S.visible = d.visible end
	if type(d.levels) == "table" then
		for _, k in ipairs(knobs) do
			local l = d.levels[k.id]
			if type(l) == "number" then k.level = clamp(floor(l), 0, #k.levels) end
		end
		if S.inited then applyLevels(userLevels()) end
	end
	S.dirty = true
end
