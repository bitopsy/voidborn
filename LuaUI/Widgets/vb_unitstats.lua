function widget:GetInfo()
	return { name = "Voidborn Unit Census", desc = "Shows summary figures + distributions of specs for the SELECTED units only (/vbstats)",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = 6, enabled = true }
end

-- What it shows (all values are the LIVE ones, so /vbcreate changes, growth and experience bonuses are included):
--   * totals: units, structures/mobile, combined health, metal value, experience average/max, splits so far
--   * distributions (histograms) of health, speed, range, damage/s, experience and size
--   * the unit types present (count, average health %, average experience)
--   * the units closest to splitting
-- The panel only exists while units are selected: it covers exactly the current selection and disappears when nothing is selected.
-- /vbstats            show / hide          drag the title bar to move
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local SPLIT_XP     = 0.07     -- keep in sync with LuaRules/Gadgets/vb_experience.lua
local REFRESH      = 15       -- frames between census updates
local MAX_UNITS    = 2000
local BINS         = 14
local W, TITLE, PAD = 300, 20, 8

local vsx, vsy = Spring.GetViewGeometry()
local px, py = nil, nil               -- top-left corner of the panel (set on first draw)
local closed, drag = false, nil
local SCOPE_NAME = "SELECTED"

local C_AMBER = { 0.85, 0.65, 0.2 }
local METRICS = {   -- key, label, colour, fixed [lo,hi] (nil = from data), number format
	{ "hp",    "HEALTH",     { 0.4, 1.0, 0.5 } },
	{ "speed", "SPEED",      { 0.8, 0.7, 1.0 } },
	{ "range", "RANGE",      { 0.4, 0.9, 1.0 } },
	{ "dps",   "DAMAGE / S", { 1.0, 0.45, 0.35 } },
	{ "xp",    "EXPERIENCE", { 1.0, 0.9, 0.3 }, 0, SPLIT_XP },
	{ "size",  "SIZE",       { 0.65, 0.8, 1.0 }, 1, 1.45 },
}

local census = nil   -- last result

-- ------------------------------------------------------------------ helpers
local function Num(n, dec)
	n = tonumber(n) or 0
	if math.abs(n) >= 10000 then return string.format("%.1fk", n / 1000) end
	if dec and dec > 0 then return string.format("%." .. dec .. "f", n) end
	if math.abs(n - math.floor(n + 0.5)) < 0.05 then return string.format("%d", math.floor(n + 0.5)) end
	return string.format("%.1f", n)
end
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end
local function Inside(x, y, r) return r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end

local function Weapons(unitID, ud)
	-- live damage/s: damage x projectiles x salvo / reload, summed over weapons (uses live values when the engine exposes them)
	local dps = 0
	for w, wu in ipairs(ud.weapons or {}) do
		local wd = WeaponDefs[wu.weaponDef]
		if wd then
			local dmg = Spring.GetUnitWeaponDamages and select(2, pcall(Spring.GetUnitWeaponDamages, unitID, w, "default"))
			if type(dmg) ~= "number" then dmg = wd.damages and (wd.damages[0] or wd.damages[1]) or 0 end
			local rl = Spring.GetUnitWeaponState and select(2, pcall(Spring.GetUnitWeaponState, unitID, w, "reloadTime"))
			if type(rl) ~= "number" or rl <= 0 then rl = wd.reload or 1 end
			dps = dps + dmg * (wd.projectiles or 1) * (wd.salvoSize or 1) / math.max(rl, 0.03)
		end
	end
	return dps
end

local function Speed(unitID, ud)
	local ok, mt = pcall(Spring.GetUnitMoveTypeData, unitID)
	if ok and type(mt) == "table" and mt.maxSpeed then return mt.maxSpeed end
	return ud.speed or 0
end

-- ------------------------------------------------------------------ census
local function Histogram(vals, lo, hi)
	local n = #vals
	if n == 0 then return nil end
	if not lo then
		lo, hi = math.huge, -math.huge
		for i = 1, n do local v = vals[i]; if v < lo then lo = v end; if v > hi then hi = v end end
	end
	local bins = {}
	for i = 1, BINS do bins[i] = 0 end
	local span = hi - lo
	for i = 1, n do
		local b = span <= 0 and 1 or math.min(BINS, math.max(1, math.floor((vals[i] - lo) / span * BINS) + 1))
		bins[b] = bins[b] + 1
	end
	local top = 0
	for i = 1, BINS do if bins[i] > top then top = bins[i] end end
	return { bins = bins, lo = lo, hi = hi, top = top }
end

local function Census()
	local all = Spring.GetSelectedUnits() or {}     -- only the units the player has selected
	local C = { n = 0, mobile = 0, static = 0, hp = 0, value = 0, xpSum = 0, xpMax = 0, splits = 0, vals = {}, types = {}, tops = {}, scopeName = SCOPE_NAME }
	for _, m in ipairs(METRICS) do C.vals[m[1]] = {} end
	local count = 0
	for i = 1, #all do
		local u = all[i]
		local defID = Spring.GetUnitDefID(u)
		local ud = defID and UnitDefs[defID]
		if ud then
			count = count + 1
			if count > MAX_UNITS then break end
			local hp, maxhp = Spring.GetUnitHealth(u)
			maxhp = maxhp or ud.health or 0; hp = hp or maxhp
			local xp = Spring.GetUnitExperience(u) or 0
			local scale = Spring.GetUnitRulesParam(u, "vb_scale") or 1
			local mobile = ud.canMove and (ud.speed or 0) > 0
			C.n = C.n + 1
			if mobile then C.mobile = C.mobile + 1 else C.static = C.static + 1 end
			C.hp = C.hp + hp; C.value = C.value + (ud.metalCost or 0)
			C.xpSum = C.xpSum + xp; if xp > C.xpMax then C.xpMax = xp end
			C.splits = C.splits + (Spring.GetUnitRulesParam(u, "vb_splits") or 0)
			local v = C.vals
			v.hp[#v.hp + 1] = maxhp
			if mobile then v.speed[#v.speed + 1] = Speed(u, ud); v.size[#v.size + 1] = scale; v.xp[#v.xp + 1] = xp end
			local range = Spring.GetUnitMaxRange and Spring.GetUnitMaxRange(u) or 0
			if range and range > 0 then v.range[#v.range + 1] = range end
			local dps = Weapons(u, ud)
			if dps > 0 then v.dps[#v.dps + 1] = dps end
			local t = C.types[defID]
			if not t then t = { name = ud.humanName or ud.name, n = 0, hpf = 0, xp = 0 }; C.types[defID] = t end
			t.n = t.n + 1; t.hpf = t.hpf + (maxhp > 0 and hp / maxhp or 1); t.xp = t.xp + xp
			if mobile and xp > 0 then C.tops[#C.tops + 1] = { name = (Spring.GetUnitRulesParam(u, "vb_name") or ud.humanName or ud.name), xp = xp } end
		end
	end
	C.hist = {}
	for _, m in ipairs(METRICS) do C.hist[m[1]] = Histogram(C.vals[m[1]], m[4], m[5]) end
	C.typeList = {}
	for _, t in pairs(C.types) do C.typeList[#C.typeList + 1] = t end
	table.sort(C.typeList, function(a, b) return a.n > b.n end)
	table.sort(C.tops, function(a, b) return a.xp > b.xp end)
	C.vals = nil
	return C
end

-- ------------------------------------------------------------------ drawing
local HIST_H, ROW = 30, 13

local function PanelHeight()
	return TITLE + PAD + 3 * ROW + 6 + #METRICS * (HIST_H + 16) + 6 + 14 + 6 * ROW + 6 + 14 + 4 * ROW + PAD
end

local rects = {}

function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:Initialize()
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbstats", function() closed = not closed; return true end, nil, "t")
	end
	Spring.Echo("[VB] Unit stats loaded: shows the selected units only. /vbstats toggles it, drag the title bar to move it")
end
function widget:Shutdown() if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbstats") end end
function widget:TextCommand(cmd) if cmd == "vbstats" then closed = not closed; return true end end

function widget:SelectionChanged() census = nil end     -- rebuild at once when the selection changes

function widget:Update()
	if closed then return end
	if (Spring.GetSelectedUnitsCount() or 0) == 0 then census = nil return end   -- nothing selected: no panel
	local f = Spring.GetGameFrame()
	if not census or f % REFRESH == 0 and f ~= (widget.lastF or -1) then
		widget.lastF = f
		local ok, res = pcall(Census)
		if ok then census = res else if not widget.warned then widget.warned = true; Spring.Echo("[VB] census error: " .. tostring(res)) end end
	end
end

function widget:DrawScreen()
	if closed or not census then return end
	local H = PanelHeight()
	if not px then px, py = vsx - W - 12, vsy - 80 end
	px = math.max(0, math.min(vsx - W, px)); py = math.max(H, math.min(vsy, py))
	local x1, y2 = px, py
	local x2, y1 = x1 + W, y2 - H
	Box(x1, y1, x2, y2, 0.05, 0.05, 0.09, 0.88)
	Frame(x1, y1, x2, y2, C_AMBER[1], C_AMBER[2], C_AMBER[3], 0.95)
	Box(x1, y2 - TITLE, x2, y2, 0.14, 0.12, 0.22, 0.95)
	VBFont.Text("SELECTED UNITS", x1 + PAD, y2 - TITLE + 6, 11, "o", 1, 0.92, 0.65, 1)
	-- scope tag + close button
	local tag = "[" .. census.n .. (census.n == 1 and " unit]" or " units]")
	local tw = VBFont.Width(tag, 10)
	rects.scope = { x2 - TITLE - tw - 14, y2 - TITLE, x2 - TITLE - 4, y2 }
	VBFont.Text(tag, rects.scope[1] + 5, y2 - TITLE + 6, 10, "o", 0.65, 0.9, 1, 1)
	rects.close = { x2 - TITLE, y2 - TITLE, x2, y2 }
	VBFont.Text("X", x2 - TITLE + 6, y2 - TITLE + 5, 11, "o", 1, 1, 1, 1)
	rects.title = { x1, y2 - TITLE, rects.scope[1], y2 }
	rects.panel = { x1, y1, x2, y2 }

	local y = y2 - TITLE - PAD
	local C = census
	local function Row(l1, v1, l2, v2, c)
		y = y - ROW
		VBFont.Text(l1, x1 + PAD, y + 2, 9, "o", 0.62, 0.62, 0.72, 1)
		VBFont.Text(v1, x1 + W / 2 - 10, y + 2, 10, "or", c[1], c[2], c[3], 1)
		VBFont.Text(l2, x1 + W / 2 + 4, y + 2, 9, "o", 0.62, 0.62, 0.72, 1)
		VBFont.Text(v2, x2 - PAD, y + 2, 10, "or", c[1], c[2], c[3], 1)
	end
	local avgXp = C.n > 0 and C.xpSum / C.n or 0
	Row("UNITS", Num(C.n), "MOBILE / STRUCT", C.mobile .. "/" .. C.static, { 1, 1, 1 })
	Row("TOTAL HEALTH", Num(C.hp), "METAL VALUE", Num(C.value), { 0.65, 0.8, 1 })
	Row("AVG XP", Num(avgXp, 3), "MAX XP", Num(C.xpMax, 3) .. "  SPLITS " .. Num(C.splits), { 1, 0.9, 0.3 })
	y = y - 6

	-- distributions
	local bw = (W - 2 * PAD) / BINS
	for _, m in ipairs(METRICS) do
		local h = C.hist[m[1]]
		local col = m[3]
		y = y - 12
		VBFont.Text(m[2], x1 + PAD, y + 2, 9, "o", col[1], col[2], col[3], 1)
		if h then
			local lab = Num(h.lo, m[1] == "xp" and 3 or m[1] == "size" and 2 or 0) .. " - " .. Num(h.hi, m[1] == "xp" and 3 or m[1] == "size" and 2 or 0)
			VBFont.Text(lab .. "   N=" .. (function() local s = 0; for i = 1, BINS do s = s + h.bins[i] end return s end)(), x2 - PAD, y + 2, 8, "or", 0.62, 0.62, 0.72, 1)
		end
		y = y - HIST_H - 4
		Box(x1 + PAD, y, x2 - PAD, y + HIST_H, 0.02, 0.02, 0.05, 0.7)
		if h and h.top > 0 then
			for i = 1, BINS do
				local c = h.bins[i]
				if c > 0 then
					local bh = math.max(2, c / h.top * (HIST_H - 2))
					Box(x1 + PAD + (i - 1) * bw + 1, y + 1, x1 + PAD + i * bw - 1, y + 1 + bh, col[1], col[2], col[3], 0.85)
				end
			end
		end
	end
	y = y - 6

	-- unit types
	y = y - 12
	VBFont.Text("TYPE", x1 + PAD, y + 2, 9, "o", C_AMBER[1], C_AMBER[2], C_AMBER[3], 1)
	VBFont.Text("N", x1 + 150, y + 2, 9, "or", C_AMBER[1], C_AMBER[2], C_AMBER[3], 1)
	VBFont.Text("HP%", x1 + 205, y + 2, 9, "or", C_AMBER[1], C_AMBER[2], C_AMBER[3], 1)
	VBFont.Text("AVG XP", x2 - PAD, y + 2, 9, "or", C_AMBER[1], C_AMBER[2], C_AMBER[3], 1)
	for i = 1, 6 do
		y = y - ROW
		local t = C.typeList[i]
		if t then
			VBFont.Text(string.sub(t.name, 1, 18), x1 + PAD, y + 2, 9, "o", 1, 1, 1, 1)
			VBFont.Text(tostring(t.n), x1 + 150, y + 2, 9, "or", 0.9, 0.9, 0.9, 1)
			VBFont.Text(string.format("%d", math.floor(t.hpf / t.n * 100 + 0.5)), x1 + 205, y + 2, 9, "or", 0.4, 1, 0.5, 1)
			VBFont.Text(Num(t.xp / t.n, 3), x2 - PAD, y + 2, 9, "or", 1, 0.9, 0.3, 1)
		end
	end
	y = y - 6

	-- closest to splitting
	y = y - 12
	VBFont.Text("CLOSEST TO SPLITTING", x1 + PAD, y + 2, 9, "o", C_AMBER[1], C_AMBER[2], C_AMBER[3], 1)
	for i = 1, 4 do
		y = y - ROW
		local t = C.tops[i]
		if t then
			VBFont.Text(string.sub(t.name, 1, 16), x1 + PAD, y + 2, 9, "o", 1, 1, 1, 1)
			local bx1, bx2 = x1 + 130, x2 - 48
			Box(bx1, y + 3, bx2, y + 9, 0.02, 0.02, 0.05, 0.9)
			local f = math.min(1, t.xp / SPLIT_XP)
			Box(bx1, y + 3, bx1 + (bx2 - bx1) * f, y + 9, 1.0, 0.9 * (1 - f * 0.4), 0.3, 0.95)
			VBFont.Text(string.format("%d%%", math.floor(f * 100)), x2 - PAD, y + 2, 9, "or", 1, 0.9, 0.3, 1)
		end
	end
end

-- ------------------------------------------------------------------ mouse
function widget:IsAbove(x, y) return not closed and census ~= nil and Inside(x, y, rects.panel) end

function widget:MousePress(x, y, button)
	if closed or not census or not Inside(x, y, rects.panel) then return false end
	if Inside(x, y, rects.close) then closed = true; return true end
	if Inside(x, y, rects.title) then drag = { x - px, y - py } end
	return true
end
function widget:MouseMove(x, y) if drag then px, py = x - drag[1], y - drag[2] end end
function widget:MouseRelease() drag = nil end
