function widget:GetInfo()
	return { name = "Voidborn Queue Monitor", desc = "One panel for all production: every factory with its current unit and queue, every builder busy or idle, what the queues will cost against your stock, build power in use. Alt+Q or /vbqueue shows and hides it",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true }
end

-- WHAT IT SHOWS (your own team)
--   Header     metal and energy the queues still need, against stock and income (red = you cannot pay it yet),
--              M / E stall flags, and BUILD POWER: the part that is working / all of it.
--   Factories  one row each: icon, what it builds now with a progress bar, or IDLE (flashing), and chips for the queue.
--              A chip is a unit type with its count; its frame shows the state: green building, red stalled for
--              resources, blue waiting, yellow on hold, cyan factory still under construction.
--   Builders   mobile constructors and commanders: busy with the number of orders and progress of what they build, or IDLE.
--   Forge      queued forge designs that have no factory of their own.
--
-- CLICKS
--   a row         left: select (shift adds)   right: select and jump the camera there
--   a chip        left: queue one more (shift: five)   right: take one out (shift: five, ctrl: the whole entry)
--                 middle: hold / release.  These are the same messages the build panel sends to the queue gadget
--                 (LuaRules/Gadgets/vb_dev_queue.lua); stock engine queues are handled with ordinary build orders.
--   EMBEDDED      Next to the build menu the panel is a one-line bar right under the unit census (same left edge and
--                 width): "> PRODUCTION  3 busy  1 IDLE".  Click it and the full panel opens to the RIGHT of the build
--                 menu (bottom edges level); click its title bar to fold it back under the census.  The idle count flashes
--                 while it is folded, so an idle factory is never hidden.  The boxes are found through
--                 WG.VBQueueMon.SetAnchor(fn)      the census:      fn returns x1, y1, x2, y2
--                 WG.VBQueueMon.SetMenuAnchor(fn)  the build menu:  same (see the name lists below).
--                 /vbqueue expand | collapse | embed on|off.  Without any box the panel is the free-floating one below.
--   title bar     drag to move (free-floating mode).  Until it is moved the panel docks next to the default layout column (vb_layout.lua).
--                 /vbqueue dock   docks it again,   /vbqueue scale 0.6..2   changes the size.
--   x             close (Alt+Q or /vbqueue brings it back)

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
local okV, V = pcall(VFS.Include, "LuaUI/Headers/vb_values.h.lua")
if not okV or type(V) ~= "table" then V = { Num = function(v) return tostring(math.floor((v or 0) + 0.5)) end } end

local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local vsx, vsy = Spring.GetViewGeometry()
local closed, docked, scale = false, true, 1.0
local embed, expanded = true, false      -- docked under the census: on / off, and expanded or a one-line bar
local anchorFn                          -- set by the census or build menu widget: function() return x1, y1, x2, y2 end
local embActive = false                 -- true while the last frame was drawn embedded
local px, py = 460, 10                  -- bottom-left corner when the panel has been moved
local clock = 0

local MC, EC = { 0.55, 0.85, 1.00 }, { 1.00, 0.80, 0.30 }
local ST_COL = { b = { 0.3, 1.0, 0.45 }, s = { 1.0, 0.4, 0.25 }, w = { 0.5, 0.65, 1.0 }, h = { 1.0, 0.85, 0.2 }, p = { 0.3, 0.85, 1.0 } }
local ST_TXT = { b = "building", s = "stalled: not enough resources", w = "waiting in the queue", h = "on hold", p = "waiting for the factory to be finished" }

-- Where the census and the build menu are.  A widget hands its box over with WG.VBQueueMon.SetAnchor(fn) (census) and
-- SetMenuAnchor(fn) (build menu), fn = function() return x1, y1, x2, y2 end; otherwise a WG table with a Box() function is used.
local CENSUS_NAMES = { "VBCensus", "VBStats", "VBUnitCensus" }
local MENU_NAMES   = { "VBBuildMenu", "VBBuildPanel" }
local menuFn
local function FindBox(own, names)
	local fns = {}
	if own then fns[1] = own end
	for _, n in ipairs(names) do
		local a = WG[n]
		if type(a) == "table" and type(a.Box) == "function" then fns[#fns + 1] = a.Box end
	end
	for _, fn in ipairs(fns) do
		local ok, x1, y1, x2, y2 = pcall(fn)
		if ok and x1 and y1 and x2 and y2 and x2 > x1 then return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end
	end
end
local function Anchor()                        -- the bar hangs under the census (or, without one, under the build menu)
	if not embed then return nil end
	return FindBox(anchorFn, CENSUS_NAMES) or FindBox(menuFn, MENU_NAMES)
end
local function MenuBox(emb)                    -- the expanded panel opens to the right of this
	return FindBox(menuFn, MENU_NAMES) or emb
end

local function Sc() return max(0.75, min(1.6, vsy / 1080)) * scale end

-- the same id rule as the build panel, so that "d_name@factory" keys of the queue gadget can be read back
local function PlainId(name) return ((("d_" .. name):gsub("[^%w_%-]", "_")):sub(1, 24)) end
local plainToDef = {}
for id, ud in pairs(UnitDefs) do if type(id) == "number" then plainToDef[PlainId(ud.name)] = id end end

local function IsFac(ud) return ud.isFactory or (not ud.canMove and ud.buildOptions and #ud.buildOptions > 0) end
local function Cnt(c) if type(c) == "table" then return #c end return c or 0 end

--------------------------------------------------------------------------------
-- data, refreshed four times a second
--------------------------------------------------------------------------------
local facs, cons, forge = {}, {}, {}
local info = { needM = 0, needE = 0, bpAll = 0, bpBusy = 0, nBusy = 0, nIdle = 0, stallM = false, stallE = false }

local function ReadGadget()
	local F = WG.VBForge
	if not (F and F.IsForgeReady and F.IsForgeReady() and F.ReadQueue) then return {}, {}, nil end
	local ok, q, order = pcall(F.ReadQueue)
	if not ok or type(q) ~= "table" or type(order) ~= "table" then return {}, {}, nil end
	return q, order, F
end

local function Gather()
	local team = Spring.GetMyTeamID()
	local fl, cl = {}, {}
	local I = { needM = 0, needE = 0, bpAll = 0, bpBusy = 0, nBusy = 0, nIdle = 0 }
	local gq, gorder, F = ReadGadget()

	-- the queue gadget's entries, by factory
	local byFac, loose = {}, {}
	for _, key in ipairs(gorder) do
		local q = gq[key]
		if type(q) == "table" then
			local base, fac = nil, nil
			if type(key) == "string" then base, fac = key:match("^(.-)@(%d+)$") end
			local c = { n = q.n or 1, st = q.st or "w", prog = q.prog or 0, gkey = key }
			if base then
				c.def, c.fac, c.id = plainToDef[base], tonumber(fac), base
				c.name = c.def and UnitDefs[c.def].name or base
				local list = byFac[c.fac]
				if not list then list = {}; byFac[c.fac] = list end
				list[#list + 1] = c
			else
				local t = F and F.templates and F.templates[key]
				local bd = t and t.base and UnitDefNames[t.base]
				c.def, c.tpl, c.name = bd and bd.id, key, (t and (t.id or key)) or tostring(key)
				loose[#loose + 1] = c
			end
			if c.def then
				local ud = UnitDefs[c.def]
				I.needM, I.needE = I.needM + c.n * (ud.metalCost or 0), I.needE + c.n * (ud.energyCost or 0)
			end
		end
	end

	for _, uid in ipairs(Spring.GetTeamUnits(team) or {}) do
		local defID = Spring.GetUnitDefID(uid)
		local ud = defID and UnitDefs[defID]
		if ud and not Spring.GetUnitIsBeingBuilt(uid) then
			local bs = ud.buildSpeed or 0
			local target = (bs > 0) and Spring.GetUnitIsBuilding(uid) or nil
			if bs > 0 then
				I.bpAll = I.bpAll + bs
				if target then I.bpBusy = I.bpBusy + bs end
			end
			local prog
			if target then
				local _, _, _, _, bp = Spring.GetUnitHealth(target)
				prog = bp
			end
			if IsFac(ud) and ud.buildOptions and #ud.buildOptions > 0 then
				local f = { uid = uid, def = defID, target = target, prog = prog, chips = {} }
				-- stock engine queue
				local ok, cmds = pcall(Spring.GetFactoryCommands, uid, -1)
				if ok and type(cmds) == "table" then
					local last
					for _, cmd in ipairs(cmds) do
						local id = cmd.id and -cmd.id
						if id and id > 0 and UnitDefs[id] then
							if last and last.def == id then last.n = last.n + 1
							else last = { def = id, n = 1, st = "w", prog = 0, eng = true, fac = uid, name = UnitDefs[id].name }; f.chips[#f.chips + 1] = last end
							I.needM, I.needE = I.needM + (UnitDefs[id].metalCost or 0), I.needE + (UnitDefs[id].energyCost or 0)
						end
					end
					if f.chips[1] and target then f.chips[1].st, f.chips[1].prog = "b", prog or 0 end
				end
				for _, c in ipairs(byFac[uid] or {}) do f.chips[#f.chips + 1] = c end
				f.busy = (target ~= nil) or #f.chips > 0
				if f.busy then I.nBusy = I.nBusy + 1 else I.nIdle = I.nIdle + 1 end
				fl[#fl + 1] = f
			elseif ud.canMove and bs > 0 and ud.buildOptions and #ud.buildOptions > 0 then
				local n = Cnt(Spring.GetUnitCommands(uid, 0))
				local c = { uid = uid, def = defID, target = target, prog = prog, orders = n, busy = (target ~= nil) or n > 0 }
				if c.busy then I.nBusy = I.nBusy + 1 else I.nIdle = I.nIdle + 1 end
				cl[#cl + 1] = c
			end
		end
	end
	table.sort(fl, function(a, b) return a.uid < b.uid end)
	table.sort(cl, function(a, b)
		if a.busy ~= b.busy then return not a.busy end       -- idle ones first: they are the ones that need you
		if a.def ~= b.def then return a.def < b.def end
		return a.uid < b.uid
	end)

	-- stall flags: stock almost empty and more asked than earned
	for _, res in ipairs({ "metal", "energy" }) do
		local cur, sto, pull, inc = Spring.GetTeamResources(team, res)
		local stall = cur and sto and sto > 0 and cur < 0.03 * sto and (pull or 0) > (inc or 0) * 1.02
		if res == "metal" then I.stallM, I.curM, I.incM = stall, cur or 0, inc or 0 else I.stallE, I.curE, I.incE = stall, cur or 0, inc or 0 end
	end
	facs, cons, forge, info = fl, cl, loose, I
end

--------------------------------------------------------------------------------
-- drawing helpers
--------------------------------------------------------------------------------
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a, w)
	w = w or 1
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + w); gl.Rect(x1, y2 - w, x2, y2); gl.Rect(x1, y1, x1 + w, y2); gl.Rect(x2 - w, y1, x2, y2)
end
local function Trunc(str, size, w)
	while #str > 3 and VBFont.Width(str, size) > w do str = str:sub(1, -2) end
	return str
end
local function Inside(x, y, r) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
local function Icon(def, x1, y1, x2, y2, a)
	if not def then Box(x1, y1, x2, y2, 0.2, 0.2, 0.28, 1) return end
	gl.Color(1, 1, 1, a or 1); gl.Texture("#" .. def); gl.TexRect(x1, y1, x2, y2); gl.Texture(false)
end

--------------------------------------------------------------------------------
-- drawing the panel
--------------------------------------------------------------------------------
local rects, panel = {}, nil
local drag

local function PanelOrigin(s)
	if docked then
		local right = WG.VBLayout and WG.VBLayout.Right and WG.VBLayout.Right()
		if right then return right + 6 * s, 8 * s end
		return px, py
	end
	return px, py
end

function widget:DrawScreen()
	rects, panel = {}, nil
	if closed then return end
	if #facs == 0 and #cons == 0 and #forge == 0 then return end
	local s = Sc()
	local mx, my = Spring.GetMouseState()
	local emb = Anchor()
	embActive = emb ~= nil
	local full = (not emb) or expanded
	local W = 330 * s
	if emb and not expanded then W = max(260 * s, emb.x2 - emb.x1) end
	local pad, gap = 6 * s, 3 * s
	local title, head, sec = 18 * s, 30 * s, 14 * s
	local chipS = 26 * s
	local rowF, rowC = chipS + 6 * s, 20 * s
	local maxCons = 8
	local nCons = min(#cons, maxCons)
	local H = title + head + pad
	if not full then H = title end
	if full and #facs > 0 then H = H + sec + #facs * (rowF + gap) end
	if full and #forge > 0 then H = H + sec + (rowF + gap) end
	if full and nCons > 0 then H = H + sec + nCons * (rowC + gap) + (#cons > maxCons and 14 * s or 0) end
	if full then H = H + pad end

	local ox, oy = PanelOrigin(s)
	if emb then
		if expanded then
			local mb = MenuBox(emb)                                  -- open to the right of the build menu, bottoms level
			ox, oy = mb.x2 + 6 * s, mb.y1
		else
			ox, oy = emb.x1, emb.y1 - 2 * s - H                      -- the folded bar hangs right under the census
		end
	end
	ox = max(0, min(vsx - W, ox)); oy = max(0, min(vsy - H, oy))
	local x1, y1, x2, y2 = ox, oy, ox + W, oy + H
	panel = { x1, y1, x2, y2 }
	Box(x1, y1, x2, y2, 0.06, 0.06, 0.09, 0.86); Frame(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.9)

	-- title bar
	local tr = { x1, y2 - title, x2, y2, kind = "title" }
	rects[#rects + 1] = tr
	Box(tr[1], tr[2], tr[3], tr[4], 0.14, 0.12, 0.2, 1)
	local label = (emb and (expanded and "< " or "> ") or "") .. "PRODUCTION"
	VBFont.Text(label, x1 + pad, y2 - title + 4 * s, 11 * s, "o", 1, 0.9, 0.5, 1)
	if not full then
		-- the collapsed bar: busy / idle at a glance, the idle count flashes
		local sx = x1 + pad + VBFont.Width(label, 11 * s) + 10 * s
		local nIdle = info.nIdle or 0
		local t1 = string.format("%d busy", info.nBusy or 0)
		VBFont.Text(t1, sx, y2 - title + 4 * s, 10 * s, "o", 0.5, 0.95, 0.6, 1)
		sx = sx + VBFont.Width(t1, 10 * s) + 8 * s
		if nIdle > 0 then
			local t2 = nIdle .. " IDLE"
			VBFont.Text(t2, sx, y2 - title + 4 * s, 10 * s, "o", 1, 0.8, 0.25, 0.55 + 0.45 * sin(clock * 5)); sx = sx + VBFont.Width(t2, 10 * s) + 8 * s
		end
		if info.stallM or info.stallE then
			VBFont.Text((info.stallM and "M " or "") .. (info.stallE and "E " or "") .. "STALL", sx, y2 - title + 4 * s, 10 * s, "o", 1, 0.35, 0.3, 0.6 + 0.4 * sin(clock * 6))
		end
	end
	local xr = { x2 - title, y2 - title, x2, y2, kind = "close" }
	rects[#rects + 1] = xr
	local overX = Inside(mx, my, xr)
	Box(xr[1] + 2, xr[2] + 2, xr[3] - 2, xr[4] - 2, overX and 0.6 or 0.3, 0.1, 0.1, 1)
	VBFont.Text("x", xr[1] + title * 0.32, xr[2] + 4 * s, 11 * s, "o", 1, 1, 1, 1)
	if not full then gl.Color(1, 1, 1, 1) return end

	-- header: what the queues need, stall flags, build power
	local hy = y2 - title - 13 * s
	local needM, needE = info.needM, info.needE
	local okM = (info.curM or 0) >= needM
	local okE = (info.curE or 0) >= needE
	local ltxt = "QUEUED  "
	VBFont.Text(ltxt, x1 + pad, hy, 10 * s, "o", 0.65, 0.7, 0.8, 1)
	local lx = x1 + pad + VBFont.Width(ltxt, 10 * s)
	local mt = V.Num(needM) .. " M"
	VBFont.Text(mt, lx, hy, 10 * s, "o", okM and MC[1] or 1, okM and MC[2] or 0.45, okM and MC[3] or 0.4, 1)
	lx = lx + VBFont.Width(mt, 10 * s) + 8 * s
	local et = V.Num(needE) .. " E"
	VBFont.Text(et, lx, hy, 10 * s, "o", okE and EC[1] or 1, okE and EC[2] or 0.45, okE and EC[3] or 0.4, 1)
	lx = lx + VBFont.Width(et, 10 * s) + 8 * s
	local flash = 0.6 + 0.4 * sin(clock * 6)
	if info.stallM then VBFont.Text("M STALL", lx, hy, 10 * s, "o", 1, 0.35, 0.3, flash); lx = lx + VBFont.Width("M STALL", 10 * s) + 6 * s end
	if info.stallE then VBFont.Text("E STALL", lx, hy, 10 * s, "o", 1, 0.35, 0.3, flash) end
	local hy2 = hy - 13 * s
	local bpTxt = string.format("BUILD POWER  %s / %s", V.Num(info.bpBusy), V.Num(info.bpAll))
	local idleBP = info.bpAll - info.bpBusy
	VBFont.Text(bpTxt, x1 + pad, hy2, 10 * s, "o", 0.65, 0.7, 0.8, 1)
	local bw = VBFont.Width(bpTxt, 10 * s)
	if info.bpAll > 0 then
		local bx1, bx2 = x1 + pad + bw + 8 * s, x2 - pad
		if bx2 - bx1 > 20 * s then
			Box(bx1, hy2 + 1 * s, bx2, hy2 + 9 * s, 0.12, 0.12, 0.16, 1)
			local f = info.bpBusy / info.bpAll
			Box(bx1, hy2 + 1 * s, bx1 + (bx2 - bx1) * f, hy2 + 9 * s, 0.3 + 0.5 * (1 - f), 0.85 * f + 0.2, 0.4, 1)
			Frame(bx1, hy2 + 1 * s, bx2, hy2 + 9 * s, 0.5, 0.5, 0.6, 0.8)
		end
	end

	local y = y2 - title - head
	local hoverTxt
	local function SectionLabel(txt)
		y = y - sec
		VBFont.Text(txt, x1 + pad, y + 3 * s, 9 * s, "o", 0.55, 0.6, 0.72, 1)
	end

	local function DrawChips(chips, cx1, cx2, cy1)
		local fit = max(1, floor((cx2 - cx1 + gap) / (chipS + gap)))
		local shown = min(#chips, fit)
		if #chips > fit then shown = fit - 1 end
		for i = 1, shown do
			local c = chips[i]
			local ix = cx1 + (i - 1) * (chipS + gap)
			local r = { ix, cy1, ix + chipS, cy1 + chipS, kind = "chip", chip = c }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r)
			Icon(c.def, ix, cy1, ix + chipS, cy1 + chipS, c.st == "h" and 0.45 or 1)
			local col = ST_COL[c.st] or ST_COL.w
			Frame(ix, cy1, ix + chipS, cy1 + chipS, col[1], col[2], col[3], over and 1 or 0.9, 2)
			if c.prog and c.prog > 0.004 and (c.st == "b" or c.st == "s") then
				Box(ix + 2, cy1 + 2, ix + 2 + (chipS - 4) * min(1, c.prog), cy1 + 5 * s, col[1], col[2], col[3], 0.95)
			end
			if c.n > 1 then VBFont.Text("x" .. c.n, ix + chipS - 3 * s, cy1 + 8 * s, 10 * s, "or", 1, 1, 1, 1) end
			if c.st == "s" then VBFont.Text("!", ix + 3 * s, cy1 + chipS - 13 * s, 12 * s, "o", 1, 0.3, 0.2, 1) end
			if over then hoverTxt = string.format("%s  x%d - %s%s", c.name or "?", c.n, ST_TXT[c.st] or "queued",
				(c.eng and "  (L: +1  R: -1)") or "  (L: +1  R: -1  M: hold)") end
		end
		if #chips > shown then
			VBFont.Text("+" .. (#chips - shown), cx1 + shown * (chipS + gap) + 2 * s, cy1 + 8 * s, 11 * s, "o", 0.8, 0.85, 1, 1)
		end
	end

	-- factories
	if #facs > 0 then
		SectionLabel("FACTORIES")
		for _, f in ipairs(facs) do
			y = y - rowF - gap
			local ry1 = y
			local r = { x1 + pad, ry1, x2 - pad, ry1 + rowF, kind = "unit", uid = f.uid }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r) and not (hoverTxt)
			Box(r[1], r[2], r[3], r[4], over and 0.14 or 0.09, over and 0.15 or 0.1, over and 0.2 or 0.14, 1)
			local isel = chipS
			Icon(f.def, r[1] + 3 * s, ry1 + 3 * s, r[1] + 3 * s + isel, ry1 + 3 * s + isel)
			local tx = r[1] + 3 * s + isel + 5 * s
			local nameW = 78 * s
			local nm = Trunc(UnitDefs[f.def].humanName or UnitDefs[f.def].name, 10 * s, nameW)
			VBFont.Text(nm, tx, ry1 + rowF - 14 * s, 10 * s, "o", 0.92, 0.94, 1, 1)
			if f.target then
				local tdef = Spring.GetUnitDefID(f.target)
				local label = tdef and UnitDefs[tdef] and (UnitDefs[tdef].humanName or UnitDefs[tdef].name) or "building"
				VBFont.Text(Trunc(label, 9 * s, nameW), tx, ry1 + 9 * s, 9 * s, "o", 0.5, 0.95, 0.6, 1)
				Box(tx, ry1 + 3 * s, tx + nameW, ry1 + 6 * s, 0.12, 0.12, 0.16, 1)
				Box(tx, ry1 + 3 * s, tx + nameW * min(1, f.prog or 0), ry1 + 6 * s, 0.3, 1, 0.45, 1)
			elseif #f.chips == 0 then
				VBFont.Text("IDLE", tx, ry1 + 7 * s, 10 * s, "o", 1, 0.8, 0.25, 0.55 + 0.45 * sin(clock * 5))
			else
				VBFont.Text("queued", tx, ry1 + 7 * s, 9 * s, "o", 0.5, 0.65, 1, 1)
			end
			DrawChips(f.chips, tx + nameW + 6 * s, r[3] - 3 * s, ry1 + 3 * s)
		end
	end

	-- forge designs without a factory
	if #forge > 0 then
		SectionLabel("FORGE")
		y = y - rowF - gap
		DrawChips(forge, x1 + pad, x2 - pad, y + 3 * s)
	end

	-- builders
	if nCons > 0 then
		SectionLabel(string.format("BUILDERS   %d idle", (function() local n = 0 for _, c in ipairs(cons) do if not c.busy then n = n + 1 end end return n end)()))
		for i = 1, nCons do
			local c = cons[i]
			y = y - rowC - gap
			local r = { x1 + pad, y, x2 - pad, y + rowC, kind = "unit", uid = c.uid }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r) and not hoverTxt
			Box(r[1], r[2], r[3], r[4], over and 0.14 or 0.09, over and 0.15 or 0.1, over and 0.2 or 0.14, 1)
			Icon(c.def, r[1] + 2 * s, y + 2 * s, r[1] + 2 * s + rowC - 4 * s, y + rowC - 2 * s)
			local tx = r[1] + rowC + 4 * s
			VBFont.Text(Trunc(UnitDefs[c.def].humanName or UnitDefs[c.def].name, 10 * s, 96 * s), tx, y + 6 * s, 10 * s, "o", 0.92, 0.94, 1, 1)
			local sx = tx + 100 * s
			if c.target then
				local tdef = Spring.GetUnitDefID(c.target)
				local label = tdef and UnitDefs[tdef] and (UnitDefs[tdef].humanName or UnitDefs[tdef].name) or "building"
				local extra = c.orders > 1 and ("  +" .. (c.orders - 1)) or ""
				VBFont.Text(Trunc(label, 9 * s, r[3] - sx - 60 * s) .. extra, sx, y + 6 * s, 9 * s, "o", 0.5, 0.95, 0.6, 1)
				local bx2 = r[3] - 4 * s
				Box(bx2 - 50 * s, y + 7 * s, bx2, y + 11 * s, 0.12, 0.12, 0.16, 1)
				Box(bx2 - 50 * s, y + 7 * s, bx2 - 50 * s + 50 * s * min(1, c.prog or 0), y + 11 * s, 0.3, 1, 0.45, 1)
			elseif c.orders > 0 then
				VBFont.Text(c.orders .. " orders", sx, y + 6 * s, 9 * s, "o", 0.6, 0.75, 1, 1)
			else
				VBFont.Text("IDLE", sx, y + 6 * s, 10 * s, "o", 1, 0.8, 0.25, 0.55 + 0.45 * sin(clock * 5))
			end
		end
		if #cons > maxCons then
			y = y - 14 * s
			VBFont.Text("+" .. (#cons - maxCons) .. " more", x1 + pad, y + 3 * s, 9 * s, "o", 0.6, 0.65, 0.8, 1)
		end
	end

	-- tooltip of the chip under the mouse
	if hoverTxt then
		local size = 10 * s
		local tw = VBFont.Width(hoverTxt, size) + 12 * s
		local tx, ty = min(mx + 14, vsx - tw - 4), my + 16
		Box(tx, ty, tx + tw, ty + 16 * s, 0.05, 0.05, 0.09, 0.95); Frame(tx, ty, tx + tw, ty + 16 * s, 0.85, 0.65, 0.2, 0.8)
		VBFont.Text(hoverTxt, tx + 6 * s, ty + 4 * s, size, "o", 1, 1, 1, 1)
	end
	gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- mouse
--------------------------------------------------------------------------------
local function ChipClick(c, button)
	local _, ctrl, _, shift = Spring.GetModKeyState()
	local n = shift and 5 or 1
	if c.gkey and c.fac then
		local ref = c.gkey
		if button == 1 then
			Spring.SendLuaRulesMsg(string.format('vbq:add:%d:{["base"]=%q,["fac"]=%d,["id"]=%q,["plain"]=1}', n, c.name, c.fac, c.id))
		elseif button == 2 then Spring.SendLuaRulesMsg("vbq:hold:1:" .. ref)
		elseif button == 3 then
			if ctrl then Spring.SendLuaRulesMsg("vbq:clear:1:" .. ref) else Spring.SendLuaRulesMsg("vbq:rem:" .. n .. ":" .. ref) end
		end
	elseif c.tpl then
		local F = WG.VBForge
		if not F then return end
		if button == 1 and F.QueueAdd then F.QueueAdd(c.tpl, n)
		elseif button == 2 and F.QueueHold then F.QueueHold(c.tpl)
		elseif button == 3 and F.QueueRemove then F.QueueRemove(c.tpl, n) end
	elseif c.eng and c.def then
		if button == 1 then for _ = 1, n do Spring.GiveOrderToUnit(c.fac, -c.def, {}, {}) end
		elseif button == 3 then for _ = 1, n do Spring.GiveOrderToUnit(c.fac, -c.def, {}, { "right" }) end end
	end
end

function widget:IsAbove(x, y) return panel ~= nil and not closed and Inside(x, y, panel) end

function widget:MousePress(x, y, button)
	if closed or not panel or not Inside(x, y, panel) then return false end
	for i = #rects, 1, -1 do
		local r = rects[i]
		if Inside(x, y, r) then
			if r.kind == "close" then closed = true; return true
			elseif r.kind == "title" then
				if button == 1 then
					if embActive then expanded = not expanded       -- docked under the census: the bar expands / collapses
					else drag = { dx = x - panel[1], dy = y - panel[2] } end
				end
				return true
			elseif r.kind == "chip" then ChipClick(r.chip, button); return true
			elseif r.kind == "unit" then
				local _, _, _, shift = Spring.GetModKeyState()
				if button == 1 then
					if shift then
						local sel = Spring.GetSelectedUnits() or {}
						sel[#sel + 1] = r.uid
						Spring.SelectUnitArray(sel)
					else Spring.SelectUnitArray({ r.uid }) end
				elseif button == 3 then
					Spring.SelectUnitArray({ r.uid })
					local ux, uy, uz = Spring.GetUnitPosition(r.uid)
					if ux then Spring.SetCameraTarget(ux, uy, uz, 0.6) end
				end
				return true
			end
		end
	end
	return true
end

function widget:MouseMove(x, y)
	if not drag or not panel then return end
	docked = false
	px, py = x - drag.dx, y - drag.dy
end

function widget:MouseRelease() drag = nil end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
local acc = 0
function widget:Update(dt)
	clock = clock + dt
	acc = acc + dt
	if acc >= 0.25 then acc = 0; if not closed then Gather() end end
end

function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:TextCommand(cmd)
	local word, rest = cmd:match("^(%S+)%s*(.*)$")
	if word ~= "vbqueue" then return false end
	rest = rest or ""
	if rest == "" then closed = not closed; if not closed then Gather() end
	elseif rest == "expand" then expanded, closed = true, false
	elseif rest == "collapse" then expanded = false
	elseif rest:match("^embed") then
		local v = rest:match("embed%s+(%S+)")
		if v == "on" then embed = true elseif v == "off" then embed = false else embed = not embed end
		Spring.Echo("[VB] queue monitor: under the census " .. (embed and "on" or "off"))
	elseif rest == "dock" then docked, closed = true, false
	elseif rest:match("^scale") then scale = max(0.6, min(2.0, tonumber(rest:match("scale%s+(%S+)")) or 1)); Spring.Echo("[VB] queue monitor scale " .. scale)
	elseif rest == "on" then closed = false elseif rest == "off" then closed = true end
	return true
end

function widget:Initialize()
	WG.VBQueueMon = {
		Toggle = function() closed = not closed; if not closed then Gather() end end,
		IsOpen = function() return not closed end,
		SetAnchor = function(fn) anchorFn = fn end,
		SetMenuAnchor = function(fn) menuFn = fn end,                         -- census / build menu: function() return x1, y1, x2, y2 end
		Expand = function() expanded, closed = true, false end,
		Collapse = function() expanded = false end,
		ToggleExpanded = function() expanded = not expanded; closed = false end,
		IsExpanded = function() return expanded end,
		Box = function() if panel then return panel[1], panel[2], panel[3], panel[4] end end,
	}
	Spring.Echo("[VB] queue monitor ready: Alt+Q or /vbqueue shows / hides it; under the census click the bar to expand; /vbqueue embed off for the free-floating panel (drag the title bar, /vbqueue dock)")
end
function widget:Shutdown() WG.VBQueueMon = nil; anchorFn, menuFn = nil, nil end

function widget:GetConfigData() return { closed = closed, docked = docked, px = px, py = py, scale = scale, embed = embed, expanded = expanded } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.docked == false then docked = false end
	if d.px then px, py = d.px, d.py end
	if d.scale then scale = max(0.6, min(2.0, d.scale)) end
	if d.embed ~= nil then embed = d.embed and true or false end
	if d.expanded ~= nil then expanded = d.expanded and true or false end
	closed = d.closed and true or false
end
