--[[
  Voidborn statistics: the drawing toolkit of the dashboard (panels, line charts, radar charts, donuts, bars).

    local D = VFS.Include("LuaUI/Headers/vb_stats_draw.h.lua")      -- needs the data module next to it:
    D.Stats = Stats

  Immediate mode: the widget calls D.BeginFrame() once per frame, draws, then D.EndFrame() (which draws the
  tooltip on top). Everything that can be clicked registers a region (D.Region); the widget forwards the mouse
  to D.Click / D.Drag / D.Wheel. All sizes are in pixels and multiplied by D.S (the user interface scale).
]]

local D = {}
local floor, ceil, max, min, abs, sqrt, cos, sin, pi, log10 = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt, math.cos, math.sin, math.pi, math.log10
local glColor, glRect, glVertex, glBeginEnd, glLineWidth = gl.Color, gl.Rect, gl.Vertex, gl.BeginEnd, gl.LineWidth
local GL_LINES, GL_LINE_STRIP, GL_LINE_LOOP, GL_TRIANGLES, GL_TRIANGLE_FAN, GL_TRIANGLE_STRIP = GL.LINES, GL.LINE_STRIP, GL.LINE_LOOP, GL.TRIANGLES, GL.TRIANGLE_FAN, GL.TRIANGLE_STRIP

D.S = 1
D.vsx, D.vsy = 1280, 720
D.mx, D.my = -1, -1
D.time = 0
D.regions, D.tip, D.modal = {}, nil, false
D.Stats = nil

D.C = {
	bg     = { 0.015, 0.020, 0.040 },
	panel  = { 0.040, 0.055, 0.090 },
	panel2 = { 0.060, 0.080, 0.125 },
	line   = { 0.14, 0.20, 0.31 },
	grid   = { 0.55, 0.66, 0.85 },
	text   = { 0.88, 0.93, 1.00 },
	dim    = { 0.52, 0.60, 0.73 },
	faint  = { 0.30, 0.37, 0.49 },
	accent = { 0.30, 0.80, 1.00 },
	good   = { 0.40, 1.00, 0.60 },
	bad    = { 1.00, 0.42, 0.42 },
	warn   = { 1.00, 0.80, 0.30 },
}
local C = D.C

local function sc(v) return v * D.S end
D.sc = sc

--------------------------------------------------------------------------------
-- text: the game's glyph font for labels, its mono font for numbers
--------------------------------------------------------------------------------
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) glColor(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
local mono, monoTried = nil, false
local function Mono()
	if monoTried then return mono end
	monoTried = true
	if gl.LoadFont then
		local ok, f = pcall(gl.LoadFont, "fonts/VoidbornMono.ttf", 32, 3, 1.5)
		if ok and f then mono = f end
	end
	return mono
end

function D.Text(str, x, y, size, opts, c, a)
	c = c or C.text
	VBFont.Text(str, x, y, size, opts or "o", c[1], c[2], c[3], a or 1)
end
function D.W(str, size) return VBFont.Width(str, size) end

function D.Mono(str, x, y, size, opts, c, a)
	c = c or C.text
	local f = Mono()
	if f then
		f:Begin(); f:SetTextColor(c[1], c[2], c[3], a or 1); f:SetOutlineColor(0, 0, 0, (a or 1) * 0.8)
		f:Print(str, x, y, size, opts or "o"); f:End()
	else
		D.Text(str, x, y, size, opts, c, a)
	end
end
function D.MW(str, size)
	local f = Mono()
	if f and f.GetTextWidth then return f:GetTextWidth(str) * size end
	return D.W(str, size)
end

-- cut a text so that it fits `w` pixels
function D.Fit(str, size, w)
	if D.W(str, size) <= w then return str end
	while #str > 1 and D.W(str .. "..", size) > w do str = str:sub(1, -2) end
	return str .. ".."
end

--------------------------------------------------------------------------------
-- primitives
--------------------------------------------------------------------------------
function D.Rect(x1, y1, x2, y2, c, a) glColor(c[1], c[2], c[3], a or 1); glRect(x1, y1, x2, y2) end
function D.Frame(x1, y1, x2, y2, c, a, t)
	t = t or 1
	glColor(c[1], c[2], c[3], a or 1)
	glRect(x1, y1, x2, y1 + t); glRect(x1, y2 - t, x2, y2); glRect(x1, y1, x1 + t, y2); glRect(x2 - t, y1, x2, y2)
end
function D.Line(x1, y1, x2, y2, c, a, w)
	glColor(c[1], c[2], c[3], a or 1)
	glLineWidth(w or 1)
	glBeginEnd(GL_LINES, function() glVertex(x1, y1); glVertex(x2, y2) end)
	glLineWidth(1)
end
function D.HLine(x1, x2, y, c, a) glColor(c[1], c[2], c[3], a or 1); glRect(x1, y, x2, y + 1) end
function D.VLine(x, y1, y2, c, a) glColor(c[1], c[2], c[3], a or 1); glRect(x, y1, x + 1, y2) end
function D.Dashed(x1, y1, x2, y2, c, a, dash)
	dash = dash or sc(4)
	glColor(c[1], c[2], c[3], a or 1)
	glBeginEnd(GL_LINES, function()
		if x1 == x2 then
			local y = y1
			while y < y2 do glVertex(x1, y); glVertex(x1, min(y + dash, y2)); y = y + dash * 2 end
		else
			local x = x1
			while x < x2 do glVertex(x, y1); glVertex(min(x + dash, x2), y1); x = x + dash * 2 end
		end
	end)
end

local function EmitPts(pts) for i = 1, #pts, 2 do glVertex(pts[i], pts[i + 1]) end end
function D.Poly(pts, mode, c, a, w)
	glColor(c[1], c[2], c[3], a or 1)
	if w then glLineWidth(w) end
	glBeginEnd(mode, EmitPts, pts)
	if w then glLineWidth(1) end
end

-- an arc band between radius r1 and r2, from angle a0 to a1 (radians, counter-clockwise from the x axis)
local function EmitArc(cx, cy, r1, r2, a0, a1, steps)
	for k = 0, steps do
		local a = a0 + (a1 - a0) * k / steps
		local co, si = cos(a), sin(a)
		glVertex(cx + co * r2, cy + si * r2); glVertex(cx + co * r1, cy + si * r1)
	end
end
function D.Arc(cx, cy, r1, r2, a0, a1, c, a)
	local steps = max(2, ceil(abs(a1 - a0) / (2 * pi) * 72))
	glColor(c[1], c[2], c[3], a or 1)
	glBeginEnd(GL_TRIANGLE_STRIP, EmitArc, cx, cy, r1, r2, a0, a1, steps)
end

local function EmitCircle(cx, cy, r, n) for k = 0, n - 1 do local a = 2 * pi * k / n; glVertex(cx + cos(a) * r, cy + sin(a) * r) end end
function D.Circle(cx, cy, r, c, a, w, n)
	glColor(c[1], c[2], c[3], a or 1)
	glLineWidth(w or 1)
	glBeginEnd(GL_LINE_LOOP, EmitCircle, cx, cy, r, n or 48)
	glLineWidth(1)
end
local function EmitDisc(cx, cy, r, n)
	glVertex(cx, cy)
	for k = 0, n do local a = 2 * pi * k / n; glVertex(cx + cos(a) * r, cy + sin(a) * r) end
end
function D.Disc(cx, cy, r, c, a, n)
	glColor(c[1], c[2], c[3], a or 1)
	glBeginEnd(GL_TRIANGLE_FAN, EmitDisc, cx, cy, r, n or 20)
end

--------------------------------------------------------------------------------
-- regions (what the mouse can hit) and the frame cycle
--------------------------------------------------------------------------------
function D.BeginFrame(mx, my, vsx, vsy, dt)
	D.regions, D.tip = {}, nil
	D.mx, D.my, D.vsx, D.vsy = mx, my, vsx, vsy
	D.time = D.time + (dt or 0)
	D.over = nil
end

-- spec: { click = fn(x, y, button), drag = fn(x, y), wheel = fn(up, x, y), tip = "text" }
function D.Region(x1, y1, x2, y2, spec)
	spec[1], spec[2], spec[3], spec[4] = x1, y1, x2, y2
	D.regions[#D.regions + 1] = spec
	return spec
end
function D.Inside(x1, y1, x2, y2) return D.mx >= x1 and D.mx <= x2 and D.my >= y1 and D.my <= y2 end
function D.Hit(x, y)
	for i = #D.regions, 1, -1 do
		local r = D.regions[i]
		if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then return r end
	end
end

-- a tooltip is drawn last, on top of everything: lines = { { left, color, right }, ... }
function D.Tooltip(lines) D.tip = lines end
function D.EndFrame()
	local tip = D.tip
	if not tip or #tip == 0 then return end
	local size = sc(10)
	local lh = size + sc(4)
	local w = 0
	for _, l in ipairs(tip) do
		local lw = D.W(l[1], size) + (l[3] and (D.MW(l[3], size) + sc(14)) or 0)
		if lw > w then w = lw end
	end
	w = w + sc(16)
	local h = #tip * lh + sc(8)
	local x = D.mx + sc(16)
	local y = D.my - sc(8) - h
	if x + w > D.vsx - 4 then x = D.mx - sc(16) - w end
	if y < 4 then y = D.my + sc(16) end
	if y + h > D.vsy - 4 then y = D.vsy - 4 - h end
	D.Rect(x, y, x + w, y + h, { 0.02, 0.03, 0.06 }, 0.96)
	D.Frame(x, y, x + w, y + h, C.accent, 0.7)
	for i, l in ipairs(tip) do
		local ty = y + h - sc(4) - i * lh + sc(3)
		D.Text(l[1], x + sc(8), ty, size, "o", l[2] or C.text)
		if l[3] then D.Mono(l[3], x + w - sc(8), ty, size, "or", l[2] or C.text) end
	end
end

--------------------------------------------------------------------------------
-- panels and buttons
--------------------------------------------------------------------------------
local function Brackets(x1, y1, x2, y2, c, a)
	local L = sc(9)
	glColor(c[1], c[2], c[3], a)
	glRect(x1, y1, x1 + L, y1 + 1); glRect(x1, y1, x1 + 1, y1 + L)
	glRect(x2 - L, y1, x2, y1 + 1); glRect(x2 - 1, y1, x2, y1 + L)
	glRect(x1, y2 - 1, x1 + L, y2); glRect(x1, y2 - L, x1 + 1, y2)
	glRect(x2 - L, y2 - 1, x2, y2); glRect(x2 - 1, y2 - L, x2, y2)
end

-- a framed panel with a title; returns the inner rectangle below the title strip
function D.Panel(x1, y1, x2, y2, title, opts)
	opts = opts or {}
	D.Rect(x1, y1, x2, y2, opts.color or C.panel, opts.alpha or 0.94)
	D.Frame(x1, y1, x2, y2, C.line, 1)
	Brackets(x1, y1, x2, y2, opts.accent or C.accent, 0.55)
	local top = y2
	if title then
		local th = sc(20)
		D.Rect(x1 + 1, y2 - th, x2 - 1, y2 - 1, C.panel2, 0.9)
		D.Rect(x1 + 1, y2 - th, x1 + sc(4), y2 - 1, opts.accent or C.accent, 0.9)
		D.Text(title, x1 + sc(10), y2 - th + sc(6), sc(10), "o", C.dim)
		if opts.right then D.Text(opts.right, x2 - sc(8), y2 - th + sc(6), sc(9), "or", C.faint) end
		top = y2 - th
	end
	return x1 + sc(6), y1 + sc(6), x2 - sc(6), top - sc(4)
end

function D.Button(x1, y1, x2, y2, label, spec)
	spec = spec or {}
	local hot = D.Inside(x1, y1, x2, y2)
	local accent = spec.color or C.accent
	if spec.active then
		D.Rect(x1, y1, x2, y2, accent, 0.28)
		D.Frame(x1, y1, x2, y2, accent, 0.95)
	else
		D.Rect(x1, y1, x2, y2, hot and C.panel2 or C.panel, 0.95)
		D.Frame(x1, y1, x2, y2, hot and accent or C.line, hot and 0.9 or 1)
	end
	local size = spec.size or sc(10)
	D.Text(label, (x1 + x2) / 2, (y1 + y2) / 2 - size * 0.35, size, "oc", spec.active and C.text or (hot and C.text or C.dim))
	return D.Region(x1, y1, x2, y2, { click = spec.click, tip = spec.tip })
end

--------------------------------------------------------------------------------
-- line charts
--------------------------------------------------------------------------------
local function NiceStep(maxv, ticks)
	if maxv <= 0 then return 1 end
	local raw = maxv / ticks
	local mag = 10 ^ floor(log10(raw))
	local n = raw / mag
	return (n <= 1 and 1 or n <= 2 and 2 or n <= 2.5 and 2.5 or n <= 5 and 5 or 10) * mag
end
D.NiceStep = NiceStep

local TIME_STEPS = { 0.5, 1, 2, 5, 10, 15, 30, 60, 120 }      -- minutes

-- the points of one team's line inside the window, thinned to about `maxPts`
local function Points(team, series, f0, f1, maxPts)
	local idx, n = {}, 0
	for i = 1, team.n do
		local f = team.f[i]
		if f >= f0 and f <= f1 then n = n + 1; idx[n] = i end
	end
	if n <= maxPts then return idx end
	local out, stride = {}, n / maxPts
	local k = 1
	while k <= n do out[#out + 1] = idx[floor(k)]; k = k + stride end
	if out[#out] ~= idx[n] then out[#out + 1] = idx[n] end
	return out
end

--[[ D.LineChart(x1, y1, x2, y2, spec)
  spec.teams    list of team records to draw             spec.metric   statistic id (see Stats.METRICS)
  spec.f0, f1   the frames shown                          spec.cursor   a frame to mark (or nil)
  spec.fill     tint the area under every line            spec.minimal  no axes, no labels (sparklines)
  spec.events   mark the events on the time axis          spec.title    drawn in the corner of the plot
  spec.onClick(frame, button)  spec.onDrag(frame)         spec.tip      tooltip for the whole chart when not over a line
  returns the plot rectangle (px1, py1, px2, py2) ]]
function D.LineChart(x1, y1, x2, y2, spec)
	local Stats = D.Stats
	local m = Stats.M[spec.metric]
	local minimal = spec.minimal
	local padL = minimal and sc(2) or sc(46)
	local padB = minimal and sc(2) or sc(16)
	local padT = spec.title and sc(16) or sc(6)
	local padR = minimal and sc(2) or sc(50)
	local px1, py1, px2, py2 = x1 + padL, y1 + padB, x2 - padR, y2 - padT
	local pw, ph = px2 - px1, py2 - py1
	if pw < 10 or ph < 10 then return px1, py1, px2, py2 end
	local f0, f1 = spec.f0, spec.f1
	if f1 <= f0 then f1 = f0 + 900 end

	-- the data inside the window and the vertical scale
	local lines, vmax, vmin = {}, 0, 0
	for _, team in ipairs(spec.teams) do
		local series = Stats.Series(team, spec.metric)
		local idx = Points(team, series, f0, f1, max(8, floor(pw / 2)))
		lines[#lines + 1] = { team = team, series = series, idx = idx }
		for _, i in ipairs(idx) do
			local v = series[i] or 0
			if v > vmax then vmax = v end
			if v < vmin then vmin = v end
		end
	end
	local step = NiceStep(max(vmax, -vmin, 1e-9), 4)
	local ymax = max(ceil(vmax / step - 1e-9) * step, step)
	local ymin = vmin < 0 and -ceil(-vmin / step - 1e-9) * step or 0
	local span = ymax - ymin
	local function X(f) return px1 + (f - f0) / (f1 - f0) * pw end
	local function Y(v) return py1 + (v - ymin) / span * ph end

	D.Rect(px1, py1, px2, py2, C.bg, 0.55)
	if not minimal then
		-- horizontal grid and value labels
		local v = ymin
		while v <= ymax + step * 0.01 do
			local y = Y(v)
			D.HLine(px1, px2, y, C.grid, v == 0 and 0.22 or 0.09)
			D.Mono(Stats.Format(m, v), px1 - sc(5), y - sc(4), sc(9), "or", C.dim)
			v = v + step
		end
		-- vertical grid and time labels
		local minutes = (f1 - f0) / 1800
		local tstep = TIME_STEPS[#TIME_STEPS]
		for _, s in ipairs(TIME_STEPS) do if minutes / s <= 7 then tstep = s; break end end
		local ts = ceil(f0 / (tstep * 1800)) * tstep * 1800
		while ts <= f1 do
			local x = X(ts)
			D.VLine(x, py1, py2, C.grid, 0.07)
			D.Mono(Stats.Time(ts), x, y1 + sc(2), sc(9), "oc", C.dim)
			ts = ts + tstep * 1800
		end
	else
		D.HLine(px1, px2, py1, C.grid, 0.18)
	end

	-- the lines
	for _, L in ipairs(lines) do
		local c = Stats.ViewColor(L.team)
		local idx = L.idx
		local n = #idx
		if n >= 1 then
			if spec.fill and n >= 2 then
				local base = Y(max(ymin, 0))
				glColor(c[1], c[2], c[3], minimal and 0.16 or 0.10)
				glBeginEnd(GL_TRIANGLE_STRIP, function()
					for _, i in ipairs(idx) do
						local x, y = X(L.team.f[i]), Y(L.series[i] or 0)
						glVertex(x, base); glVertex(x, y)
					end
				end)
			end
			local pts = {}
			for _, i in ipairs(idx) do pts[#pts + 1] = X(L.team.f[i]); pts[#pts + 1] = Y(L.series[i] or 0) end
			if n == 1 then D.Disc(pts[1], pts[2], sc(2.5), c, 1)
			else D.Poly(pts, GL_LINE_STRIP, c, 0.95, minimal and sc(1.4) or sc(1.8)) end
			L.lastX, L.lastY, L.lastV = pts[#pts - 1], pts[#pts], L.series[idx[n]] or 0
		end
	end

	-- the value at the end of every line, pushed apart so they do not overlap
	if not minimal then
		local labels = {}
		for _, L in ipairs(lines) do if L.lastY then labels[#labels + 1] = { y = L.lastY, L = L } end end
		table.sort(labels, function(a, b) return a.y < b.y end)
		local gap = sc(11)
		for k = 2, #labels do if labels[k].y - labels[k - 1].y < gap then labels[k].y = labels[k - 1].y + gap end end
		for _, lb in ipairs(labels) do
			local c = Stats.ViewColor(lb.L.team)
			D.Mono(Stats.Format(m, lb.L.lastV), px2 + sc(5), lb.y - sc(4), sc(9), "o", c)
		end
	end

	-- events on the time axis
	local markers = {}
	if spec.events and not minimal then
		for _, e in ipairs(Stats.events) do
			local team = Stats.teams[e[2]]
			local visible = false
			for _, t in ipairs(spec.teams) do if t == team then visible = true end end
			if visible and e[1] >= f0 and e[1] <= f1 then
				local x = X(e[1])
				local c = Stats.ViewColor(team)
				D.Poly({ x - sc(3.5), py1, x + sc(3.5), py1, x, py1 + sc(7) }, GL_TRIANGLES, c, 0.95)
				markers[#markers + 1] = { x = x, e = e }
			end
		end
	end

	-- the selected time
	if spec.cursor and spec.cursor >= f0 and spec.cursor <= f1 then
		local x = X(spec.cursor)
		D.Rect(x - 0.5, py1, x + 1.5, py2, C.warn, 0.55)
	end

	-- title
	if spec.title then
		D.Text(spec.title, px1 + sc(2), py2 + sc(3), sc(10), "o", m and m.color or C.text)
	end

	-- hover: guide, dots and a tooltip with every team's value
	local over = D.Inside(px1, py1, px2, py2) and not D.modalBlocked
	if over then
		local f = f0 + (D.mx - px1) / pw * (f1 - f0)
		local near, nearDist
		for _, mk in ipairs(markers) do
			local d = abs(mk.x - D.mx)
			if d < sc(6) and D.my < py1 + sc(14) and (not nearDist or d < nearDist) then near, nearDist = mk, d end
		end
		local tip = {}
		if near then
			tip[1] = { Stats.EventText(near.e), Stats.ViewColor(Stats.teams[near.e[2]] or lines[1].team), Stats.Time(near.e[1]) }
		else
			local shown
			local rows = {}
			for _, L in ipairs(lines) do
				local i = Stats.NearestIndex(L.team, f)
				if i and L.series[i] then
					shown = shown or L.team.f[i]
					local c = Stats.ViewColor(L.team)
					local x, y = X(L.team.f[i]), Y(L.series[i])
					D.Disc(x, y, sc(3.2), c, 1, 12)
					rows[#rows + 1] = { L.team.name, c, Stats.Format(m, L.series[i]), v = L.series[i] }
				end
			end
			table.sort(rows, function(a, b) return a.v > b.v end)
			if shown then
				D.Rect(D.mx - 0.5, py1, D.mx + 0.5, py2, C.text, 0.35)
				tip[1] = { (m and m.label or ""), C.dim, Stats.Time(shown) }
				for _, r in ipairs(rows) do tip[#tip + 1] = r end
			end
		end
		if #tip > 0 then D.Tooltip(tip) end
		if spec.onClick or spec.onDrag then
			D.Region(px1, py1, px2, py2, {
				click = spec.onClick and function(x, y, b) return spec.onClick(f0 + (x - px1) / pw * (f1 - f0), b) end or nil,
				drag  = spec.onDrag and function(x, y) return spec.onDrag(min(f1, max(f0, f0 + (x - px1) / pw * (f1 - f0)))) end or nil,
			})
		end
	elseif spec.onClick or spec.onDrag then
		D.Region(px1, py1, px2, py2, {
			click = spec.onClick and function(x, y, b) return spec.onClick(f0 + (x - px1) / pw * (f1 - f0), b) end or nil,
			drag  = spec.onDrag and function(x, y) return spec.onDrag(min(f1, max(f0, f0 + (x - px1) / pw * (f1 - f0)))) end or nil,
		})
	end
	return px1, py1, px2, py2
end

--------------------------------------------------------------------------------
-- radar chart
--------------------------------------------------------------------------------
--[[ D.Radar(cx, cy, R, axes, entries, spec)
  axes     { { label = "Army", fmt = function(v) -> text }, ... }
  entries  { { name = "...", color = {r,g,b}, vals = { raw value per axis } }, ... }
  Every spoke is scaled to the largest value on it, so the team that leads an axis touches the rim.
  spec.small   fewer labels (the HUD)   spec.title  heading drawn above ]]
function D.Radar(cx, cy, R, axes, entries, spec)
	spec = spec or {}
	local n = #axes
	if n < 3 then return end
	local Stats = D.Stats
	local ang = {}
	for k = 1, n do ang[k] = pi / 2 - 2 * pi * (k - 1) / n end

	-- the scale of every spoke
	local top = {}
	for k = 1, n do
		local mx = 0
		for _, e in ipairs(entries) do if (e.vals[k] or 0) > mx then mx = e.vals[k] end end
		top[k] = mx
	end

	-- the web: rings and spokes
	local rings = spec.small and 3 or 4
	D.Disc(cx, cy, R, C.bg, 0.55, 48)
	for r = 1, rings do
		local rr = R * r / rings
		D.Poly((function() local p = {}; for k = 1, n do p[#p + 1] = cx + cos(ang[k]) * rr; p[#p + 1] = cy + sin(ang[k]) * rr end; return p end)(),
			GL_LINE_LOOP, C.grid, r == rings and 0.30 or 0.12, 1)
	end
	for k = 1, n do D.Line(cx, cy, cx + cos(ang[k]) * R, cy + sin(ang[k]) * R, C.grid, 0.14, 1) end

	-- a faint sweep, like a radar
	local sw = (D.time * 0.7) % (2 * pi)
	for s = 0, 7 do
		local a = sw - s * 0.07
		glColor(C.accent[1], C.accent[2], C.accent[3], 0.10 * (1 - s / 8))
		glBeginEnd(GL_TRIANGLES, function()
			glVertex(cx, cy); glVertex(cx + cos(a) * R, cy + sin(a) * R); glVertex(cx + cos(a - 0.07) * R, cy + sin(a - 0.07) * R)
		end)
	end

	-- hover: the spoke nearest to the mouse
	local hotAxis
	local dx, dy = D.mx - cx, D.my - cy
	local dist = sqrt(dx * dx + dy * dy)
	if dist > R * 0.12 and dist < R * 1.35 and not D.modalBlocked then
		local a = math.atan2(dy, dx)
		local best, bd = nil, 1e9
		for k = 1, n do
			local d = abs(((a - ang[k] + pi) % (2 * pi)) - pi)
			if d < bd then best, bd = k, d end
		end
		if bd < pi / n then hotAxis = best end
	end
	if hotAxis then
		D.Line(cx, cy, cx + cos(ang[hotAxis]) * R, cy + sin(ang[hotAxis]) * R, C.accent, 0.8, sc(2))
	end

	-- the teams
	for _, e in ipairs(entries) do
		local c = e.color
		local pts = {}
		for k = 1, n do
			local f = top[k] > 0 and min(1, (e.vals[k] or 0) / top[k]) or 0
			pts[#pts + 1] = cx + cos(ang[k]) * R * f; pts[#pts + 1] = cy + sin(ang[k]) * R * f
		end
		glColor(c[1], c[2], c[3], 0.17)
		glBeginEnd(GL_TRIANGLE_FAN, function() glVertex(cx, cy); EmitPts(pts); glVertex(pts[1], pts[2]) end)
		D.Poly(pts, GL_LINE_LOOP, c, 0.95, sc(spec.small and 1.4 or 2))
		for k = 1, n do D.Disc(pts[k * 2 - 1], pts[k * 2], sc(spec.small and 1.8 or 2.8), c, 1, 10) end
	end

	-- the labels
	local size = sc(spec.small and 8 or 10)
	for k = 1, n do
		local co, si = cos(ang[k]), sin(ang[k])
		local lx, ly = cx + co * (R + sc(spec.small and 6 or 10)), cy + si * (R + sc(spec.small and 6 or 10))
		local opts = abs(co) < 0.25 and "oc" or (co > 0 and "o" or "or")
		local label = axes[k].label
		local hot = hotAxis == k
		local ty = ly - size * 0.35 + (si > 0.6 and size * 0.5 or (si < -0.6 and -size * 0.9 or 0))
		D.Text(label, lx, ty, size, opts, hot and C.text or C.dim)
		if not spec.small and top[k] > 0 then
			D.Mono(axes[k].fmt and axes[k].fmt(top[k]) or Stats.Num(top[k]), lx, ty - size - sc(1), sc(8), opts, C.faint)
		end
	end

	if hotAxis then
		local tip = { { axes[hotAxis].label, C.accent } }
		local rows = {}
		for _, e in ipairs(entries) do rows[#rows + 1] = { e.name, e.color, axes[hotAxis].fmt and axes[hotAxis].fmt(e.vals[hotAxis] or 0) or Stats.Num(e.vals[hotAxis] or 0), v = e.vals[hotAxis] or 0 } end
		table.sort(rows, function(a, b) return a.v > b.v end)
		for _, r in ipairs(rows) do tip[#tip + 1] = r end
		D.Tooltip(tip)
	end
end

--------------------------------------------------------------------------------
-- donut, bars
--------------------------------------------------------------------------------
-- slices: { { frac = 0..1, color = {r,g,b}, name = "", value = "text" }, ... }; hovering a slice shows it
function D.Donut(cx, cy, r1, r2, slices, centerText, centerSub)
	local total = 0
	for _, s in ipairs(slices) do total = total + s.frac end
	D.Circle(cx, cy, r2, C.line, 0.6, 1, 48); D.Circle(cx, cy, r1, C.line, 0.6, 1, 48)
	if total <= 0 then
		D.Text("no data", cx, cy - sc(4), sc(9), "oc", C.faint)
		return
	end
	local a = pi / 2
	local dx, dy = D.mx - cx, D.my - cy
	local dist = sqrt(dx * dx + dy * dy)
	local ma = (pi / 2 - math.atan2(dy, dx)) % (2 * pi)      -- clockwise from the top
	local acc, tip = 0, nil
	for _, s in ipairs(slices) do
		local sw = s.frac / total * 2 * pi
		if sw > 0.001 then
			local hot = dist >= r1 and dist <= r2 and ma >= acc and ma < acc + sw and not D.modalBlocked
			D.Arc(cx, cy, r1 + (hot and -sc(1) or 0), r2 + (hot and sc(3) or 0), a - 0.012, a - sw + 0.012, s.color, hot and 1 or 0.88)
			if hot then tip = { { s.name or "", s.color, s.value }, { string.format("%.1f%% of the total", s.frac / total * 100), C.dim } } end
			a = a - sw; acc = acc + sw
		end
	end
	if tip then D.Tooltip(tip) end
	if centerText then D.Mono(centerText, cx, cy - sc(1), sc(13), "oc", C.text) end
	if centerSub then D.Text(centerSub, cx, cy - sc(13), sc(8), "oc", C.dim) end
end

-- horizontal bars: items = { { label =, value =, color =, text = , tip = }, ... }, sorted by the caller
function D.HBars(x1, y1, x2, y2, items, spec)
	spec = spec or {}
	local n = #items
	if n == 0 then D.Text(spec.empty or "nothing yet", (x1 + x2) / 2, (y1 + y2) / 2, sc(10), "oc", C.faint); return end
	local rowH = min(sc(28), (y2 - y1) / n)
	local labelW = spec.labelW or sc(104)
	local valW = spec.valueW or sc(54)
	local vmax = 0
	for _, it in ipairs(items) do if it.value > vmax then vmax = it.value end end
	if vmax <= 0 then vmax = 1 end
	for k, it in ipairs(items) do
		local ry2 = y2 - (k - 1) * rowH
		local ry1 = ry2 - rowH
		if ry1 < y1 - 1 then break end
		local bx1, bx2 = x1 + labelW, x2 - valW
		local hot = D.Inside(x1, ry1, x2, ry2) and not D.modalBlocked
		if hot then D.Rect(x1, ry1, x2, ry2, C.panel2, 0.7) end
		D.Text(D.Fit(it.label, sc(9), labelW - sc(6)), x1 + sc(3), ry1 + rowH * 0.5 - sc(3), sc(9), "o", hot and C.text or C.dim)
		D.Rect(bx1, ry1 + rowH * 0.22, bx2, ry2 - rowH * 0.22, C.bg, 0.8)
		local w = (bx2 - bx1) * it.value / vmax
		if w > 0 then
			D.Rect(bx1, ry1 + rowH * 0.22, bx1 + w, ry2 - rowH * 0.22, it.color, 0.85)
			D.Rect(bx1, ry1 + rowH * 0.22, bx1 + w, ry1 + rowH * 0.22 + 1, C.text, 0.25)
		end
		D.Mono(it.text or tostring(it.value), x2 - sc(3), ry1 + rowH * 0.5 - sc(4), sc(9), "or", C.text)
		if hot and it.tip then D.Tooltip(it.tip) end
	end
end

-- a proportional stacked bar: parts = { { value =, color =, name =, text = }, ... }
function D.StackBar(x1, y1, x2, y2, parts)
	local total = 0
	for _, p in ipairs(parts) do total = total + p.value end
	D.Rect(x1, y1, x2, y2, C.bg, 0.8)
	if total <= 0 then return end
	local x = x1
	local tip
	for _, p in ipairs(parts) do
		local w = (x2 - x1) * p.value / total
		if w > 0.5 then
			D.Rect(x, y1, x + w, y2, p.color, 0.9)
			if w > sc(3) then D.Rect(x + w - 1, y1, x + w, y2, C.bg, 0.8) end
			if D.Inside(x, y1, x + w, y2) and not D.modalBlocked then tip = { { p.name, p.color, p.text }, { string.format("%.1f%%", p.value / total * 100), C.dim } } end
			x = x + w
		end
	end
	if tip then D.Tooltip(tip) end
end

return D
