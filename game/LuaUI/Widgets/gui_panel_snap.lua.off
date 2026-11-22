function widget:GetInfo()
	return {
		name    = "Panel Snap Layout",
		desc    = "Docks panels into left/right/top/bottom columns; drag a panel near an edge to snap it there. /panelsnap help",
		author  = "goddot",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = -1000,
		enabled = false,
	}
end

--------------------------------------------------------------------------------
-- HOW IT WORKS
--  * Panels register themselves:  WG.PanelLayout.Register("name", { ... })   (see below)
--  * Every panel sits in one dock: left | right | top | bottom. The docks are stacked columns / rows.
--  * DRAG A PANEL (with its own title bar) and let go: it snaps to the nearest dock and is slotted in
--    at the place where you dropped it. Drop it in the middle of the screen to float it (unmanaged);
--    /panelsnap dock <name> <side> brings it back.
--  * Panels that are closed or hidden (isVisible() == false) take no space.
--  * Panels that can resize (setRect honours w,h) are stretched to fill their dock; panels with a fixed
--    size (fixedSize = true) are only moved and stacked with their own size.
--
-- REGISTER:
--   WG.PanelLayout.Register("mywidget", {
--       getRect = function() return x, y, w, h end,   -- pixels, origin bottom-left (REQUIRED for drop-snapping)
--       setRect = function(x, y, w, h) end,           -- REQUIRED
--       isVisible = function() return true end,       -- optional: false = takes no space
--       fixedSize = false,   -- true: never resized, only moved
--       dock = "right",      -- default dock
--       minW, minH, maxW, maxH, aspect, weight, order
--   })
--   WG.PanelLayout.Unregister("mywidget")   -- from the widget's Shutdown
-- Auto-discovery: a WG table with GetRect() and SetRect(x,y,w,h) (and optional .PanelLayout = {...}).
--
-- HOSTING (no changes needed in the other widget):
--   Any loaded widget can be docked without registering. Its panel is found by probing the widget's own
--   IsAbove(x,y) (or GetTooltip) hit test, and moved by drawing it with an offset (gl.Translate in its
--   DrawScreen) while its mouse callins get the shifted coordinates. A hosted widget moves as ONE panel.
--     /panelsnap adopt <widget name>     host a widget (word match on its name, e.g. "pip")  /panelsnap unadopt
--     /panelsnap widgets                 list loaded widgets and which are hosted
--     /panelsnap rect <key> x y w h      give the panel rectangle by hand if the widget has no hit test
--   Default: the Voidborn HUD resource panels and Picture-in-Picture are hosted.
--   ALT + drag moves any panel (hosted or registered), even one without a title bar; drop it near an edge.
--------------------------------------------------------------------------------

local spGetMouseState = Spring.GetMouseState
local spGetModKeyState = Spring.GetModKeyState
local glPushMatrix, glPopMatrix, glTranslate = gl.PushMatrix, gl.PopMatrix, gl.Translate
local spEcho = Spring.Echo
local glColor, glRect, glText = gl.Color, gl.Rect, gl.Text
local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt

local vsx, vsy = Spring.GetViewGeometry()
local DOCKS = { "left", "right", "top", "bottom" }
local DOCK_OK = { left = true, right = true, top = true, bottom = true }

local cfg = {
	enabled  = true,
	snapOnDrop = true,
	margin   = 8,
	gap      = 6,
	frac     = { left = 0.17, right = 0.19, top = 0.09, bottom = 0.15 },  -- share of the screen (for resizable panels)
	override = {},  -- [name] = { dock=, weight=, enabled=, order=, floating= }
	rowAlign = { top = "right", bottom = "left" },   -- where fixed-size panels sit in the top / bottom row
	adopt    = { "voidborn hud", "picture-in-picture", "pip" },   -- widget names that are hosted automatically
	manual   = {},  -- [hostKey] = { x, y, w, h } rectangle given by hand
	altDrag  = true,
}
local editMode = false
local reg = {}          -- name -> entry
local lastSig = ""
local plan = {}         -- name -> { x, y, w, h } as laid out
local dockRects = {}
local lastApplied = {}  -- name -> { x, y, w, h } what we asked for
local seen = {}         -- name -> { x, y, w, h } what the panel reported when last stable
local settle = {}       -- name -> seconds to wait after a layout before watching for drags
local dragging = {}     -- name -> true while the user is dragging the panel
local hoverDock = nil   -- dock under the dragged panel (for the overlay)
local timer = 0

--------------------------------------------------------------------------------
-- registry
--------------------------------------------------------------------------------
local function makeEntry(name, d, old)
	local o = cfg.override[name] or {}
	return {
		name = name, get = d.getRect, set = d.setRect, visible = d.isVisible,
		fixed = d.fixedSize and true or false,
		dock = o.dock or (old and old.dock) or d.dock or "right",
		weight = o.weight or d.weight or 1,
		enabled = o.enabled ~= false,
		floating = (o.floating ~= nil and o.floating) or (o.floating == nil and not o.dock and d.floating) or false,
		minW = d.minW or 120, minH = d.minH or 80,
		maxW = d.maxW or 10000, maxH = d.maxH or 10000,
		aspect = d.aspect, order = o.order or d.order or 100,
	}
end

local function Register(name, d)
	if type(name) ~= "string" or type(d) ~= "table" or type(d.setRect) ~= "function" then return false end
	reg[name] = makeEntry(name, d, reg[name])
	settle[name] = 0.8
	seen[name] = nil
	lastSig = ""
	return true
end

local function Unregister(name)
	reg[name], plan[name], lastApplied[name], seen[name], settle[name], dragging[name] = nil, nil, nil, nil, nil, nil
	lastSig = ""
end

local function scanWG()
	for k, v in pairs(WG) do
		if type(v) == "table" and not reg[k] and k ~= "PanelLayout" and type(v.GetRect) == "function" and type(v.SetRect) == "function" then
			local m = type(v.PanelLayout) == "table" and v.PanelLayout or {}
			local copy = {}
			for kk, vv in pairs(m) do copy[kk] = vv end
			copy.getRect = function() return v.GetRect() end
			copy.setRect = function(x, y, w, h) return v.SetRect(x, y, w, h) end
			Register(k, copy)
		end
	end
end

-- the panel's current rectangle, or nil
local function rectOf(e)
	if not e.get then return nil end
	local ok, x, y, w, h = pcall(e.get)
	if ok and type(x) == "number" and type(y) == "number" and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
		return x, y, w, h
	end
end

local function isShown(e)
	if not e.enabled or not cfg.enabled or e.floating then return false end
	if e.visible then
		local ok, v = pcall(e.visible)
		if ok and not v then return false end
	end
	return true
end

--------------------------------------------------------------------------------
-- layout maths
--------------------------------------------------------------------------------
-- split `total` among items by weight, honouring per-item lo/hi limits
local function distribute(items, total, lo, hi)
	local size, fixed, remaining = {}, {}, total
	local left = #items
	while left > 0 do
		local wsum = 0
		for i, it in ipairs(items) do if not fixed[i] then wsum = wsum + it.weight end end
		local clamped = false
		for i, it in ipairs(items) do
			if not fixed[i] then
				local s = remaining * it.weight / wsum
				local l, h = lo(it), hi(it)
				if s < l then size[i] = l; fixed[i] = true; remaining = remaining - l; left = left - 1; clamped = true; break
				elseif s > h then size[i] = h; fixed[i] = true; remaining = remaining - h; left = left - 1; clamped = true; break end
			end
		end
		if not clamped then
			for i, it in ipairs(items) do
				if not fixed[i] then size[i] = remaining * it.weight / wsum end
			end
			break
		end
	end
	return size
end

local function fitAspect(w, h, aspect)
	if not aspect then return w, h end
	if w / h > aspect then return h * aspect, h end
	return w, w / aspect
end

-- a panel that keeps its own size reports it here; resizable panels get their limits
local function prepare(e)
	if e.fixed then
		local _, _, w, h = rectOf(e)
		e.fw, e.fh = w or e.fw or 200, h or e.fh or 100
		e.minW, e.maxW, e.minH, e.maxH = e.fw, e.fw, e.fh, e.fh
	end
end

local function computePlan()
	local m, g = cfg.margin, cfg.gap
	local by = { left = {}, right = {}, top = {}, bottom = {} }
	for _, e in pairs(reg) do
		if isShown(e) and by[e.dock] then
			prepare(e)
			by[e.dock][#by[e.dock] + 1] = e
		end
	end
	for _, list in pairs(by) do
		table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.name < b.name end)
	end

	-- spill: a column that cannot hold its minimum heights hands its last panel to the opposite column
	local usableH = vsy - 2 * m
	local function minStack(list)
		local s = g * max(#list - 1, 0)
		for _, e in ipairs(list) do s = s + e.minH end
		return s
	end
	for _, pair in ipairs({ { "left", "right" }, { "right", "left" } }) do
		local a, b = by[pair[1]], by[pair[2]]
		while #a > 1 and minStack(a) > usableH and minStack(b) + a[#a].minH + g <= usableH do
			local e = table.remove(a)
			e.spilled = pair[2]
			b[#b + 1] = e
		end
	end

	-- how thick each dock is: panels with a fixed size decide it, resizable ones get their share of the screen
	local function thickness(list, horizontal, screen, fracKey)
		if #list == 0 then return 0 end
		local fixedMax, allFixed = 0, true
		for _, e in ipairs(list) do
			if e.fixed then fixedMax = max(fixedMax, horizontal and e.fh or e.fw) else allFixed = false end
		end
		local base = floor(screen * cfg.frac[fracKey])
		local t = allFixed and fixedMax or max(base, fixedMax)
		return floor(min(t, screen * 0.45))
	end
	local topH   = thickness(by.top, true, vsy, "top")
	local botH   = thickness(by.bottom, true, vsy, "bottom")
	local leftW  = thickness(by.left, false, vsx, "left")
	local rightW = thickness(by.right, false, vsx, "right")

	local midY0 = m + (botH > 0 and botH + g or 0)
	local midY1 = vsy - m - (topH > 0 and topH + g or 0)
	local out = {}
	dockRects = {
		left   = { m, midY0, leftW, midY1 - midY0 },
		right  = { vsx - m - rightW, midY0, rightW, midY1 - midY0 },
		top    = { m + (leftW > 0 and leftW + g or 0), vsy - m - topH, vsx - 2 * m - (leftW > 0 and leftW + g or 0) - (rightW > 0 and rightW + g or 0), topH },
		bottom = { m + (leftW > 0 and leftW + g or 0), m, vsx - 2 * m - (leftW > 0 and leftW + g or 0) - (rightW > 0 and rightW + g or 0), botH },
	}
	-- the side columns run the full height when the rows are narrower than the screen: keep them from overlapping
	dockRects.left[2], dockRects.left[4]   = midY0, midY1 - midY0
	dockRects.right[2], dockRects.right[4] = midY0, midY1 - midY0

	local function column(list, side)
		if #list == 0 then return end
		local r = dockRects[side]
		local colW, colH = r[3], r[4]
		local sizes = distribute(list, colH - g * (#list - 1), function(e) return e.minH end, function(e) return e.maxH end)
		local y = r[2] + colH
		for i, e in ipairs(list) do
			local h = sizes[i]
			local w = min(colW, e.maxW)
			if not e.fixed then w, h = fitAspect(w, h, e.aspect) end
			local x = (side == "left") and r[1] or (r[1] + colW - w)
			out[e.name] = { floor(x), floor(y - h), floor(w), floor(h) }
			y = y - sizes[i] - g
		end
	end

	local function row(list, side)
		if #list == 0 then return end
		local r = dockRects[side]
		local rowW, rowH = r[3], r[4]
		local sizes = distribute(list, rowW - g * (#list - 1), function(e) return e.minW end, function(e) return e.maxW end)
		local x = r[1]
		if cfg.rowAlign[side] == "right" then
			local used = g * (#list - 1)
			for i = 1, #list do used = used + sizes[i] end
			if used < rowW then x = r[1] + rowW - used end
		end
		for i, e in ipairs(list) do
			local w = sizes[i]
			local h = min(rowH, e.maxH)
			if not e.fixed then w, h = fitAspect(w, h, e.aspect) end
			local y = (side == "top") and (r[2] + rowH - h) or r[2]
			out[e.name] = { floor(x), floor(y), floor(w), floor(h) }
			x = x + sizes[i] + g
		end
	end

	column(by.left, "left"); column(by.right, "right")
	row(by.top, "top");      row(by.bottom, "bottom")
	return out
end

local function apply(force)
	plan = computePlan()
	for name, r in pairs(plan) do
		local e = reg[name]
		local last = lastApplied[name]
		if force or not last or last[1] ~= r[1] or last[2] ~= r[2] or last[3] ~= r[3] or last[4] ~= r[4] then
			local ok, err = pcall(e.set, r[1], r[2], r[3], r[4])
			if ok then
				lastApplied[name] = r
				settle[name] = 0.8       -- let the panel clamp itself before we watch for drags
				seen[name] = nil
			else
				spEcho("[PanelSnap] " .. name .. " setRect failed: " .. tostring(err))
				e.enabled = false
			end
		end
	end
end

local function signature()
	local t = { vsx, vsy, tostring(cfg.enabled), cfg.margin, cfg.gap, cfg.rowAlign.top, cfg.rowAlign.bottom }
	for _, d in ipairs(DOCKS) do t[#t + 1] = cfg.frac[d] end
	local names = {}
	for n, e in pairs(reg) do
		local s = n .. e.dock .. e.weight .. e.order .. tostring(e.enabled) .. tostring(e.floating) .. tostring(isShown(e))
		if e.fixed then
			local _, _, w, h = rectOf(e)       -- a fixed-size panel that grows or shrinks reflows its dock
			s = s .. floor(w or 0) .. "x" .. floor(h or 0)
		end
		names[#names + 1] = s
	end
	table.sort(names)
	return table.concat(t, ",") .. "|" .. table.concat(names, ",")
end

--------------------------------------------------------------------------------
-- drag and drop: let a panel go near an edge and it snaps to that dock
--------------------------------------------------------------------------------
local function strips()
	return {
		left   = { 0, 0, vsx * cfg.frac.left, vsy },
		right  = { vsx * (1 - cfg.frac.right), 0, vsx * cfg.frac.right, vsy },
		top    = { 0, vsy * (1 - cfg.frac.top), vsx, vsy * cfg.frac.top },
		bottom = { 0, 0, vsx, vsy * cfg.frac.bottom },
	}
end

local function distToRect(px, py, r)
	local dx = max(r[1] - px, 0, px - (r[1] + r[3]))
	local dy = max(r[2] - py, 0, py - (r[2] + r[4]))
	return sqrt(dx * dx + dy * dy)
end

-- which dock a panel centred at (cx, cy) belongs to, or nil when it was dropped far from every edge
local function nearestDock(cx, cy)
	local best, bestScore, bestDist
	for side, r in pairs(strips()) do
		local d = distToRect(cx, cy, r)
		local edge = (side == "left" and cx) or (side == "right" and vsx - cx) or (side == "top" and vsy - cy) or cy
		local score = d + edge * 0.001
		if not bestScore or score < bestScore then best, bestScore, bestDist = side, score, d end
	end
	if bestDist and bestDist > 0.12 * min(vsx, vsy) then return nil end
	return best
end

local function setOverride(name, key, value)
	cfg.override[name] = cfg.override[name] or {}
	cfg.override[name][key] = value
end

-- re-number the orders of one dock after a drop, so the dropped panel lands where it was released
local function reorder(dock, dropped, cx, cy)
	local list = {}
	for _, e in pairs(reg) do
		if e.dock == dock and (e == dropped or isShown(e)) then
			local key
			if e == dropped then key = (dock == "left" or dock == "right") and -cy or cx
			else
				local p = plan[e.name]
				local ex, ey = p and (p[1] + p[3] / 2) or 0, p and (p[2] + p[4] / 2) or 0
				key = (dock == "left" or dock == "right") and -ey or ex
			end
			list[#list + 1] = { e = e, key = key }
		end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	for i, it in ipairs(list) do
		it.e.order = i * 10
		setOverride(it.e.name, "order", i * 10)
	end
end

local function dropPanel(e, x, y, w, h)
	local cx, cy = x + w / 2, y + h / 2
	local dock = nearestDock(cx, cy)
	if not dock then
		e.floating = true
		setOverride(e.name, "floating", true)
		spEcho("[PanelSnap] " .. e.name .. " floats (dropped away from the edges). /panelsnap dock " .. e.name .. " <side> to snap it again")
	else
		e.floating = false
		setOverride(e.name, "floating", nil)
		e.dock = dock
		setOverride(e.name, "dock", dock)
		reorder(dock, e, cx, cy)
	end
	lastApplied[e.name] = nil
	lastSig = ""
end

local function watchDrags(dt)
	if not cfg.snapOnDrop or not cfg.enabled then return end
	local _, _, lmb = spGetMouseState()
	hoverDock = nil
	for name, e in pairs(reg) do
		if settle[name] and settle[name] > 0 then
			settle[name] = settle[name] - dt
			if settle[name] <= 0 then seen[name] = { rectOf(e) } end   -- the stable position after a layout
		elseif isShown(e) or e.floating then
			local x, y, w, h = rectOf(e)
			local s = seen[name]
			if x then
				if not s or not s[1] then
					seen[name] = { x, y, w, h }
				else
					local moved = abs(x - s[1]) > 4 or abs(y - s[2]) > 4
					if moved and lmb then
						dragging[name] = true                    -- the user has it in their hand
						local d = nearestDock(x + w / 2, y + h / 2)
						hoverDock = d or hoverDock
					elseif moved and not lmb then
						if dragging[name] then
							dragging[name] = nil
							dropPanel(e, x, y, w, h)
						else
							seen[name] = { x, y, w, h }          -- moved by the panel itself, not by a drag
						end
					elseif dragging[name] and not lmb then
						dragging[name] = nil                     -- let go where it started: lay everything out again
						lastSig = ""
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- hosting: dock widgets that know nothing about this layout
--  find the panel by probing the widget's hit test, move it with gl.Translate, shift its mouse input
--------------------------------------------------------------------------------
local PROBE_STEP = 16
local hosts = {}                     -- key -> { key, name, w, off, orig, wrap, raw, hit, gms, ... }
local hostTimer, adoptTimer = 0, 0
local HOSTED_CALLINS = { "DrawScreen", "IsAbove", "GetTooltip", "MousePress", "MouseMove", "MouseRelease", "MouseWheel" }
local realGMS = spGetMouseState
local canShim = pcall(function() Spring.GetMouseState = Spring.GetMouseState end)

local function slug(s)
	local t = s:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
	return t
end

-- word match, so "pip" finds "PiP" but not "pipeline"
local function nameMatches(name, pat)
	name, pat = name:lower(), pat:lower()
	if pat == "" then return false end
	local init = 1
	while true do
		local s, e = name:find(pat, init, true)
		if not s then return false end
		local before = s > 1 and name:sub(s - 1, s - 1) or ""
		local after = name:sub(e + 1, e + 1)
		if not before:match("%w") and not after:match("%w") then return true end
		init = s + 1
	end
end

local function wantAdopt(name)
	for _, pat in ipairs(cfg.adopt) do
		if nameMatches(name, pat) then return true end
	end
	return false
end

-- run a widget callin with Spring.GetMouseState reporting the widget's own (unshifted) coordinates
local function callIn(h, f, self, ...)
	local off = h.off
	if not canShim or (off[1] == 0 and off[2] == 0) then return f(self, ...) end
	Spring.GetMouseState = h.gms
	local ok, a, b = pcall(f, self, ...)
	Spring.GetMouseState = realGMS
	if not ok then error(a, 0) end
	return a, b
end

local function makeWrapper(h, name)
	local off = h.off
	if name == "DrawScreen" then
		return function(self, ...)
			local ox, oy = off[1], off[2]
			if ox == 0 and oy == 0 then return h.orig.DrawScreen(self, ...) end
			glPushMatrix(); glTranslate(ox, oy, 0)
			local ok, err = pcall(callIn, h, h.orig.DrawScreen, self, ...)
			glPopMatrix()
			if not ok then error(err, 0) end
		end
	elseif name == "IsAbove" or name == "GetTooltip" or name == "MousePress" or name == "MouseMove" or name == "MouseRelease" then
		return function(self, x, y, ...) return callIn(h, h.orig[name], self, x - off[1], y - off[2], ...) end
	else   -- MouseWheel: no coordinates, but the widget may ask the mouse state
		return function(self, ...) return callIn(h, h.orig[name], self, ...) end
	end
end

local function wrapCallins(h)
	local w = h.w
	for _, name in ipairs(HOSTED_CALLINS) do
		local f = w[name]
		if type(f) == "function" and f ~= h.wrap[name] then
			h.orig[name] = f
			h.wrap[name] = h.wrap[name] or makeWrapper(h, name)
			w[name] = h.wrap[name]
		end
	end
end

local function unwrapCallins(h)
	for _, name in ipairs(HOSTED_CALLINS) do
		if h.wrap[name] and h.w[name] == h.wrap[name] then h.w[name] = h.orig[name] end
	end
end

-- a widget's hit test: true where it has something
local function makeHit(h)
	local w = h.w
	if h.orig.IsAbove then return function(x, y) return h.orig.IsAbove(w, x, y) and true or false end end
	if h.orig.GetTooltip then
		return function(x, y) local t = h.orig.GetTooltip(w, x, y); return t ~= nil and t ~= "" end
	end
end

-- bounding box of the hit area inside a window, found on a lattice and refined by bisection at the edges
local function findRect(hit, x0, y0, x1, y1, clamp)
	local S = PROBE_STEP
	-- a full scan stays on the screen; a local one may leave it (the widget's own space is offset from what we show)
	local openL, openR, openB, openT = true, true, true, true
	if clamp then
		openL, openR, openB, openT = false, false, false, false
		x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, vsx), min(y1, vsy)
	end
	local gx0, gx1, gy0, gy1 = ceil(x0 / S), floor(x1 / S), ceil(y0 / S), floor(y1 / S)
	local lx, ly, rx, ry, bx, by, tx, ty
	local border = false
	for gy = gy0, gy1 do
		local y = gy * S
		for gx = gx0, gx1 do
			local x = gx * S
			if hit(x, y) then
				if not lx or x < lx then lx, ly = x, y end
				if not rx or x > rx then rx, ry = x, y end
				if not by or y < by then bx, by = x, y end
				if not ty or y > ty then tx, ty = x, y end
				if (openL and gx == gx0) or (openR and gx == gx1) or (openB and gy == gy0) or (openT and gy == gy1) then border = true end
			end
		end
	end
	if not lx then return nil, false end
	local function bisect(ax, ay, cx, cy)       -- (ax,ay) misses, (cx,cy) hits; returns the hit side
		for _ = 1, 5 do
			local mx, my = (ax + cx) / 2, (ay + cy) / 2
			if hit(mx, my) then cx, cy = mx, my else ax, ay = mx, my end
		end
		return cx, cy
	end
	local left   = bisect(lx - S, ly, lx, ly)
	local right  = bisect(rx + S, ry, rx, ry)
	local _, bot = bisect(bx, by - S, bx, by)
	local _, top = bisect(tx, ty + S, tx, ty)
	local x, y, w, hh = floor(left), floor(bot), ceil(right) - floor(left), ceil(top) - floor(bot)
	if w < 8 or hh < 8 or w * hh > 0.5 * vsx * vsy then return nil, false end   -- not a panel (e.g. "everywhere")
	return { x, y, w, hh }, border
end

local function sameRect(a, b)
	return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

local function setRaw(h, r)
	if sameRect(h.raw, r) then return end
	local first = h.raw == nil
	h.raw = r
	-- the widget moved or resized itself (not by a drag we are tracking): put it back into its slot
	if r and not first and not dragging[h.key] then
		lastApplied[h.key] = nil
		lastSig = ""
	end
end

local function probeHost(h, localOnly)
	local m = cfg.manual[h.key]
	if m then setRaw(h, { m[1], m[2], m[3], m[4] }); return end
	if not h.hit then return end
	local old = h.raw
	if localOnly and old then
		local pad = 6 * PROBE_STEP
		local ok, r, border = pcall(findRect, h.hit, old[1] - pad, old[2] - pad, old[1] + old[3] + pad, old[2] + old[4] + pad)
		if ok and r and not border then setRaw(h, r); return end
	end
	local now = os.clock()
	if now - h.lastFull < 1.5 then return end
	h.lastFull = now
	local ok, r = pcall(findRect, h.hit, 0, 0, vsx, vsy, true)
	if ok then setRaw(h, r) else h.hit = nil; spEcho("[PanelSnap] probing " .. h.name .. " failed: " .. tostring(r)) end
end

-- which dock a panel at this raw rectangle starts in: the nearest edge, wide panels prefer top/bottom
local function autoDock(r)
	local cx, cy = r[1] + r[3] / 2, r[2] + r[4] / 2
	local wide = r[3] >= r[4]
	local best, bestScore
	for side, s in pairs(strips()) do
		local d = distToRect(cx, cy, s)
		if d <= 0.12 * min(vsx, vsy) then
			local edge = (side == "left" and cx) or (side == "right" and vsx - cx) or (side == "top" and vsy - cy) or cy
			local horizontal = side == "top" or side == "bottom"
			local score = d + edge * 0.001 + ((horizontal == wide) and 0 or 1000)
			if not bestScore or score < bestScore then best, bestScore = side, score end
		end
	end
	return best
end

local function registerHost(h)
	local dock = autoDock(h.raw)
	Register(h.key, {
		fixedSize = true, dock = dock or "right", floating = dock == nil, order = 50,
		getRect = function() local r = h.raw; if not r then return nil end return r[1] + h.off[1], r[2] + h.off[2], r[3], r[4] end,
		setRect = function(x, y) if h.raw then h.off[1], h.off[2] = floor(x - h.raw[1]), floor(y - h.raw[2]) end end,
		isVisible = function() return h.raw ~= nil end,
	})
	h.registered = true
end

local function dropHost(h)
	unwrapCallins(h)
	if h.registered then Unregister(h.key) end
	hosts[h.key] = nil
end

local function hostWidget(w, name)
	local key = "w_" .. slug(name)
	if hosts[key] or reg[key] or key == "w_" then return end
	local h = { key = key, name = name, w = w, off = { 0, 0 }, orig = {}, wrap = {}, lastFull = -10 }
	h.gms = function() local x, y, a, b, c = realGMS(); return x - h.off[1], y - h.off[2], a, b, c end
	wrapCallins(h)
	h.hit = makeHit(h)
	if not h.hit and not cfg.manual[key] then
		spEcho("[PanelSnap] " .. name .. " has no IsAbove/GetTooltip to find its panel: /panelsnap rect " .. key .. " x y w h")
	end
	hosts[key] = h
end

local function adoptScan()
	local list = widgetHandler and widgetHandler.widgets
	if type(list) ~= "table" then return end
	local present = {}
	for _, w in ipairs(list) do
		local info = type(w) == "table" and w.whInfo
		local name = info and info.name
		if name and w ~= widget then
			local key = "w_" .. slug(name)
			present[key] = w
			local h = hosts[key]
			if h and h.w ~= w then dropHost(h); h = nil end        -- reloaded: a new widget table
			if not h and wantAdopt(name) then hostWidget(w, name) end
		end
	end
	for key, h in pairs(hosts) do
		if present[key] ~= h.w or not wantAdopt(h.name) then dropHost(h) end
	end
end

local function hostUpdate(dt)
	adoptTimer = adoptTimer + dt
	if adoptTimer >= 1 then adoptTimer = 0; adoptScan() end
	if not next(hosts) then return end
	local mx, my, lmb = spGetMouseState()
	hostTimer = hostTimer + dt
	local slow = hostTimer >= 0.5
	if slow then hostTimer = 0 end
	for _, h in pairs(hosts) do
		if slow then wrapCallins(h) end                              -- in case the widget replaced a callin
		if cfg.enabled then
			local near = false
			if lmb and h.raw then                                    -- someone may be dragging it: follow it every frame
				local x, y = h.raw[1] + h.off[1], h.raw[2] + h.off[2]
				near = mx > x - 300 and mx < x + h.raw[3] + 300 and my > y - 300 and my < y + h.raw[4] + 300
			end
			if near or slow or not h.raw then probeHost(h, true) end
			if h.raw and not h.registered then registerHost(h) end
		end
	end
end

local function resetHostOffsets()
	for _, h in pairs(hosts) do h.off[1], h.off[2] = 0, 0 end
end

--------------------------------------------------------------------------------
-- Alt + drag: move any panel by hand, then it snaps on release like any other drag
--------------------------------------------------------------------------------
local grab = nil     -- { e, dx, dy, w, h }

local function panelAt(x, y)
	local best, bestArea, bx, by, bw, bh
	for _, e in pairs(reg) do
		if isShown(e) or e.floating then
			local rx, ry, rw, rh = rectOf(e)
			if rx and x >= rx and x <= rx + rw and y >= ry and y <= ry + rh and (not bestArea or rw * rh < bestArea) then
				best, bestArea, bx, by, bw, bh = e, rw * rh, rx, ry, rw, rh
			end
		end
	end
	return best, bx, by, bw, bh
end

--------------------------------------------------------------------------------
-- widget callins
--------------------------------------------------------------------------------
function widget:Initialize()
	WG.PanelLayout = {
		Register = Register, Unregister = Unregister,
		Apply = function() apply(true) end,
		IsManaged = function(name) local e = reg[name]; return e ~= nil and isShown(e) end,
	}
	scanWG()
end

function widget:Shutdown()
	for _, h in pairs(hosts) do unwrapCallins(h) end      -- give every hosted widget its own drawing back
	hosts = {}
	WG.PanelLayout = nil
end

function widget:MousePress(x, y, button)
	if button ~= 1 or not cfg.enabled or not cfg.altDrag then return false end
	if not spGetModKeyState() then return false end
	local e, rx, ry, rw, rh = panelAt(x, y)
	if not e then return false end
	grab = { e = e, dx = x - rx, dy = y - ry, w = rw, h = rh }
	return true
end

function widget:MouseMove(x, y)
	if not grab then return end
	local nx = max(0, min(vsx - grab.w, x - grab.dx))
	local ny = max(0, min(vsy - grab.h, y - grab.dy))
	pcall(grab.e.set, nx, ny, grab.w, grab.h)
end

function widget:MouseRelease()
	grab = nil
end

function widget:ViewResize(x, y)
	vsx, vsy = x, y
	lastSig = ""
end

function widget:Update(dt)
	hostUpdate(dt)
	watchDrags(dt)
	timer = timer + dt
	if timer < 0.25 then return end
	timer = 0
	scanWG()
	if next(dragging) then return end        -- do not fight the hand
	local s = signature()
	if s ~= lastSig then
		lastSig = s
		apply(false)
	end
end

function widget:DrawScreen()
	local showing = editMode or next(dragging)
	if not showing then return end
	local S = strips()
	for side, r in pairs(S) do
		local hot = hoverDock == side
		glColor(0.2, 0.6, 1, hot and 0.30 or 0.10); glRect(r[1], r[2], r[1] + r[3], r[2] + r[4])
		if hot then glColor(1, 1, 1, 0.9); glText(side:upper(), r[1] + r[3] / 2 - 20, r[2] + r[4] / 2, 16, "o") end
	end
	if editMode then
		for name, r in pairs(plan) do
			glColor(1, 1, 1, 0.5)
			gl.BeginEnd(GL.LINE_LOOP, function()
				gl.Vertex(r[1], r[2]); gl.Vertex(r[1] + r[3], r[2])
				gl.Vertex(r[1] + r[3], r[2] + r[4]); gl.Vertex(r[1], r[2] + r[4])
			end)
			glText(name, r[1] + 4, r[2] + r[4] - 16, 12, "o")
		end
	end
	glColor(1, 1, 1, 1)
end

local HELP = {
	"Drag a panel by its title bar and let go near an edge: it snaps there. Let go in the middle: it floats.",
	"/panelsnap [on|off]            toggle auto layout",
	"/panelsnap apply               force re-layout",
	"/panelsnap edit                show the dock overlay",
	"/panelsnap list                list the panels",
	"/panelsnap dock <name> <left|right|top|bottom>   (also re-snaps a floating panel)",
	"/panelsnap float <name>        stop managing the position of a panel",
	"/panelsnap order <name> <n>    position inside the dock (lower = first)",
	"/panelsnap weight <name> <number>   share of the dock for resizable panels",
	"/panelsnap frac <left|right|top|bottom> <0.05-0.4>",
	"/panelsnap gap <px>   |   /panelsnap margin <px>",
	"/panelsnap drop on|off         snap panels when you drag them",
	"/panelsnap skip <name>         never touch a panel   |   /panelsnap reset  forget all your changes",
	"/panelsnap adopt <widget name> host any widget's panel without it knowing (word match, e.g. pip)  |  unadopt <name>",
	"/panelsnap widgets             list loaded widgets, hosted ones marked   |  /panelsnap rect <key> x y w h  (or 'off')",
	"/panelsnap align <top|bottom> <left|right>   |   /panelsnap alt on|off   (Alt+drag moves any panel)",
}

function widget:TextCommand(cmd)
	local a, b, c = cmd:match("^panelsnap%s*(%S*)%s*(%S*)%s*(%S*)")
	if not a then return false end
	local rest = cmd:match("^panelsnap%s+%S+%s+(.-)%s*$")
	if a == "" or a == "on" or a == "off" then
		cfg.enabled = (a == "on") or (a == "" and not cfg.enabled)
		if not cfg.enabled then resetHostOffsets() end
		lastApplied = {}
		spEcho("[PanelSnap] " .. (cfg.enabled and "on" or "off"))
	elseif a == "adopt" and rest then
		for _, p in ipairs(cfg.adopt) do if p:lower() == rest:lower() then rest = nil; break end end
		if rest then cfg.adopt[#cfg.adopt + 1] = rest end
		adoptScan()
		spEcho("[PanelSnap] hosting widgets matching '" .. tostring(rest or b) .. "' (see /panelsnap list)")
	elseif a == "unadopt" and rest then
		for i = #cfg.adopt, 1, -1 do if cfg.adopt[i]:lower() == rest:lower() then table.remove(cfg.adopt, i) end end
		adoptScan()
		lastApplied = {}
	elseif a == "widgets" then
		for _, w in ipairs(widgetHandler and widgetHandler.widgets or {}) do
			local name = type(w) == "table" and w.whInfo and w.whInfo.name
			if name and w ~= widget then
				local key = "w_" .. slug(name)
				local h = hosts[key]
				local hit = (w.IsAbove or w.GetTooltip) and "" or "  (no hit test)"
				spEcho(("[PanelSnap] %s%s%s"):format(name, h and ("  [HOSTED as " .. key .. (h.raw and "" or ", no panel found") .. "]") or "", hit))
			end
		end
	elseif a == "rect" and b ~= "" then
		local x, y, w, h = cmd:match("^panelsnap%s+rect%s+%S+%s+(-?%d+)%s+(-?%d+)%s+(%d+)%s+(%d+)")
		if x then cfg.manual[b] = { tonumber(x), tonumber(y), tonumber(w), tonumber(h) }
		else cfg.manual[b] = nil end
	elseif a == "align" and (b == "top" or b == "bottom") and (c == "left" or c == "right") then
		cfg.rowAlign[b] = c
	elseif a == "alt" and (b == "on" or b == "off") then cfg.altDrag = (b == "on")
	elseif a == "apply" then apply(true)
	elseif a == "edit" then editMode = not editMode
	elseif a == "list" then
		for n, e in pairs(reg) do
			spEcho(("[PanelSnap] %s dock=%s order=%s weight=%s%s%s%s%s"):format(n, e.dock, e.order, e.weight,
				e.fixed and " fixed-size" or "", e.floating and " FLOATING" or "", e.enabled and "" or " (off)",
				hosts[n] and " (hosted)" or ""))
		end
	elseif a == "dock" and reg[b] and DOCK_OK[c] then
		local e = reg[b]
		e.dock, e.floating, e.enabled = c, false, true
		setOverride(b, "dock", c); setOverride(b, "floating", nil); setOverride(b, "enabled", nil)
	elseif a == "float" and reg[b] then
		reg[b].floating = true; setOverride(b, "floating", true)
	elseif a == "order" and reg[b] and tonumber(c) then
		reg[b].order = tonumber(c); setOverride(b, "order", tonumber(c))
	elseif a == "weight" and reg[b] and tonumber(c) then
		reg[b].weight = max(0.1, tonumber(c)); setOverride(b, "weight", reg[b].weight)
	elseif a == "frac" and cfg.frac[b] and tonumber(c) then
		cfg.frac[b] = min(0.4, max(0.05, tonumber(c)))
	elseif a == "gap" and tonumber(b) then cfg.gap = tonumber(b)
	elseif a == "margin" and tonumber(b) then cfg.margin = tonumber(b)
	elseif a == "drop" and (b == "on" or b == "off") then cfg.snapOnDrop = (b == "on")
	elseif a == "skip" and reg[b] then
		reg[b].enabled = false; setOverride(b, "enabled", false)
	elseif a == "reset" then
		cfg.override = {}
		for n, e in pairs(reg) do e.floating, e.enabled, e.order, e.weight = false, true, 100, 1 end
		spEcho("[PanelSnap] all changes forgotten")
	else
		for _, l in ipairs(HELP) do spEcho(l) end
	end
	lastSig = ""
	return true
end

function widget:GetConfigData()
	return { enabled = cfg.enabled, snapOnDrop = cfg.snapOnDrop, margin = cfg.margin, gap = cfg.gap, frac = cfg.frac, override = cfg.override,
		rowAlign = cfg.rowAlign, adopt = cfg.adopt, manual = cfg.manual, altDrag = cfg.altDrag }
end

function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	for k, v in pairs(d) do cfg[k] = v end
	cfg.frac = cfg.frac or { left = 0.17, right = 0.19, top = 0.09, bottom = 0.15 }
	cfg.override = cfg.override or {}
	cfg.rowAlign = cfg.rowAlign or { top = "right", bottom = "left" }
	cfg.adopt = cfg.adopt or { "voidborn hud", "picture-in-picture", "pip" }
	cfg.manual = cfg.manual or {}
	if cfg.altDrag == nil then cfg.altDrag = true end
	if cfg.snapOnDrop == nil then cfg.snapOnDrop = true end
	-- panels that registered before the saved settings arrived
	for n, e in pairs(reg) do
		local o = cfg.override[n]
		if o then
			e.dock = o.dock or e.dock; e.weight = o.weight or e.weight; e.order = o.order or e.order
			e.floating = o.floating and true or false; e.enabled = o.enabled ~= false
		end
	end
	lastSig = ""
end
