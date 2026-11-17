function widget:GetInfo()
	return { name = "Voidborn Unit Census", desc = "Docked HUD panel: figures and distributions of specs for the SELECTED units (/vbdock census)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true }
end

-- What it shows (all values are the LIVE ones, so /vbcreate changes, growth and experience bonuses are included):
--   * totals: units, structures/mobile, combined health, metal value, experience average/max, splits so far
--   * one page at a time: the distribution (histogram) of health, speed, range, damage/s, experience or size,
--     the unit types present, or the units closest to splitting - pick it with the small tabs
-- It covers exactly the current selection.  It lives in the dock column (LuaUI/Widgets/vb_dock.lua) and is self-contained:
-- - folds it to its title bar, x switches it off (dashboard > SETTINGS or /vbdock census or /vbstats switch it on again).
local okK, K = pcall(VFS.Include, "LuaUI/Headers/vb_dockui.h.lua")
if not okK or type(K) ~= "table" then
	Spring.Echo("[VB] census: could not load LuaUI/Headers/vb_dockui.h.lua: " .. tostring(K))
	return
end
local VBFont = K.Font

local SPLIT_XP     = 0.14     -- the default of LuaRules/Gadgets/vb_experience.lua; the live value is read from the game rules below
local REFRESH      = 15       -- frames between census updates
local MAX_UNITS    = 2000
local BINS         = 20
local PAD, ROW     = 8, 13    -- dock units

local METRICS = {   -- key, label, short tab label, colour, fixed [lo,hi] (nil = from data)
	{ "hp",    "HEALTH",     "HP",   { 0.4, 1.0, 0.5 } },
	{ "speed", "SPEED",      "SPD",  { 0.8, 0.7, 1.0 } },
	{ "range", "RANGE",      "RNG",  { 0.4, 0.9, 1.0 } },
	{ "dps",   "DAMAGE / S", "DPS",  { 1.0, 0.45, 0.35 } },
	{ "xp",    "EXPERIENCE", "XP",   { 1.0, 0.9, 0.3 }, 0, SPLIT_XP },
	{ "size",  "SIZE",       "SIZE", { 0.65, 0.8, 1.0 }, 1, 1.45 },
}
local PAGES = {}
for _, m in ipairs(METRICS) do PAGES[#PAGES + 1] = { id = m[1], label = m[3], metric = m } end
PAGES[#PAGES + 1] = { id = "types", label = "TYPES" }
PAGES[#PAGES + 1] = { id = "split", label = "SPLIT" }

local P = K.New("census", "UNIT CENSUS")
local page = "hp"
local census = nil   -- last result
local C_AMBER = K.AMBER

local function SplitXP() return tonumber(Spring.GetGameRulesParam and Spring.GetGameRulesParam("vb_split_xp")) or SPLIT_XP end

-- ------------------------------------------------------------------ helpers
local function Num(n, dec)
	n = tonumber(n) or 0
	if math.abs(n) >= 10000 then return string.format("%.1fk", n / 1000) end
	if dec and dec > 0 then return string.format("%." .. dec .. "f", n) end
	if math.abs(n - math.floor(n + 0.5)) < 0.05 then return string.format("%d", math.floor(n + 0.5)) end
	return string.format("%.1f", n)
end
local Box, Frame = K.Box, K.Frame

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
	local vmin, vmax, sum = math.huge, -math.huge, 0
	for i = 1, n do local v = vals[i]; sum = sum + v; if v < vmin then vmin = v end; if v > vmax then vmax = v end end
	if not lo then lo, hi = vmin, vmax end
	local bins = {}
	for i = 1, BINS do bins[i] = 0 end
	local span = hi - lo
	for i = 1, n do
		local b = span <= 0 and 1 or math.min(BINS, math.max(1, math.floor((vals[i] - lo) / span * BINS) + 1))
		bins[b] = bins[b] + 1
	end
	local top = 0
	for i = 1, BINS do if bins[i] > top then top = bins[i] end end
	return { bins = bins, lo = lo, hi = hi, top = top, n = n, avg = sum / n, min = vmin, max = vmax }
end

local function Census()
	local all = Spring.GetSelectedUnits() or {}     -- only the units the player has selected
	local C = { n = 0, mobile = 0, static = 0, hp = 0, value = 0, xpSum = 0, xpMax = 0, splits = 0, vals = {}, types = {}, tops = {} }
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
	for _, m in ipairs(METRICS) do C.hist[m[1]] = Histogram(C.vals[m[1]], m[5], m[6]) end
	C.typeList = {}
	for _, t in pairs(C.types) do C.typeList[#C.typeList + 1] = t end
	table.sort(C.typeList, function(a, b) return a.n > b.n end)
	table.sort(C.tops, function(a, b) return a.xp > b.xp end)
	C.vals = nil
	return C
end

-- ------------------------------------------------------------------ drawing
local TAB_H, VIEW_H = 16, 100
local H_OPEN = K.TITLE + 6 + 3 * ROW + 6 + TAB_H + 4 + VIEW_H + PAD       -- dock units
local H_EMPTY = K.TITLE + 24

function widget:Initialize()
	if not (WG and WG.VBDock) then Spring.Echo("[VB] census: needs the Voidborn Dock widget (vb_dock)") end
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbstats", function() if WG.VBDock then WG.VBDock.ToggleOn("census") end return true end, nil, "t")
	end
	Spring.Echo("[VB] Unit census loaded: a docked panel for the selected units (/vbstats or the dashboard SETTINGS switch it on and off)")
end
function widget:Shutdown() if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbstats") end end
function widget:TextCommand(cmd) if cmd == "vbstats" and WG.VBDock then WG.VBDock.ToggleOn("census"); return true end end

function widget:SelectionChanged() census = nil end     -- rebuild at once when the selection changes

function widget:Update()
	if WG.VBDock and not WG.VBDock.IsOn("census") then census = nil return end
	if (Spring.GetSelectedUnitsCount() or 0) == 0 then census = nil return end   -- nothing selected: no figures
	local f = Spring.GetGameFrame()
	if not census or f % REFRESH == 0 and f ~= (widget.lastF or -1) then
		widget.lastF = f
		local ok, res = pcall(Census)
		if ok then census = res else if not widget.warned then widget.warned = true; Spring.Echo("[VB] census error: " .. tostring(res)) end end
	end
end

local function Fmt(key, v) return Num(v, key == "xp" and 3 or key == "size" and 2 or 0) end

function widget:DrawScreen()
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
	local sel = census ~= nil
	local x1, y1, x2, y2, S, folded = P:Frame(sel and H_OPEN or H_EMPTY, K.TITLE)
	if not x1 then return end
	local C = census
	local tag
	if C then tag = "[" .. C.n .. (C.n == 1 and " unit]" or " units]") end
	local top = P:Title(x1, y2, x2, S, tag)
	if folded then return end
	if not C then
		VBFont.Text("select units to see their figures", (x1 + x2) / 2, top - 15 * S, 9 * S, "oc", 0.55, 0.58, 0.65, 1)
		return
	end
	local W = x2 - x1
	local pad = PAD * S
	local y = top - 6 * S
	local function Row(l1, v1, l2, v2, c)
		y = y - ROW * S
		VBFont.Text(l1, x1 + pad, y + 2 * S, 9 * S, "o", 0.62, 0.62, 0.72, 1)
		VBFont.Text(v1, x1 + W / 2 - 10 * S, y + 2 * S, 10 * S, "or", c[1], c[2], c[3], 1)
		VBFont.Text(l2, x1 + W / 2 + 4 * S, y + 2 * S, 9 * S, "o", 0.62, 0.62, 0.72, 1)
		VBFont.Text(v2, x2 - pad, y + 2 * S, 10 * S, "or", c[1], c[2], c[3], 1)
	end
	local avgXp = C.n > 0 and C.xpSum / C.n or 0
	Row("UNITS", Num(C.n), "MOBILE / STRUCT", C.mobile .. "/" .. C.static, { 1, 1, 1 })
	Row("TOTAL HEALTH", Num(C.hp), "METAL VALUE", Num(C.value), { 0.65, 0.8, 1 })
	Row("AVG XP", Num(avgXp, 3), "MAX XP", Num(C.xpMax, 3) .. "  SPLITS " .. Num(C.splits), { 1, 0.9, 0.3 })
	y = y - 6 * S

	-- page tabs
	local tw = (W - 2 * pad) / #PAGES
	local ty1, ty2 = y - TAB_H * S, y
	for i, pg in ipairs(PAGES) do
		local tx1 = x1 + pad + (i - 1) * tw
		local act = pg.id == page
		P:Button(tx1 + 1, ty1, tx1 + tw - 1, ty2, pg.label, 8 * S, function() page = pg.id end, "Show " .. pg.label, act)
	end
	y = ty1 - 4 * S

	-- the page
	local vy2, vy1 = y, y - VIEW_H * S
	local vx1, vx2 = x1 + pad, x2 - pad
	Box(vx1, vy1, vx2, vy2, 0.02, 0.02, 0.05, 0.55)
	if page == "types" then
		local yy = vy2 - 12 * S
		local cA = C_AMBER
		VBFont.Text("TYPE", vx1 + 4 * S, yy, 8 * S, "o", cA[1], cA[2], cA[3], 1)
		VBFont.Text("N", vx1 + 150 * S, yy, 8 * S, "or", cA[1], cA[2], cA[3], 1)
		VBFont.Text("HP%", vx1 + 200 * S, yy, 8 * S, "or", cA[1], cA[2], cA[3], 1)
		VBFont.Text("AVG XP", vx2 - 4 * S, yy, 8 * S, "or", cA[1], cA[2], cA[3], 1)
		local maxRows = 6
		for i = 1, math.min(#C.typeList, maxRows) do
			local t = C.typeList[i]
			yy = yy - ROW * S
			VBFont.Text(string.sub(t.name, 1, 18), vx1 + 4 * S, yy, 9 * S, "o", 1, 1, 1, 1)
			VBFont.Text(tostring(t.n), vx1 + 150 * S, yy, 9 * S, "or", 0.9, 0.9, 0.9, 1)
			VBFont.Text(string.format("%d", math.floor(t.hpf / t.n * 100 + 0.5)), vx1 + 200 * S, yy, 9 * S, "or", 0.4, 1, 0.5, 1)
			VBFont.Text(Num(t.xp / t.n, 3), vx2 - 4 * S, yy, 9 * S, "or", 1, 0.9, 0.3, 1)
		end
		if #C.typeList > maxRows then VBFont.Text("+" .. (#C.typeList - maxRows) .. " more types", vx1 + 4 * S, yy - ROW * S, 8 * S, "o", 0.5, 0.55, 0.65, 1) end
	elseif page == "split" then
		local yy = vy2 - 12 * S
		VBFont.Text("CLOSEST TO SPLITTING", vx1 + 4 * S, yy, 8 * S, "o", C_AMBER[1], C_AMBER[2], C_AMBER[3], 1)
		local sx = SplitXP()
		if #C.tops == 0 then VBFont.Text("no mobile unit has any experience yet", vx1 + 4 * S, yy - ROW * S, 9 * S, "o", 0.5, 0.55, 0.65, 1) end
		for i = 1, math.min(#C.tops, 6) do
			local t = C.tops[i]
			yy = yy - ROW * S
			VBFont.Text(string.sub(t.name, 1, 16), vx1 + 4 * S, yy, 9 * S, "o", 1, 1, 1, 1)
			local bx1, bx2 = vx1 + 120 * S, vx2 - 40 * S
			Box(bx1, yy + 1 * S, bx2, yy + 7 * S, 0.02, 0.02, 0.05, 0.9)
			local f = math.min(1, t.xp / sx)
			Box(bx1, yy + 1 * S, bx1 + (bx2 - bx1) * f, yy + 7 * S, 1.0, 0.9 * (1 - f * 0.4), 0.3, 0.95)
			VBFont.Text(string.format("%d%%", math.floor(f * 100)), vx2 - 4 * S, yy, 9 * S, "or", 1, 0.9, 0.3, 1)
		end
	else
		local m
		for _, mm in ipairs(METRICS) do if mm[1] == page then m = mm end end
		local h, col = C.hist[page], m[4]
		VBFont.Text(m[2], vx1 + 4 * S, vy2 - 12 * S, 9 * S, "o", col[1], col[2], col[3], 1)
		if not h then
			VBFont.Text("none of the selected units has this", vx1 + 4 * S, vy2 - 40 * S, 9 * S, "o", 0.5, 0.55, 0.65, 1)
		else
			VBFont.Text(Fmt(page, h.lo) .. " - " .. Fmt(page, h.hi) .. "   N=" .. h.n, vx2 - 4 * S, vy2 - 12 * S, 8 * S, "or", 0.62, 0.62, 0.72, 1)
			local cy1, cy2 = vy1 + 16 * S, vy2 - 18 * S
			local bw = (vx2 - vx1 - 8 * S) / BINS
			for i = 1, BINS do
				local c = h.bins[i]
				if c > 0 then
					local bh = math.max(2 * S, c / h.top * (cy2 - cy1))
					Box(vx1 + 4 * S + (i - 1) * bw + 1, cy1, vx1 + 4 * S + i * bw - 1, cy1 + bh, col[1], col[2], col[3], 0.85)
				end
			end
			Box(vx1 + 4 * S, cy1 - 1, vx2 - 4 * S, cy1, col[1], col[2], col[3], 0.4)
			-- the average as a marker
			if h.hi > h.lo then
				local ax = vx1 + 4 * S + (vx2 - vx1 - 8 * S) * math.min(1, math.max(0, (h.avg - h.lo) / (h.hi - h.lo)))
				Box(ax - 0.5, cy1 - 2 * S, ax + 0.5, cy2, 1, 1, 1, 0.8)
			end
			VBFont.Text("AVG " .. Fmt(page, h.avg) .. "   MIN " .. Fmt(page, h.min) .. "   MAX " .. Fmt(page, h.max), vx1 + 4 * S, vy1 + 4 * S, 8 * S, "o", 0.75, 0.78, 0.86, 1)
		end
	end
end

function widget:IsAbove(x, y) return P:IsAbove(x, y) end
function widget:MousePress(x, y, b) return P:Press(x, y, b) end
function widget:MouseMove(x, y) P:Move(x, y) end
function widget:MouseRelease() P:Release() end
function widget:GetTooltip(x, y) return P:Tip(x, y) end

function widget:GetConfigData() return { page = page } end
function widget:SetConfigData(d) if type(d) == "table" and d.page then for _, p in ipairs(PAGES) do if p.id == d.page then page = d.page end end end end
