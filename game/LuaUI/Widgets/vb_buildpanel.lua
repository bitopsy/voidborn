function widget:GetInfo()
	return { name = "Voidborn Build Panel", desc = "Compact draggable build/order/toggle panel with scale handle and close button",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = 5, enabled = true }
end

-- alien UI font; falls back to the engine font automatically if it cannot load
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

-- saved settings -------------------------------------------------------------
local px, py = 12, 250          -- bottom-left corner in screen pixels
local scale, closed = 1.0, false
local MIN_SCALE, MAX_SCALE = 0.6, 2.2
-- base sizes (multiplied by scale) ---------------------------------------------
local ICON, GAP, PAD, TITLE, COLS = 54, 4, 6, 18, 5

local vsx, vsy = Spring.GetViewGeometry()
local drag, scaling = nil, nil
local builds, toggles, orders = {}, {}, {}
local rects, panelBox, hover, hoverRect, lastH, frame = {}, nil, nil, nil, 120, 0

local function Refresh()
	local cmds = Spring.GetActiveCmdDescs() or {}
	-- layout.lua flags every command as hidden to blank the engine's stock panel, so the engine's own
	-- "hidden" flag is useless here. The untouched list handed to LayoutButtons is kept in
	-- widgetHandler.commands: use that to find commands that are genuinely hidden.
	local realHidden = {}
	local orig = widgetHandler and widgetHandler.commands
	if type(orig) == "table" then
		for i = 1, (orig.n or #orig) do
			local oc = orig[i]
			if type(oc) == "table" and oc.hidden and oc.id then realHidden[oc.id] = true end
		end
	end
	builds, toggles, orders = {}, {}, {}
	for i = 1, #cmds do
		local c = cmds[i]
		if type(c) == "table" and c.id and not realHidden[c.id] then
			if c.id < 0 then builds[#builds + 1] = { c = c, i = i }
			elseif c.name and c.name ~= "" and c.id ~= CMD.OPT_SHIFT then
				if c.type == CMDTYPE.ICON_MODE and c.params and #c.params >= 2 then toggles[#toggles + 1] = { c = c, i = i }
				else orders[#orders + 1] = { c = c, i = i } end
			end
		end
	end
end

function widget:Initialize()
	Spring.Echo("[VB] Build panel loaded: drag title bar to move, corner handle to scale, X to close (/vbpanel reopens)")
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbpanel", function() closed = not closed return true end, nil, "t")
	end
	Refresh()
end
function widget:TextCommand(cmd) if cmd == "vbpanel" then closed = not closed return true end end

function widget:GetConfigData() return { px = px, py = py, scale = scale, closed = closed } end
function widget:SetConfigData(d)
	if d and d.px then px, py = d.px, d.py end
	if d and d.scale then scale = math.max(MIN_SCALE, math.min(MAX_SCALE, d.scale)) end
	if d and d.closed ~= nil then closed = d.closed end
end
function widget:ViewResize(w, h) vsx, vsy = w, h end
function widget:Update() frame = frame + 1; if frame % 6 == 0 then Refresh() end end

local function Inside(x, y, r) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
local function Clamp(w, h)
	px = math.max(0, math.min(vsx - w, px)); py = math.max(0, math.min(vsy - h, py))
end
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end

-- hexagonal unit stats HUD ------------------------------------------------------------------------------
local statCache = {}
local C_METAL, C_ENERGY, C_TIME = { 0.65, 0.8, 1.0 }, { 1.0, 0.9, 0.3 }, { 0.85, 0.85, 0.85 }
local C_HP, C_RANGE, C_DMG, C_MISC = { 0.4, 1.0, 0.5 }, { 0.4, 0.9, 1.0 }, { 1.0, 0.45, 0.35 }, { 0.8, 0.7, 1.0 }

local function Num(n)
	n = tonumber(n) or 0
	if n >= 10000 then return string.format("%.1fk", n / 1000) end
	if math.abs(n - math.floor(n + 0.5)) < 0.05 then return string.format("%d", math.floor(n + 0.5)) end
	return string.format("%.1f", n)
end

local function BuildStats(ud)
	local rows = {}
	local function Add(label, value, col) rows[#rows + 1] = { label, value, col } end
	Add("METAL", Num(ud.metalCost), C_METAL)
	Add("ENERGY", Num(ud.energyCost), C_ENERGY)
	Add("BUILD TIME", Num(ud.buildTime), C_TIME)
	Add("HEALTH", Num(ud.health), C_HP)
	if (ud.speed or 0) > 0 then Add("SPEED", Num(ud.speed), C_MISC) end
	if (ud.losRadius or 0) > 0 then Add("SIGHT", Num(ud.losRadius), C_RANGE) end
	if (ud.radarRadius or 0) > 0 then Add("RADAR", Num(ud.radarRadius), C_RANGE) end
	-- weapons: longest range, damage per volley and damage per second, summed over all weapons
	local maxRange, volley, dps, nW, reload = 0, 0, 0, 0, nil
	local arm = (Game and Game.armorTypes and Game.armorTypes.default) or 0
	for _, w in ipairs(ud.weapons or {}) do
		local wd = w.weaponDef and WeaponDefs[w.weaponDef]
		if wd then
			nW = nW + 1
			local d = wd.damages and (wd.damages[arm] or wd.damages[0] or wd.damages[1]) or 0
			local shots = (wd.projectiles or 1) * (wd.salvoSize or 1)
			local rl = math.max(wd.reload or 1, 0.03)
			maxRange = math.max(maxRange, wd.range or 0)
			volley = volley + d * shots
			dps = dps + d * shots / rl
			reload = reload and math.min(reload, rl) or rl
		end
	end
	if nW > 0 then
		Add("RANGE", Num(maxRange), C_RANGE)
		Add("DAMAGE", Num(volley), C_DMG)
		Add("DPS", Num(dps), C_DMG)
		Add("RELOAD", Num(reload) .. "s", C_TIME)
		if nW > 1 then Add("WEAPONS", tostring(nW), C_MISC) end
	end
	-- economy / support
	if (ud.metalMake or 0) > 0 then Add("METAL +/S", Num(ud.metalMake), C_METAL) end
	if (ud.extractsMetal or 0) > 0 then Add("EXTRACTS", Num(ud.extractsMetal * 1000), C_METAL) end
	if (ud.energyMake or 0) > 0 then Add("ENERGY +/S", Num(ud.energyMake), C_ENERGY) end
	if (ud.energyUpkeep or 0) > 0 then Add("UPKEEP", Num(ud.energyUpkeep), C_ENERGY) end
	if (ud.metalStorage or 0) > 0 then Add("M STORAGE", Num(ud.metalStorage), C_METAL) end
	if (ud.energyStorage or 0) > 0 then Add("E STORAGE", Num(ud.energyStorage), C_ENERGY) end
	if (ud.buildSpeed or 0) > 0 then Add("BUILD POWER", Num(ud.buildSpeed), C_MISC) end
	return rows
end

local function GetStats(defID)
	local st = statCache[defID]
	if st == nil then
		local ud = UnitDefs[defID]
		local ok, rows = pcall(BuildStats, ud)
		st = ok and rows or false
		if not ok then Spring.Echo("[VB] hex stats error: " .. tostring(rows)) end
		statCache[defID] = st
	end
	return st
end

-- hexagon (flat top/bottom, pointed left/right) as a convex polygon
local function HexVerts(x1, y1, x2, y2, k)
	local ym = (y1 + y2) / 2
	return { { v = { x1 + k, y2 } }, { v = { x2 - k, y2 } }, { v = { x2, ym } },
		{ v = { x2 - k, y1 } }, { v = { x1 + k, y1 } }, { v = { x1, ym } } }
end

local function DrawHexPanel(ud, icon)
	local rows = GetStats(ud.id)
	if not rows then return end
	local s = math.max(0.8, scale)
	local rowH, W = 15 * s, 250 * s
	local headH = 46 * s
	local H = headH + #rows * rowH + 22 * s
	local k = H * 0.17                                   -- how far the left/right points stick out
	-- beside the build panel, vertically centred on the hovered icon; flip to the left side if no room
	local cy = (icon[2] + icon[4]) / 2
	local hx1 = px + (panelBox and panelBox.w or 0) + 10
	if hx1 + W > vsx then hx1 = px - 10 - W end
	local hy1 = math.max(4, math.min(vsy - H - 4, cy - H / 2))
	local hx2, hy2 = hx1 + W, hy1 + H

	gl.Color(0.05, 0.05, 0.09, 0.93); gl.Shape(GL.TRIANGLE_FAN, HexVerts(hx1, hy1, hx2, hy2, k))
	gl.LineWidth(2); gl.Color(0.85, 0.65, 0.2, 0.95); gl.Shape(GL.LINE_LOOP, HexVerts(hx1, hy1, hx2, hy2, k))
	local i2 = 5 * s                                      -- thin inner hexagon
	gl.LineWidth(1); gl.Color(0.85, 0.65, 0.2, 0.35); gl.Shape(GL.LINE_LOOP, HexVerts(hx1 + i2, hy1 + i2, hx2 - i2, hy2 - i2, k - i2 * 0.3))
	gl.LineWidth(1)

	local cx = (hx1 + hx2) / 2
	local name = (ud.humanName or ud.name or "?")
	VBFont.Text(name, cx, hy2 - 22 * s, 15 * s, "oc", 1, 0.92, 0.65, 1)
	local desc = ud.tooltip or ""
	if #desc > 0 then
		if #desc > 34 then desc = desc:sub(1, 33) .. "." end
		VBFont.Text(desc, cx, hy2 - 38 * s, 9 * s, "oc", 0.7, 0.7, 0.8, 1)
	end
	gl.Color(0.85, 0.65, 0.2, 0.5); gl.Rect(hx1 + k + 6 * s, hy2 - headH + 3 * s, hx2 - k - 6 * s, hy2 - headH + 4 * s)

	local lx, rx = hx1 + k + 10 * s, hx2 - k - 10 * s
	local y = hy2 - headH - rowH + 3 * s
	for _, r in ipairs(rows) do
		VBFont.Text(r[1], lx, y, 11 * s, "o", 0.62, 0.62, 0.72, 1)
		VBFont.Text(r[2], rx, y, 12 * s, "or", r[3][1], r[3][2], r[3][3], 1)
		y = y - rowH
	end
end

local function DrawClosedTab()
	local s = 22
	local x1, y1 = px, math.max(0, math.min(vsy - s, py + lastH - s))
	rects = { { x1, y1, x1 + s, y1 + s, open = true } }
	panelBox = { w = s, h = s }
	Box(x1, y1, x1 + s, y1 + s, 0.06, 0.06, 0.09, 0.9); Frame(x1, y1, x1 + s, y1 + s, 0.85, 0.65, 0.2, 0.9)
	VBFont.Text("+", x1 + 7, y1 + 6, 14, "o", 1, 0.9, 0.5, 1)
end

function widget:DrawScreen()
	rects = {}
	if closed then
		if #builds + #toggles + #orders == 0 then panelBox = nil return end
		DrawClosedTab() return
	end
	if #builds + #toggles + #orders == 0 then panelBox = nil return end

	local s = scale
	local icon, gap, pad, title = ICON * s, GAP * s, PAD * s, math.max(16, TITLE * s)
	local fs = math.max(9, 10 * s)
	local gridW = COLS * (icon + gap) - gap
	local brows = math.ceil(#builds / COLS)
	local tcols, ocols = 2, 3
	local trows, orows = math.ceil(#toggles / tcols), math.ceil(#orders / ocols)
	local tbW, tbH = (gridW - (tcols - 1) * gap) / tcols, 20 * s
	local obW, obH = (gridW - (ocols - 1) * gap) / ocols, 18 * s
	local w = gridW + pad * 2
	local h = title + pad + brows * (icon + gap)
		+ (orows > 0 and (orows * (obH + gap) + 4 * s) or 0)
		+ (trows > 0 and (trows * (tbH + gap) + 4 * s) or 0) + pad + 8 * s
	if scaling then py = scaling.top - h end
	Clamp(w, h)
	panelBox, lastH = { w = w, h = h }, h
	local x1, y1, x2, y2 = px, py, px + w, py + h

	Box(x1, y1, x2, y2, 0.06, 0.06, 0.09, 0.88); Frame(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.9)
	-- title bar: drag handle + close button
	Box(x1, y2 - title, x2, y2, 0.14, 0.12, 0.2, 1)
	VBFont.Text("BUILD / ORDERS", x1 + pad, y2 - title + title * 0.28, fs, "o", 0.9, 0.85, 0.7, 1)
	rects[#rects + 1] = { x1, y2 - title, x2 - title, y2, drag = true }
	local mx, my = Spring.GetMouseState()
	local xr = { x2 - title, y2 - title, x2, y2, close = true }
	rects[#rects + 1] = xr
	Box(xr[1], xr[2], xr[3], xr[4], Inside(mx, my, xr) and 0.6 or 0.3, 0.1, 0.1, 1)
	VBFont.Text("x", xr[1] + title * 0.33, xr[2] + title * 0.25, fs + 2, "o", 1, 1, 1, 1)
	-- scale handle (bottom-right corner)
	local hs = 12 * s
	local hr = { x2 - hs, y1, x2, y1 + hs, scale = true }
	rects[#rects + 1] = hr
	gl.Color(0.85, 0.65, 0.2, Inside(mx, my, hr) and 1 or 0.7)
	for k = 1, 3 do gl.Rect(x2 - 2 - k * 3 * s, y1 + 2, x2 - 2, y1 + 2 + k * 3 * s - 2 * s) end

	local _, activeID = Spring.GetActiveCommand()
	hover, hoverRect = nil, nil
	local top = y2 - title - pad
	-- build icons
	for n, b in ipairs(builds) do
		local col, row = (n - 1) % COLS, math.floor((n - 1) / COLS)
		local ix, iy = x1 + pad + col * (icon + gap), top - (row + 1) * (icon + gap) + gap
		local r = { ix, iy, ix + icon, iy + icon, cmd = b }
		rects[#rects + 1] = r
		local over = Inside(mx, my, r); if over then hover, hoverRect = b, r end
		gl.Color(1, 1, 1, b.c.disabled and 0.35 or 1)
		gl.Texture("#" .. (-b.c.id)); gl.TexRect(ix, iy, ix + icon, iy + icon); gl.Texture(false)
		if b.c.id == activeID then Frame(ix, iy, ix + icon, iy + icon, 1, 0.9, 0.3, 1)
		elseif over then Frame(ix, iy, ix + icon, iy + icon, 1, 1, 1, 0.9)
		else Frame(ix, iy, ix + icon, iy + icon, 0.85, 0.65, 0.2, 0.8) end
		local cnt = b.c.params and b.c.params[1]
		if cnt and tonumber(cnt) and tonumber(cnt) > 0 then VBFont.Text(cnt, ix + icon - 4 * s, iy + 3 * s, 12 * s, "or", 1, 1, 1, 1) end
	end
	-- order buttons
	local oy = top - brows * (icon + gap) - 4 * s
	for n, o in ipairs(orders) do
		local col, row = (n - 1) % ocols, math.floor((n - 1) / ocols)
		local bx, by = x1 + pad + col * (obW + gap), oy - (row + 1) * (obH + gap) + gap
		local r = { bx, by, bx + obW, by + obH, cmd = o }
		rects[#rects + 1] = r
		local over = Inside(mx, my, r); if over then hover = o end
		if o.c.id == activeID then Box(bx, by, bx + obW, by + obH, 0.5, 0.4, 0.1, 1)
		elseif over then Box(bx, by, bx + obW, by + obH, 0.25, 0.25, 0.35, 1)
		else Box(bx, by, bx + obW, by + obH, 0.15, 0.15, 0.22, 1) end
		VBFont.Text(string.sub(o.c.name, 1, 13), bx + 4 * s, by + obH * 0.3, fs, "o", 1, 1, 1, o.c.disabled and 0.4 or 1)
	end
	-- toggle buttons (fire state, move state, repeat, on/off, land...) with state LEDs
	local ty = oy - (orows > 0 and (orows * (obH + gap)) or 0) - 4 * s
	for n, t in ipairs(toggles) do
		local col, row = (n - 1) % tcols, math.floor((n - 1) / tcols)
		local bx, by = x1 + pad + col * (tbW + gap), ty - (row + 1) * (tbH + gap) + gap
		local r = { bx, by, bx + tbW, by + tbH, cmd = t, toggle = true }
		rects[#rects + 1] = r
		local over = Inside(mx, my, r); if over then hover = t end
		Box(bx, by, bx + tbW, by + tbH, over and 0.25 or 0.15, over and 0.25 or 0.15, over and 0.35 or 0.22, 1)
		VBFont.Text(string.sub(t.c.name, 1, 14), bx + 4 * s, by + tbH * 0.42, fs, "o", 1, 1, 1, 1)
		local nstates, cur = #t.c.params - 1, tonumber(t.c.params[1]) or 0
		local lw = 7 * s
		for k = 0, nstates - 1 do
			local lx = bx + 4 * s + k * (lw + 2 * s)
			if k == cur then Box(lx, by + 2 * s, lx + lw, by + 5 * s, 0.1, 0.9, 0.2, 1)
			else Box(lx, by + 2 * s, lx + lw, by + 5 * s, 0.3, 0.3, 0.35, 1) end
		end
	end
	-- hover info: hexagonal stats HUD for build icons, one-line tooltip above the panel for orders/toggles
	if hover then
		local c = hover.c
		if c.id < 0 and UnitDefs[-c.id] and hoverRect then
			DrawHexPanel(UnitDefs[-c.id], hoverRect)
		else
			local line = c.tooltip ~= "" and c.tooltip or c.name
			if line then
				Box(x1, y2 + 2, x1 + math.max(w, VBFont.Width(line, 11) + 12), y2 + 20, 0.06, 0.06, 0.09, 0.9)
				VBFont.Text(line, x1 + 6, y2 + 7, 11, "o", 1, 1, 1, 1)
			end
		end
	end
end

function widget:IsAbove(x, y)
	return panelBox ~= nil and (closed and rects[1] and Inside(x, y, rects[1]) or
		(not closed and x >= px and x <= px + panelBox.w and y >= py and y <= py + panelBox.h)) or false
end

local function Activate(r, button)
	local c, i = r.cmd.c, r.cmd.i
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	if r.toggle then                                   -- cycle the option: left = next, right = previous
		local n, cur = #c.params - 1, tonumber(c.params[1]) or 0
		local nxt = (button == 3) and (cur - 1) % n or (cur + 1) % n
		Spring.GiveOrder(c.id, { nxt }, {})
	elseif c.type == CMDTYPE.ICON and c.id >= 0 then   -- instant orders: stop, wait, ...
		Spring.GiveOrder(c.id, {}, shift and { "shift" } or {})
	else
		-- Spring.SetActiveCommand takes the 1-BASED index into the same array GetActiveCmdDescs returns
		-- (the engine subtracts 1 itself; passing i-1 made every button trigger the one before it).
		-- Look the index up again by command id at click time, in case the list changed since Refresh().
		local idx = (Spring.GetCmdDescIndex and Spring.GetCmdDescIndex(c.id)) or i
		local ok, res = pcall(Spring.SetActiveCommand, idx, button, button == 1, button == 3, alt, ctrl, meta, shift)
		if (not ok or res == false) and c.id < 0 and UnitDefs[-c.id] then pcall(Spring.SetActiveCommand, "buildunit_" .. UnitDefs[-c.id].name) end
	end
end

function widget:MousePress(x, y, button)
	if not widget:IsAbove(x, y) then return false end
	for _, r in ipairs(rects) do
		if Inside(x, y, r) then
			if r.open then closed = false return true end
			if r.close then closed = true return true end
			if r.scale then scaling = { x0 = x, y0 = y, s0 = scale, top = py + (panelBox and panelBox.h or 0) } return true end
			if r.drag then drag = { x - px, y - py } return true end
			if r.cmd then Activate(r, button) return true end
		end
	end
	return true  -- swallow clicks on empty panel area
end

function widget:MouseMove(x, y)
	if drag then px, py = x - drag[1], y - drag[2]
	elseif scaling then
		scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scaling.s0 + ((x - scaling.x0) - (y - scaling.y0)) / 350))
	end
end
function widget:MouseRelease() drag, scaling = nil, nil end
