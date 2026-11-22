function widget:GetInfo()
	return { name = "Voidborn HUD", desc = "One widget for the Voidborn interface: resource panels (top right), 3D pill health bars, and a wiggly snake progress bar above features while metal / energy is reclaimed from them",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true }
end

-- Replaces vb_resbar.lua and vb_healthbars.lua (disable or delete those two when you use this one).
--
--   /vbhud                       prints the current settings
--   /vbhud resbar [on|off]       resource panels (the stock bar comes back when they are off)
--   /vbhud scale 1.2             size of the resource panels (0.6 .. 2.0)
--   /vbhud health [mode]         selected / always / damaged / off  (no argument cycles)
--   /vbhud reclaim [mode]        active / partial / off             (no argument cycles)
-- The old commands /vbresbar [scale n], /vbhealth and /vbreclaim still work.
--
-- RECLAIM SNAKE
--   While a unit reclaims a feature (mushroom, tree, wreck, rock ...) a snake grows above it.  The snake is the
--   progress bar: its head slithers along the track as the feature is eaten.  The body colour follows what the
--   feature holds: blue for metal, amber for energy, blended when it holds both.  The snake wriggles faster while
--   reclaiming is going on, flicks its tongue, and fades out a few seconds after the last reclaim tick.
--   "partial" mode keeps a faint snake on every half eaten feature in view.  When a feature is eaten completely a
--   "+N M  +N E" popup floats up, and the resource panel shows a RECLAIM +N/s tag and a soft glow.

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local spGetTeamResources, spGetMyTeamID = Spring.GetTeamResources, Spring.GetMyTeamID
local spGetVisibleUnits   = Spring.GetVisibleUnits
local spGetUnitHealth     = Spring.GetUnitHealth
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitHeight     = Spring.GetUnitHeight
local spGetUnitRadius     = Spring.GetUnitRadius
local spGetUnitTeam       = Spring.GetUnitTeam
local spIsUnitSelected    = Spring.IsUnitSelected
local spAreTeamsAllied    = Spring.AreTeamsAllied
local spGetVisibleFeatures   = Spring.GetVisibleFeatures
local spGetFeatureResources  = Spring.GetFeatureResources
local spGetFeaturePosition   = Spring.GetFeaturePosition
local spGetFeatureRadius     = Spring.GetFeatureRadius
local spGetFeatureHeight     = Spring.GetFeatureHeight

local glColor, glRect, glBeginEnd, glVertex, glLineWidth = gl.Color, gl.Rect, gl.BeginEnd, gl.Vertex, gl.LineWidth
local glPushMatrix, glPopMatrix, glTranslate, glBillboard = gl.PushMatrix, gl.PopMatrix, gl.Translate, gl.Billboard
local min, max, floor, sin, cos, sqrt, abs, pi = math.min, math.max, math.floor, math.sin, math.cos, math.sqrt, math.abs, math.pi

--------------------------------------------------------------------------------
-- settings
--------------------------------------------------------------------------------
local HEALTH_MODES  = { "selected", "always", "damaged", "off" }
local RECLAIM_MODES = { "active", "partial", "off" }
local resbarOn, scale = true, 1.0
local healthMode  = "selected"
local reclaimMode = "active"

local MAX_BARS    = 500      -- never draw more than this many health bars in one frame
local MAX_SNAKES  = 40       -- ... or this many reclaim snakes
local HOLD        = 3.5      -- seconds a reclaim snake stays after the last change
local HISTORY     = 60       -- seconds of trend line on the resource panels

local COLORS = {
	metal  = { name = "METAL",  main = { 0.55, 0.85, 1.00 }, dark = { 0.10, 0.22, 0.30 } },
	energy = { name = "ENERGY", main = { 1.00, 0.80, 0.30 }, dark = { 0.30, 0.22, 0.06 } },
}
local ORDER = { "metal", "energy" }
local UP, DOWN, WARN = { 0.45, 1.00, 0.55 }, { 1.00, 0.45, 0.40 }, { 1.00, 0.62, 0.15 }
local MC, EC = COLORS.metal.main, COLORS.energy.main

local vsx, vsy = Spring.GetViewGeometry()
local panels = {}                   -- res -> { shown, hist, rect, flash, recAcc, recRate }
for _, r in ipairs(ORDER) do panels[r] = { shown = 0, hist = {}, rect = nil, flash = 0, recAcc = 0, recRate = 0 } end
local stockBarHidden = false

local function Sc(v) return v * scale * max(0.75, min(1.8, vsy / 1080)) end

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
-- resource data
--------------------------------------------------------------------------------
local data = {}
local nextPoll, nextHist, nextRate = 0, 0, 0

local function Poll(now)
	local team = spGetMyTeamID()
	for _, res in ipairs(ORDER) do
		local cur, stor, pull, inc, exp, share, sent, recv, excess = spGetTeamResources(team, res)
		data[res] = { cur = cur or 0, stor = max(stor or 1, 1), pull = pull or 0, inc = inc or 0, exp = exp or 0,
			share = share or 0, excess = excess or 0, recv = recv or 0, sent = sent or 0 }
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

--------------------------------------------------------------------------------
-- reclaim tracking
--------------------------------------------------------------------------------
-- feats[featureID] = { left, shown, phase, lastChange, lastDown, x, y, z, rad, ht, dm, de, gm, ge, seen }
-- only features that are partly reclaimed are tracked, so the scan stays cheap on maps full of mushrooms
local feats, popups = {}, {}
local scanId, nextScan = 0, 0

local function AddGain(gm, ge)
	if gm > 0 then local p = panels.metal;  p.recAcc = p.recAcc + gm; p.flash = 1 end
	if ge > 0 then local p = panels.energy; p.recAcc = p.recAcc + ge; p.flash = 1 end
end

local function ScanFeatures(now)
	local list = spGetVisibleFeatures(-1, nil, false, false)
	if not list then return end
	scanId = scanId + 1
	for i = 1, #list do
		local fid = list[i]
		local _, defM, _, defE, left = spGetFeatureResources(fid)
		if left then
			defM, defE = defM or 0, defE or 0
			local st = feats[fid]
			if not st and left < 0.9999 and (defM > 0 or defE > 0) then
				local fx, fy, fz = spGetFeaturePosition(fid)
				if fx then
					st = { left = left, shown = 1 - left, phase = 0, lastChange = -1000, lastDown = -1000,
						x = fx, y = fy, z = fz, rad = spGetFeatureRadius(fid) or 16, ht = spGetFeatureHeight(fid) or 16,
						dm = defM, de = defE, gm = 0, ge = 0 }
					feats[fid] = st
				end
			end
			if st then
				st.seen = scanId
				st.dm, st.de = defM, defE
				if left >= 0.9999 then
					feats[fid] = nil
				elseif abs(left - st.left) > 1e-5 then
					if left < st.left then
						local d = st.left - left
						st.gm, st.ge = st.gm + d * defM, st.ge + d * defE
						AddGain(d * defM, d * defE)
						st.lastDown = now
					end
					st.left, st.lastChange = left, now
				end
			end
		end
	end
	for fid, st in pairs(feats) do
		if st.seen ~= scanId then feats[fid] = nil end      -- left the view
	end
end

-- a feature that vanished right after a reclaim tick was eaten up: float a popup with what it gave
function widget:FeatureDestroyed(fid)
	local st = feats[fid]
	if not st then return end
	feats[fid] = nil
	local now = os.clock()
	if now - st.lastChange < 1.5 and st.left < 0.25 then
		local gm, ge = st.gm + st.left * st.dm, st.ge + st.left * st.de
		AddGain(st.left * st.dm, st.left * st.de)
		if gm >= 1 or ge >= 1 then
			popups[#popups + 1] = { x = st.x, y = st.y + max(st.ht, st.rad), z = st.z, t0 = now, m = gm, e = ge }
		end
	end
end

local lastUpd = os.clock()
function widget:Update()
	local now = os.clock()
	local dt = min(0.1, now - lastUpd)
	lastUpd = now
	if now >= nextPoll then nextPoll = now + 0.25; Poll(now) end
	if reclaimMode ~= "off" and now >= nextScan then nextScan = now + 0.1; ScanFeatures(now) end
	if now >= nextRate then
		nextRate = now + 1
		for _, res in ipairs(ORDER) do
			local p = panels[res]
			p.recRate = p.recRate * 0.4 + p.recAcc * 0.6
			p.recAcc = 0
		end
	end
	local k = min(1, dt * 14)         -- ease the shown stock toward the real one
	for _, res in ipairs(ORDER) do
		local d, p = data[res], panels[res]
		if d then p.shown = p.shown + (d.cur - p.shown) * k end
		p.flash = max(0, p.flash - dt * 2.5)
	end
end

--------------------------------------------------------------------------------
-- resource panels (screen space)
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
	if p.flash > 0.01 then glColor(main[1], main[2], main[3], p.flash * 0.10); glRect(x1, y1, x2, y2) end
	local frameC, fa = main, 0.55
	if starving then frameC = DOWN; fa = 0.45 + 0.45 * (0.5 + 0.5 * sin(t * 7))
	elseif full then frameC = WARN; fa = 0.45 + 0.4 * (0.5 + 0.5 * sin(t * 4)) end
	Frame(x1, y1, x2, y2, frameC, fa, 1)
	glColor(main[1], main[2], main[3], 0.35); glRect(x1 + 1, y2 - 2, x2 - 1, y2 - 1)

	-- glyph
	local h = y2 - y1
	Glyph(res, x1 + Sc(14), y2 - h * 0.34, h * 0.20, main, 0.95)

	-- big stock number and capacity
	local numX = x1 + Sc(30)
	VBFont.Text(Fmt(p.shown), numX, y2 - h * 0.46, Sc(19), "o", 1, 1, 1, 1)
	local nw = VBFont.Width(Fmt(p.shown), Sc(19))
	VBFont.Text("/ " .. Fmt(d.stor), numX + nw + Sc(5), y2 - h * 0.43, Sc(10), "o", 0.65, 0.7, 0.78, 0.9)

	-- reclaim tag, shown while something is being eaten
	if p.recRate > 0.5 then
		VBFont.Text("RECLAIM +" .. FmtRate(p.recRate) .. "/s", numX, y2 - h * 0.15, Sc(8), "o", main[1], main[2], main[3], 0.95)
	end

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
	glColor(0, 0, 0, 0.45)
	for i = 1, 3 do local tx = bx1 + (bx2 - bx1) * i / 4; glRect(tx, by1, tx + 1, by2) end
	Frame(bx1, by1, bx2, by2, main, 0.35, 1)

	-- trend line (60 s of net flow)
	local hist = p.hist
	if #hist >= 2 then
		local lx1, lx2 = numX, x2 - Sc(86)
		local ly1, ly2 = by2 + Sc(3), by2 + Sc(3) + h * 0.17
		if lx2 - lx1 > 20 and ly2 - ly1 > 4 then
			local lo, hi = 0, 0
			for _, v in ipairs(hist) do lo = min(lo, v); hi = max(hi, v) end
			if hi - lo < 1 then hi = lo + 1 end
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

	-- warnings, centred on the storage bar on a dark plate
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
	if not resbarOn then return end
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
	local t2 = os.clock()      -- wall clock: warnings keep pulsing while the game is paused
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

local function Hit(x, y)
	if not resbarOn then return nil end
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
	if panels[res].recRate > 0.5 then lines[#lines + 1] = string.format("Reclaiming: +%s/s", FmtRate(panels[res].recRate)) end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- world drawing: shared shapes
--------------------------------------------------------------------------------
-- circle
local CN = 14
local CC, CSN = {}, {}
for i = 0, CN do local a = 2 * pi * i / CN; CC[i], CSN[i] = cos(a), sin(a) end
local function EmitCircle(cx, cy, r)
	glVertex(cx, cy)
	for i = 0, CN do glVertex(cx + r * CC[i], cy + r * CSN[i]) end
end
local function Circle(cx, cy, r, R, G, B, A)
	glColor(R, G, B, A)
	glBeginEnd(GL.TRIANGLE_FAN, EmitCircle, cx, cy, r)
end

-- pill (capsule) for the health bars: a rectangle with half circles at both ends as one triangle fan
local SEG = 6
local PCS, PSN = {}, {}
for i = 0, SEG do local a = pi * i / SEG; PCS[i], PSN[i] = cos(a), sin(a) end
local function EmitPill(x1, y1, x2, y2)
	local r = (y2 - y1) / 2
	local cy = y1 + r
	glVertex((x1 + x2) / 2, cy)
	for i = 0, SEG do glVertex(x2 - r + r * PSN[i], cy - r * PCS[i]) end
	for i = 0, SEG do glVertex(x1 + r - r * PSN[i], cy + r * PCS[i]) end
	glVertex(x2 - r, y1)
end
local function Pill(x1, y1, x2, y2, r, g, b, a)
	glColor(r, g, b, a)
	glBeginEnd(GL.TRIANGLE_FAN, EmitPill, x1, y1, x2, y2)
end

--------------------------------------------------------------------------------
-- health bars
--------------------------------------------------------------------------------
local function HealthColor(f)
	if f > 0.5 then return (1 - f) * 2, 1, 0.1 end
	return 1, f * 2, 0.1
end

-- dark glass tube, liquid that shrinks from the right, highlights so that it looks rounded
local function Tube(x1, y1, x2, y2, f, r, g, b)
	local H = y2 - y1
	local pad = H * 0.14
	local o = max(0.35, H * 0.2)
	Pill(x1 - o, y1 - o, x2 + o, y2 + o, 0, 0, 0, 0.8)
	Pill(x1, y1, x2, y2, 0.10, 0.11, 0.16, 0.92)
	if f > 0.01 then
		local fx2 = min(max(x1 + H - 2 * pad, x1 + (x2 - x1) * f), x2)
		Pill(x1 + pad, y1 + pad, fx2 - pad, y2 - pad, r * 0.55, g * 0.55, b * 0.55, 0.98)
		Pill(x1 + pad, y1 + H * 0.32, fx2 - pad, y2 - pad, r, g, b, 1)
		local hl = H * 0.2
		Pill(x1 + H * 0.45, y2 - pad - hl - H * 0.06, max(x1 + H * 0.45 + hl, fx2 - H * 0.45), y2 - pad - H * 0.06, 1, 1, 1, 0.42)
	end
	Pill(x1 + H * 0.3, y2 - H * 0.38, x2 - H * 0.3, y2 - H * 0.12, 1, 1, 1, 0.1)
end

local function DrawHealth()
	local units = spGetVisibleUnits(-1, nil, false)
	if not units or #units == 0 then return end
	local myTeam = spGetMyTeamID()
	local drawn = 0
	for i = 1, #units do
		local u = units[i]
		local hp, maxhp, _, _, build = spGetUnitHealth(u)
		if hp and maxhp and maxhp > 0 then
			local building = build and build < 1
			local f = max(0, min(1, hp / maxhp))
			local selected = spIsUnitSelected(u)
			local show
			if healthMode == "selected" then show = selected
			else show = building or healthMode == "always" or f < 0.999 or selected end
			if show then
				local x, y, z = spGetUnitPosition(u)
				if x then
					drawn = drawn + 1
					if drawn > MAX_BARS then break end
					local rad = spGetUnitRadius(u) or 20
					local w = max(10, min(80, rad * 0.95))
					-- thickness grows with max health on a log scale
					local h = max(2.2, min(7, 1.8 + (math.log(maxhp) / math.log(10) - 2) * 1.6))
					local top = y + (spGetUnitHeight(u) or rad * 2) + 3 + h
					glPushMatrix()
					glTranslate(x, top, z)
					glBillboard()
					local r, g, b = HealthColor(f)
					local team = spGetUnitTeam(u)
					if team and team ~= myTeam and not (spAreTeamsAllied and spAreTeamsAllied(team, myTeam)) then r, g, b = 1, 0.25 + 0.4 * f, 0.2 end
					Tube(-w, 0, w, h, f, r, g, b)
					if building then
						local h2 = h * 0.6
						Tube(-w * 0.8, -h2 - 2, w * 0.8, -2, build, 0.35, 0.8, 1)
					end
					glPopMatrix()
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- reclaim snake
--------------------------------------------------------------------------------
-- Z holds the parameters of the snake that is being drawn right now, so the emitters need no per call tables.
-- The snake lies along x from x0 to x0 + L (s = 0 is the tail, s = 1 the end of the track) and wiggles in y.
local Z = { L = 60, x0 = -30, amp = 3, k = 2, ph = 0, ms = 1, cr = 0, cg = 0, cb = 0 }
local TWO_PI = 2 * pi

-- height of the path and its slope dy/dx at s; the wave grows toward the head like a real slither
local function PathY(s)
	local th = Z.k * TWO_PI * s - Z.ph
	local e = 0.2 + 0.8 * s
	return Z.amp * e * sin(th), Z.amp * e * cos(th) * Z.k * TWO_PI / Z.L
end

-- body colour at s: metal blue, energy amber, with a soft blend where a feature holds both
local function ColorAt(s)
	local ms = Z.ms
	if ms >= 0.999 then return MC[1], MC[2], MC[3] end
	if ms <= 0.001 then return EC[1], EC[2], EC[3] end
	local t = min(1, max(0, (s - ms) / 0.12 + 0.5))
	return MC[1] + (EC[1] - MC[1]) * t, MC[2] + (EC[2] - MC[2]) * t, MC[3] + (EC[3] - MC[3]) * t
end

-- a ribbon along the path from s0 to s1.  mode 0 = metal/energy colour, 1 = white, 2 = the solid Z.cr/cg/cb colour;
-- lo / hi multiply the colour of the lower / upper edge, which gives the rounded, lit-from-above look.
local function EmitRibbon(s0, s1, w, yoff, lo, hi, mode, a, taper)
	local n = floor((s1 - s0) * 30 + 0.5)
	if n < 2 then n = 2 end
	local L, x0 = Z.L, Z.x0
	for i = 0, n do
		local s = s0 + (s1 - s0) * i / n
		local y, sl = PathY(s)
		local nl = 1 / sqrt(1 + sl * sl)
		local nx, ny = -sl * nl, nl
		local ww = w * 0.5
		if taper then ww = ww * (0.3 + 0.7 * min(1, s / 0.35)) end
		local px, py = x0 + L * s, y + yoff
		local r, g, b
		if mode == 0 then r, g, b = ColorAt(s) elseif mode == 1 then r, g, b = 1, 1, 1 else r, g, b = Z.cr, Z.cg, Z.cb end
		glColor(r * lo, g * lo, b * lo, a)
		glVertex(px - nx * ww, py - ny * ww)
		glColor(r * hi, g * hi, b * hi, a)
		glVertex(px + nx * ww, py + ny * ww)
	end
end

-- little diamond scales along the back
local function EmitScales(sp, w, a)
	local L, x0 = Z.L, Z.x0
	glColor(0, 0, 0, a)
	local s = 0.09
	while s < sp - 0.05 do
		local y = PathY(s)
		local cx = x0 + L * s
		local r = w * 0.17 * (0.5 + 0.5 * min(1, s / 0.35))
		glVertex(cx - r, y); glVertex(cx, y + r); glVertex(cx + r, y)
		glVertex(cx - r, y); glVertex(cx + r, y); glVertex(cx, y - r)
		s = s + 0.075
	end
end

-- forked tongue: base -> tip, tip -> two prongs
local function EmitTongue(bx, by, fx, fy, len)
	local px, py = -fy, fx
	local tx, ty = bx + fx * len, by + fy * len
	glVertex(bx, by); glVertex(tx, ty)
	glVertex(tx, ty); glVertex(tx + fx * len * 0.4 + px * len * 0.35, ty + fy * len * 0.4 + py * len * 0.35)
	glVertex(tx, ty); glVertex(tx + fx * len * 0.4 - px * len * 0.35, ty + fy * len * 0.4 - py * len * 0.35)
end

local function DrawSnake(st, now, dt, a)
	local rad = st.rad
	local L = max(44, min(120, rad * 2.3))
	local w = 4.6 + L * 0.012
	local active = (now - st.lastDown) < 0.6

	Z.L, Z.x0, Z.k = L, -L / 2, L / 30
	st.phase = st.phase + dt * (active and 9 or 3.2)
	Z.ph = st.phase
	Z.amp = w * (active and 0.95 or 0.55)
	local tot = st.dm + st.de
	Z.ms = tot > 0 and st.dm / tot or 1

	st.shown = st.shown + ((1 - st.left) - st.shown) * min(1, dt * 6)
	local sp = min(1, max(0.05, st.shown))
	local top = st.y + max(st.ht, rad) + 12 + w

	glPushMatrix()
	glTranslate(st.x, top, st.z)
	glBillboard()

	-- track: black outline, then the dark empty groove, with round ends
	local o = max(0.9, w * 0.22)
	local y0, y1 = PathY(0), PathY(1)
	Z.cr, Z.cg, Z.cb = 0, 0, 0
	glBeginEnd(GL.TRIANGLE_STRIP, EmitRibbon, 0, 1, w + 2 * o, 0, 1, 1, 2, a * 0.8, false)
	Circle(Z.x0, y0, (w + 2 * o) / 2, 0, 0, 0, a * 0.8)
	Circle(Z.x0 + L, y1, (w + 2 * o) / 2, 0, 0, 0, a * 0.8)
	Z.cr, Z.cg, Z.cb = 0.08, 0.09, 0.13
	glBeginEnd(GL.TRIANGLE_STRIP, EmitRibbon, 0, 1, w, 0, 1, 1, 2, a * 0.92, false)
	Circle(Z.x0, y0, w / 2, 0.08, 0.09, 0.13, a * 0.92)
	Circle(Z.x0 + L, y1, w / 2, 0.08, 0.09, 0.13, a * 0.92)

	-- the snake: shaded body, lit back, scales, glossy stripe
	glBeginEnd(GL.TRIANGLE_STRIP, EmitRibbon, 0, sp, w * 0.9, 0, 0.45, 0.8, 0, a, true)
	glBeginEnd(GL.TRIANGLE_STRIP, EmitRibbon, 0, sp, w * 0.55, w * 0.1, 0.85, 1.2, 0, a, true)
	glBeginEnd(GL.TRIANGLES, EmitScales, sp, w, a * 0.22)
	glBeginEnd(GL.TRIANGLE_STRIP, EmitRibbon, 0.04, sp, w * 0.16, w * 0.2, 1, 1, 1, a * 0.38, true)

	-- head
	local hy, sl = PathY(sp)
	local hx = Z.x0 + L * sp
	local fl = 1 / sqrt(1 + sl * sl)
	local fx, fy = fl, sl * fl                 -- forward direction
	local px, py = -fy, fx                     -- left of forward
	local hr = w * 0.72
	local hr_, hg_, hb_ = ColorAt(sp)
	Circle(hx + fx * hr * 0.45, hy + fy * hr * 0.45, hr * 0.8, hr_ * 0.75, hg_ * 0.75, hb_ * 0.75, a)
	Circle(hx, hy, hr, hr_ * 1.05, hg_ * 1.05, hb_ * 1.05, a)
	Circle(hx - px * hr * 0.2 + fx * hr * 0.1, hy + hr * 0.3, hr * 0.38, 1, 1, 1, a * 0.28)
	for side = -1, 1, 2 do                      -- eyes
		local ex = hx + fx * hr * 0.35 + px * hr * 0.5 * side
		local ey = hy + fy * hr * 0.35 + py * hr * 0.5 * side
		Circle(ex, ey, hr * 0.3, 1, 1, 1, a)
		Circle(ex + fx * hr * 0.1, ey + fy * hr * 0.1, hr * 0.15, 0.05, 0.05, 0.08, a)
	end
	if active and (now * 5) % 1 < 0.55 then      -- tongue flicks while it eats
		glLineWidth(1.3)
		glColor(1, 0.3, 0.35, a)
		glBeginEnd(GL.LINES, EmitTongue, hx + fx * hr * 1.4, hy + fy * hr * 1.4, fx, fy, hr * (0.9 + 0.4 * sin(now * 30)))
		glLineWidth(1)
	end

	-- what is left to reclaim, above the snake
	local rm, re = st.left * st.dm, st.left * st.de
	local parts = {}
	if rm >= 0.5 then parts[#parts + 1] = { string.format("%d M", floor(rm + 0.5)), MC } end
	if re >= 0.5 then parts[#parts + 1] = { string.format("%d E", floor(re + 0.5)), EC } end
	if #parts > 0 then
		local size, gap = 7, 4
		local total = -gap
		for i = 1, #parts do parts[i][3] = gl.GetTextWidth(parts[i][1]) * size; total = total + parts[i][3] + gap end
		local tx, ty = -total / 2, Z.amp + w + 3
		for i = 1, #parts do
			local c = parts[i][2]
			glColor(c[1], c[2], c[3], a)
			gl.Text(parts[i][1], tx, ty, size, "o")
			tx = tx + parts[i][3] + gap
		end
		gl.Texture(false)
	end
	glPopMatrix()
end

local function DrawReclaim(now, dt)
	if reclaimMode ~= "off" then
		local n = 0
		for _, st in pairs(feats) do
			local age = now - st.lastDown
			local a = 0
			if age < HOLD then a = (age > HOLD - 0.8) and (HOLD - age) / 0.8 or 1 end
			if reclaimMode == "partial" then a = max(a, 0.5) end
			if a > 0 then
				n = n + 1
				if n > MAX_SNAKES then break end
				DrawSnake(st, now, dt, a)
			end
		end
	end
	-- "+N M  +N E" popups for features that were eaten completely
	for i = #popups, 1, -1 do
		local p = popups[i]
		local age = now - p.t0
		if age > 2 then
			table.remove(popups, i)
		else
			local fade = age < 1.2 and 1 or (2 - age) / 0.8
			local size = 9 + 4 * max(0, 1 - age * 4)
			glPushMatrix()
			glTranslate(p.x, p.y + 18 + age * 16, p.z)
			glBillboard()
			local line = 0
			if p.m >= 1 then glColor(MC[1], MC[2], MC[3], fade); gl.Text("+" .. Fmt(p.m) .. " M", 0, line, size, "co"); line = line - size - 1 end
			if p.e >= 1 then glColor(EC[1], EC[2], EC[3], fade); gl.Text("+" .. Fmt(p.e) .. " E", 0, line, size, "co") end
			glPopMatrix()
			gl.Texture(false)
		end
	end
end

local lastDraw = os.clock()
function widget:DrawWorld()
	local now = os.clock()
	local dt = min(0.05, now - lastDraw)
	lastDraw = now
	gl.DepthTest(false)
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	if healthMode ~= "off" then DrawHealth() end
	DrawReclaim(now, dt)
	glColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- commands, lifecycle, settings
--------------------------------------------------------------------------------
local function Cycle(list, cur)
	for i, m in ipairs(list) do if m == cur then return list[i % #list + 1] end end
	return list[1]
end
local function InList(list, v) for _, m in ipairs(list) do if m == v then return true end end end

local function Status()
	Spring.Echo(string.format("[VB] HUD: resbar %s (scale %.1f), health bars %s, reclaim snakes %s",
		resbarOn and "on" or "off", scale, healthMode, reclaimMode))
end

local lastLine, lastT = "", 0
local function Dispatch(line)
	local name, rest = line:match("^(%S+)%s*(.*)$")
	if not name then return false end
	local section, args
	if name == "vbhud" then section, args = rest:match("^(%S*)%s*(.*)$")
	elseif name == "vbresbar" then section, args = "resbar", rest
	elseif name == "vbhealth" then section, args = "health", rest
	elseif name == "vbreclaim" then section, args = "reclaim", rest
	else return false end
	local now = os.clock()
	if line == lastLine and now - lastT < 0.1 then return true end   -- action and text command can both fire
	lastLine, lastT = line, now

	local a1, a2 = args:match("^(%S*)%s*(%S*)")
	if section == "scale" then a1, a2, section = "scale", a1, "resbar" end
	if section == "resbar" then
		if a1 == "scale" then scale = max(0.6, min(2.0, tonumber(a2) or 1))
		elseif a1 == "on" then resbarOn = true
		elseif a1 == "off" then resbarOn = false
		else resbarOn = not resbarOn end
		HideStock(resbarOn)
	elseif section == "health" then
		healthMode = InList(HEALTH_MODES, a1) and a1 or Cycle(HEALTH_MODES, healthMode)
	elseif section == "reclaim" then
		reclaimMode = InList(RECLAIM_MODES, a1) and a1 or Cycle(RECLAIM_MODES, reclaimMode)
		if reclaimMode == "off" then feats = {} end
	end
	Status()
	return true
end

function widget:TextCommand(cmd) return Dispatch(cmd) end

function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:Initialize()
	vsx, vsy = Spring.GetViewGeometry()
	HideStock(resbarOn)
	if widgetHandler and widgetHandler.AddAction then
		for _, n in ipairs({ "vbhud", "vbresbar", "vbhealth", "vbreclaim" }) do
			widgetHandler:AddAction(n, function(_, extra) return Dispatch(n .. " " .. (extra or "")) end, nil, "t")
		end
	end
	Status()
end

function widget:Shutdown() HideStock(false) end

-- v = 3: bars only on selected units is the default; settings of the two old widgets are not carried over
function widget:GetConfigData() return { v = 3, resbar = resbarOn, scale = scale, health = healthMode, reclaim = reclaimMode } end
function widget:SetConfigData(d)
	if type(d) ~= "table" or d.v ~= 3 then return end
	if d.resbar ~= nil then resbarOn = d.resbar end
	if d.scale then scale = max(0.6, min(2.0, d.scale)) end
	if InList(HEALTH_MODES, d.health) then healthMode = d.health end
	if InList(RECLAIM_MODES, d.reclaim) then reclaimMode = d.reclaim end
end
