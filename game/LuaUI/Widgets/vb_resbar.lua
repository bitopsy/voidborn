function widget:GetInfo()
	return { name = "Voidborn Resource Bar", desc = "Metal and energy panels at the top right: stock, storage, income / spend, a 60 s trend line and warnings",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true }
end

-- Replaces the engine's stock resource bar (switched off with "resbar 0" while this widget runs).
--   /vbresbar         switches this widget's panels off and on (the stock bar comes back when they are off)
--   /vbresbar scale 1.2   size of the panels (0.6 .. 2.0)
-- Each panel shows the stock as a big number, a storage bar that eases toward the real value, the income and
-- the spending per second, and a 60 second trend line of the net flow.  The bar pulses amber when the storage
-- is nearly full (you are wasting income) and red when the stock is empty and you spend more than you earn.
-- Hover a panel for the full numbers.

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local spGetTeamResources, spGetMyTeamID = Spring.GetTeamResources, Spring.GetMyTeamID
local glColor, glRect, glBeginEnd, glVertex, glLineWidth = gl.Color, gl.Rect, gl.BeginEnd, gl.Vertex, gl.LineWidth
local min, max, floor, sin, abs = math.min, math.max, math.floor, math.sin, math.abs

local HISTORY = 60                  -- seconds of trend line
local COLORS = {
	metal  = { name = "METAL",  main = { 0.55, 0.85, 1.00 }, dark = { 0.10, 0.22, 0.30 } },
	energy = { name = "ENERGY", main = { 1.00, 0.80, 0.30 }, dark = { 0.30, 0.22, 0.06 } },
}
local ORDER = { "metal", "energy" }
local UP, DOWN, WARN = { 0.45, 1.00, 0.55 }, { 1.00, 0.45, 0.40 }, { 1.00, 0.62, 0.15 }

local vsx, vsy = Spring.GetViewGeometry()
local enabled, scale = true, 1.0
local panels = {}                   -- res -> { shown, hist = {}, histT, rect }
for _, r in ipairs(ORDER) do panels[r] = { shown = 0, hist = {}, histT = 0, rect = nil, flash = 0 } end
local stockBarHidden = false

local function Sc(v) return v * scale * max(0.75, min(1.8, vsy / 1080)) end

--------------------------------------------------------------------------------
-- stock bar on / off
--------------------------------------------------------------------------------
local function HideStock(hide)
	if hide == stockBarHidden then return end
	stockBarHidden = hide
	Spring.SendCommands(hide and "resbar 0" or "resbar 1")
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function Fmt(v)
	v = v or 0
	local a = abs(v)
	if a >= 100000 then return string.format("%dk", floor(v / 1000 + 0.5))
	elseif a >= 10000 then return string.format("%.1fk", v / 1000)
	else return string.format("%d", floor(v + 0.5)) end
end
local function FmtRate(v)
	v = v or 0
	local a = abs(v)
	if a >= 1000 then return string.format("%.1fk", v / 1000) end
	if a >= 100 then return string.format("%d", floor(v + 0.5)) end
	return string.format("%.1f", v)
end

local function VGrad(x1, y1, x2, y2, top, bot, a)
	glBeginEnd(GL.QUADS, function()
		glColor(bot[1], bot[2], bot[3], a); glVertex(x1, y1); glVertex(x2, y1)
		glColor(top[1], top[2], top[3], a); glVertex(x2, y2); glVertex(x1, y2)
	end)
end

local function Frame(x1, y1, x2, y2, c, a, w)
	glColor(c[1], c[2], c[3], a)
	glRect(x1, y2 - w, x2, y2); glRect(x1, y1, x2, y1 + w); glRect(x1, y1, x1 + w, y2); glRect(x2 - w, y1, x2, y2)
end

-- glyphs: a drop-like diamond for metal and a bolt for energy, drawn from plain triangles
local function Glyph(res, cx, cy, r, c, a)
	glColor(c[1], c[2], c[3], a)
	if res == "metal" then
		glBeginEnd(GL.TRIANGLE_FAN, function()
			glVertex(cx, cy + r); glVertex(cx + r * 0.8, cy); glVertex(cx, cy - r); glVertex(cx - r * 0.8, cy)
		end)
		glColor(1, 1, 1, a * 0.45)
		glBeginEnd(GL.TRIANGLES, function()
			glVertex(cx, cy + r * 0.8); glVertex(cx + r * 0.3, cy); glVertex(cx - r * 0.45, cy + r * 0.05)
		end)
	else
		glBeginEnd(GL.TRIANGLE_FAN, function()
			glVertex(cx + r * 0.15, cy + r); glVertex(cx - r * 0.55, cy - r * 0.1); glVertex(cx - r * 0.05, cy - r * 0.1)
			glVertex(cx - r * 0.2, cy - r); glVertex(cx + r * 0.6, cy + r * 0.15); glVertex(cx + r * 0.05, cy + r * 0.15)
		end)
	end
end

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------
local data = {}
local nextPoll, nextHist = 0, 0

local function Poll(now)
	local team = spGetMyTeamID()
	for _, res in ipairs(ORDER) do
		local cur, stor, pull, inc, exp, share, sent, recv, excess = spGetTeamResources(team, res)
		local d = { cur = cur or 0, stor = max(stor or 1, 1), pull = pull or 0, inc = inc or 0, exp = exp or 0,
			share = share or 0, excess = excess or 0, recv = recv or 0, sent = sent or 0 }
		data[res] = d
	end
	if now >= nextHist then
		nextHist = now + 1
		for _, res in ipairs(ORDER) do
			local d, p = data[res], panels[res]
			p.hist[#p.hist + 1] = d.inc - d.exp
			if #p.hist > HISTORY then table.remove(p.hist, 1) end
		end
	end
end

function widget:Update()
	if not widget.t0 then widget.t0 = Spring.GetTimer() end
	local now = Spring.DiffTimers(Spring.GetTimer(), widget.t0)
	if now >= nextPoll then nextPoll = now + 0.25; Poll(now) end
	-- ease the shown stock toward the real one (about a quarter of a second)
	for _, res in ipairs(ORDER) do
		local d, p = data[res], panels[res]
		if d then p.shown = p.shown + (d.cur - p.shown) * 0.25 end
	end
end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------
local function DrawPanel(res, x1, y1, x2, y2, t)
	local d, p, C = data[res], panels[res], COLORS[res]
	if not d then return end
	local main, dark = C.main, C.dark
	local frac = min(1, max(0, p.shown / d.stor))
	local net = d.inc - d.exp
	local full = d.cur >= d.stor * 0.97
	local starving = d.cur < d.stor * 0.02 and d.pull > d.inc + 0.5

	-- body
	VGrad(x1, y1, x2, y2, { 0.07, 0.08, 0.11 }, { 0.03, 0.035, 0.05 }, 0.88)
	local frameC = main
	local fa = 0.55
	if starving then frameC = DOWN; fa = 0.45 + 0.45 * (0.5 + 0.5 * sin(t * 7))
	elseif full then frameC = WARN; fa = 0.45 + 0.4 * (0.5 + 0.5 * sin(t * 4)) end
	Frame(x1, y1, x2, y2, frameC, fa, 1)
	glColor(main[1], main[2], main[3], 0.35); glRect(x1 + 1, y2 - 2, x2 - 1, y2 - 1)

	-- glyph
	local h = y2 - y1
	local gr = h * 0.20
	Glyph(res, x1 + Sc(14), y2 - h * 0.34, gr, main, 0.95)

	-- big stock number and name
	local numX = x1 + Sc(30)
	VBFont.Text(Fmt(p.shown), numX, y2 - h * 0.46, Sc(19), "o", 1, 1, 1, 1)
	local nw = VBFont.Width(Fmt(p.shown), Sc(19))
	VBFont.Text("/ " .. Fmt(d.stor), numX + nw + Sc(5), y2 - h * 0.43, Sc(10), "o", 0.65, 0.7, 0.78, 0.9)

	-- income / spend on the right
	local rx = x2 - Sc(8)
	local netUp = net > -0.05
	local netC = netUp and UP or DOWN
	VBFont.Text((netUp and "+" or "-") .. FmtRate(abs(net)) .. "/s", rx, y2 - h * 0.40, Sc(13), "or", netC[1], netC[2], netC[3], 1)
	VBFont.Text("in " .. FmtRate(d.inc) .. "   out " .. FmtRate(d.exp), rx, y2 - h * 0.62, Sc(8.5), "or", 0.62, 0.68, 0.76, 0.9)

	-- storage bar
	local bx1, bx2 = x1 + Sc(8), x2 - Sc(8)
	local by1, by2 = y1 + Sc(5), y1 + Sc(5) + max(Sc(12), h * 0.22)
	glColor(dark[1], dark[2], dark[3], 0.9); glRect(bx1, by1, bx2, by2)
	local fx = bx1 + (bx2 - bx1) * frac
	if fx > bx1 then
		local top = { min(1, main[1] + 0.15), min(1, main[2] + 0.15), min(1, main[3] + 0.15) }
		local pulse = full and (0.75 + 0.25 * sin(t * 6)) or 1
		VGrad(bx1, by1, fx, by2, top, { main[1] * 0.55, main[2] * 0.55, main[3] * 0.55 }, pulse)
		glColor(1, 1, 1, 0.35); glRect(bx1, by2 - 1, fx, by2)
	end
	-- tick marks every quarter
	glColor(0, 0, 0, 0.45)
	for i = 1, 3 do local tx = bx1 + (bx2 - bx1) * i / 4; glRect(tx, by1, tx + 1, by2) end
	Frame(bx1, by1, bx2, by2, main, 0.35, 1)

	-- trend line (60 s of net flow), drawn between the number row and the bar
	local hist = p.hist
	if #hist >= 2 then
		local lx1, lx2 = numX, x2 - Sc(86)
		local ly1, ly2 = by2 + Sc(3), by2 + Sc(3) + h * 0.17
		if lx2 - lx1 > 20 and ly2 - ly1 > 4 then
			local lo, hi = 0, 0
			for _, v in ipairs(hist) do lo = min(lo, v); hi = max(hi, v) end
			if hi - lo < 1 then hi = lo + 1 end
			-- zero line
			local zy = ly1 + (ly2 - ly1) * (0 - lo) / (hi - lo)
			glColor(1, 1, 1, 0.12); glRect(lx1, zy, lx2, zy + 1)
			glLineWidth(1.5)
			glColor(main[1], main[2], main[3], 0.9)
			glBeginEnd(GL.LINE_STRIP, function()
				for i, v in ipairs(hist) do
					glVertex(lx1 + (lx2 - lx1) * (i - 1) / (HISTORY - 1), ly1 + (ly2 - ly1) * (v - lo) / (hi - lo))
				end
			end)
			glLineWidth(1)
		end
	end

	-- warnings: centred on the storage bar, on a dark plate so they never mix with the numbers above
	local msg, wc, wa
	if starving then msg, wc, wa = "STALLED", DOWN, 0.75 + 0.25 * sin(t * 7)
	elseif full and d.inc > 0.5 then msg, wc, wa = "FULL - WASTING", WARN, 0.75 + 0.25 * sin(t * 4) end
	if msg then
		local size = min(Sc(9), (by2 - by1) * 0.95)
		local tw = VBFont.Width(msg, size) + Sc(14)
		local cx, cy = (bx1 + bx2) / 2, (by1 + by2) / 2
		glColor(0, 0, 0, 0.6); glRect(cx - tw / 2, by1, cx + tw / 2, by2)
		VBFont.Text(msg, cx, cy - size * 0.35, size, "oc", wc[1], wc[2], wc[3], wa)
	end
end

function widget:DrawScreen()
	if not enabled then return end
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
	local t2 = os.clock()      -- wall clock: the warnings keep pulsing while the game is paused
	local w, h, gap = Sc(250), Sc(62), Sc(6)
	local x2 = vsx - Sc(8)
	local y2 = vsy - Sc(4)
	for i = #ORDER, 1, -1 do
		local res = ORDER[i]
		local x1 = x2 - w
		panels[res].rect = { x1, y2 - h, x2, y2 }
		DrawPanel(res, x1, y2 - h, x2, y2, t2)
		x2 = x1 - gap
	end
end

--------------------------------------------------------------------------------
-- hover tooltip
--------------------------------------------------------------------------------
local function Hit(x, y)
	if not enabled then return nil end
	for _, res in ipairs(ORDER) do
		local r = panels[res].rect
		if r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then return res end
	end
end

function widget:IsAbove(x, y) return Hit(x, y) ~= nil end

function widget:GetTooltip(x, y)
	local res = Hit(x, y)
	local d = res and data[res]
	if not d then return nil end
	local lines = {
		COLORS[res].name .. ":  " .. Fmt(d.cur) .. " of " .. Fmt(d.stor) .. string.format("  (%d%%)", floor(d.cur / d.stor * 100 + 0.5)),
		string.format("Income %s/s   Spending %s/s   Net %s%s/s", FmtRate(d.inc), FmtRate(d.exp), (d.inc - d.exp) >= 0 and "+" or "-", FmtRate(abs(d.inc - d.exp))),
		string.format("Demand (what everything wants to spend): %s/s", FmtRate(d.pull)),
	}
	if d.excess > 0.5 then lines[#lines + 1] = string.format("Wasted (storage full): %s/s", FmtRate(d.excess)) end
	if d.recv > 0.5 or d.sent > 0.5 then lines[#lines + 1] = string.format("Shared: received %s, sent %s", Fmt(d.recv), Fmt(d.sent)) end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- lifecycle, settings
--------------------------------------------------------------------------------
function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:Initialize()
	vsx, vsy = Spring.GetViewGeometry()
	widget.t0 = Spring.GetTimer()
	HideStock(enabled)
end

function widget:Shutdown() HideStock(false) end

function widget:TextCommand(cmd)
	local word, rest = cmd:match("^(%S+)%s*(.*)$")
	if word ~= "vbresbar" then return false end
	local arg, val = rest:match("^(%S*)%s*(.*)$")
	if arg == "scale" then
		scale = max(0.6, min(2.0, tonumber(val) or 1))
	else
		enabled = not enabled
		HideStock(enabled)
		Spring.Echo("[VB] resource bar " .. (enabled and "on" or "off (stock bar restored)"))
	end
	return true
end

function widget:GetConfigData() return { enabled = enabled, scale = scale } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.enabled ~= nil then enabled = d.enabled end
	if d.scale then scale = max(0.6, min(2.0, d.scale)) end
end
