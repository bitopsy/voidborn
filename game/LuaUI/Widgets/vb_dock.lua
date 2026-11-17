function widget:GetInfo()
	return { name = "Voidborn Dock", desc = "Snaps the HUD panels into one column at the side of the screen: tooltip, build menu, radars, census, minimap (/vbdock)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -5, enabled = true }
end

--[[
  THE DOCK

  One column, flush with the left edge of the screen, every panel the same width.  From the bottom up (the default):

      tooltip  ->  build menu  ->  economy radar  ->  army radar  ->  unit census  ->  minimap

  The panels are separate widgets (vb_tooltip, vb_buildpanel, vb_hud_econ, vb_hud_army, vb_unitstats); this widget
  only decides where each one goes.  They talk to it through WG.VBDock:

      Report(id, hOpen, hFolded)   every frame a panel says how tall it wants to be (in dock units: 1 unit = 1 pixel at scale 1)
      Rect(id)                     x1, y1, x2, y2, scale, folded  - where to draw (nil: nothing to draw)
      IsOn / SetOn / ToggleOn      switch a panel on or off (economy radar, army radar, census)
      IsCollapsed / ToggleCollapsed   the - / + button of a panel
      BeginDrag / DragMove / DragEnd  drag a title bar to another slot: the panel snaps there on release

  Everything is remembered with the other widget settings.  The whole column shrinks (down to 75 %) when it does not
  fit the screen height, and folds the top panels if that is still not enough.

      /vbdock                  list the panels
      /vbdock econ|army|census switch that panel on / off
      /vbdock reset            default order, scale and side
      /vbdock side left|right  which edge of the screen
      /vbdock scale 1.2        size of the whole column (0.6 .. 1.6)
]]

local floor, ceil, max, min, exp = math.floor, math.ceil, math.max, math.min, math.exp

local BASE_W, GAP, MARGIN = 298, 4, 6      -- dock units (1 unit = 1 pixel at scale 1); 298 = the build panel at its default size
local MM_STRIP, MM_PAD = 16, 3             -- minimap slot: title strip on top, padding around the map
local FIT_FLOOR = 0.75                     -- the column may shrink to this share of its normal size before panels are folded

local DEFAULT_ORDER = { "tooltip", "build", "econ", "army", "census", "minimap" }     -- bottom to top
local TOGGLE = { econ = "Economy radar", army = "Army radar", census = "Unit census" }
local FOLD_FIRST = { "census", "army", "econ" }
local TITLES = { tooltip = "Tooltip", build = "Build menu", econ = "Economy radar", army = "Army radar", census = "Unit census", minimap = "Minimap" }

local function Copy(t) local c = {}; for i, v in ipairs(t) do c[i] = v end return c end
local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local vsx, vsy = Spring.GetViewGeometry()
local side, userScale = "left", 1.0
local order = Copy(DEFAULT_ORDER)
local on = { econ = true, army = true, census = true }
local collapsed = {}
local reports, frame = {}, 0
local S, folded = 1, {}
local target, cur = {}, {}          -- id -> { y1, y2 }  (target, and the eased value that is drawn)
local colX = MARGIN
local drag = nil                    -- { id, dy (panel top minus mouse y), snap = { id -> mid y of the others without it }, idx }
local lastGeo, mmMode, mmTries = nil, nil, 0
local Dock = {}

--------------------------------------------------------------------------------
-- sizes
--------------------------------------------------------------------------------
local function MinimapDims()          -- inner size of the map in dock units: the map's own aspect, never wider than the column
	local ratio = 1
	local gx, gz = Game and tonumber(Game.mapSizeX), Game and tonumber(Game.mapSizeZ)
	if gx and gz and gx > 0 and gz > 0 then ratio = gz / gx end
	ratio = Clamp(ratio, 0.4, 2.5)
	local inner = BASE_W - 2 * MM_PAD
	if ratio <= 1 then return inner, inner * ratio end
	return inner / ratio, inner
end

local function HeightOf(id, fold)     -- dock units
	if id == "minimap" then local _, mh = MinimapDims(); return MM_STRIP + MM_PAD * 2 + mh end
	local r = reports[id]
	if not r then return 0 end
	if fold then return r.h0 end
	return r.h1
end

local function Present(id)
	if id == "minimap" then return true end
	local r = reports[id]
	if not r or r.seen < frame - 3 or r.h1 <= 0 then return false end
	if on[id] == false then return false end
	return true
end

--------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------
local function Compute(ord)
	local list = {}
	for _, id in ipairs(ord) do if Present(id) then list[#list + 1] = id end end
	local S0 = Clamp(vsy / 1080, 0.75, 1.5) * userScale
	local fold = {}
	local function Total()
		local t = 2 * MARGIN + GAP * max(0, #list - 1)
		for _, id in ipairs(list) do t = t + HeightOf(id, collapsed[id] or fold[id]) end
		return t
	end
	local sfit = vsy / Total()
	if sfit < S0 * FIT_FLOOR then
		for _, id in ipairs(FOLD_FIRST) do
			local r = reports[id]
			local inList = false
			for _, l in ipairs(list) do if l == id then inList = true end end
			if inList and not collapsed[id] and r and r.h0 < r.h1 then
				fold[id] = true
				sfit = vsy / Total()
				if sfit >= S0 * FIT_FLOOR then break end
			end
		end
	end
	local s = max(0.4, min(S0, sfit))
	local t, y = {}, MARGIN * s
	for _, id in ipairs(list) do
		local h = HeightOf(id, collapsed[id] or fold[id]) * s
		t[id] = { y, y + h }
		y = y + h + GAP * s
	end
	return list, fold, s, t
end

local function OrderWithDrag()
	if not drag then return order end
	local o = {}
	for _, id in ipairs(order) do if id ~= drag.id then o[#o + 1] = id end end
	table.insert(o, Clamp(drag.idx or #o + 1, 1, #o + 1), drag.id)
	return o
end

local function Relayout(dt)
	local list, fold, s, t = Compute(OrderWithDrag())
	S, folded, target = s, fold, t
	local W = BASE_W * s
	colX = (side == "right") and (vsx - MARGIN * s - W) or (MARGIN * s)
	local k = 1 - exp(-(dt or 0.016) * 22)
	for id, tr in pairs(t) do
		local c = cur[id]
		if not c then cur[id] = { tr[1], tr[2] }
		else
			c[1] = c[1] + (tr[1] - c[1]) * k; c[2] = c[2] + (tr[2] - c[2]) * k
			if math.abs(c[1] - tr[1]) < 0.6 then c[1] = tr[1] end
			if math.abs(c[2] - tr[2]) < 0.6 then c[2] = tr[2] end
		end
	end
	for id in pairs(cur) do if not t[id] then cur[id] = nil end end
end

--------------------------------------------------------------------------------
-- the minimap (the engine draws it; this places it)
--------------------------------------------------------------------------------
local function MinimapRect()          -- the map itself, in screen pixels (bottom-left origin)
	local c = cur.minimap
	if not c then return end
	if drag and drag.id == "minimap" and drag.rect then c = drag.rect end
	local mw, mh = MinimapDims()
	local W = BASE_W * S
	local x = colX + (W - mw * S) / 2
	return x, c[1] + MM_PAD * S, mw * S, mh * S
end

local function ApplyMinimap()
	if not (Spring.SendCommands and Spring.GetViewGeometry) then return end
	local x, y, w, h = MinimapRect()
	if not x then return end
	x, y, w, h = floor(x + 0.5), floor(y + 0.5), floor(w + 0.5), floor(h + 0.5)
	local key = x .. " " .. y .. " " .. w .. " " .. h
	if key == lastGeo then return end
	lastGeo = key
	-- "minimap geometry x y w h": the engine counts y from the top of the screen; the command is checked once with
	-- Spring.IsAboveMiniMap (which takes ordinary bottom-left mouse coordinates) and the other convention is used if it
	-- turns out to be the other way round
	local function Send(yArg) Spring.SendCommands(string.format("minimap geometry %d %d %d %d", x, yArg, w, h)) end
	local top = vsy - y - h
	Send(mmMode == "bottom" and y or top)
	if mmMode == nil and Spring.IsAboveMiniMap and mmTries < 4 then
		mmTries = mmTries + 1
		if Spring.IsAboveMiniMap(x + w / 2, y + h / 2) then mmMode = "top"
		else
			Send(y)
			if Spring.IsAboveMiniMap(x + w / 2, y + h / 2) then mmMode = "bottom"
			else Send(top) end
		end
	end
end

--------------------------------------------------------------------------------
-- the API
--------------------------------------------------------------------------------
Dock.BASE_W = BASE_W
Dock.TITLES = TITLES
function Dock.Report(id, h1, h0)
	local r = reports[id]
	if not r then r = {}; reports[id] = r end
	r.h1, r.h0, r.seen = h1 or 0, h0 or h1 or 0, frame
end
function Dock.Rect(id)
	if drag and drag.id == id and drag.rect then
		return colX, drag.rect[1], colX + BASE_W * S, drag.rect[2], S, folded[id] or false
	end
	local c = cur[id]
	if not c then return nil end
	return colX, c[1], colX + BASE_W * S, c[2], S, folded[id] or false
end
function Dock.Scale() return S end
function Dock.Side() return side end
function Dock.IsOn(id) return on[id] ~= false end
function Dock.SetOn(id, v) if TOGGLE[id] then on[id] = v and true or false end end
function Dock.ToggleOn(id) if TOGGLE[id] then on[id] = not (on[id] ~= false) end return on[id] end
function Dock.IsCollapsed(id) return collapsed[id] == true end
function Dock.SetCollapsed(id, v) collapsed[id] = v and true or nil end
function Dock.ToggleCollapsed(id) collapsed[id] = (not collapsed[id]) or nil; return collapsed[id] == true end
function Dock.Order() return Copy(order) end

function Dock.BeginDrag(id, mx, my)
	local c = cur[id]
	if not c then return end
	-- where the others would sit without the dragged panel: frozen, so the slot does not flicker while it moves
	local others = {}
	for _, o in ipairs(order) do if o ~= id then others[#others + 1] = o end end
	local saved = drag
	drag = nil
	local _, _, _, t = Compute(others)
	drag = saved
	local snap = {}
	for _, o in ipairs(others) do if t[o] then snap[#snap + 1] = (t[o][1] + t[o][2]) / 2 end end
	local idx = 1
	for i, o in ipairs(order) do if o == id then idx = i end end
	drag = { id = id, dy = c[2] - my, snap = snap, h = c[2] - c[1], idx = idx }
	drag.rect = { c[1], c[2] }
end
function Dock.DragMove(mx, my)
	if not drag then return end
	local h = drag.h
	local y2 = Clamp(my + drag.dy, h, vsy)
	drag.rect = { y2 - h, y2 }
	local n = 0
	for _, m in ipairs(drag.snap) do if m < my then n = n + 1 end end
	drag.idx = n + 1
end
function Dock.DragEnd()
	if not drag then return end
	local id = drag.id
	local o = OrderWithDrag()
	order = o
	cur[id] = { drag.rect[1], drag.rect[2] }      -- it eases from where it was dropped into its slot
	drag = nil
end
function Dock.Dragging() return drag and drag.id or nil end

function Dock.Reset()
	order = Copy(DEFAULT_ORDER); side, userScale = "left", 1.0
	on = { econ = true, army = true, census = true }; collapsed = {}
	drag, lastGeo = nil, nil
end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
function widget:Initialize()
	WG.VBDock = Dock
	Spring.Echo("[VB] Dock loaded: tooltip, build menu, radars, census and minimap snap into one column (/vbdock)")
end
function widget:Shutdown() if WG.VBDock == Dock then WG.VBDock = nil end end
function widget:ViewResize(w, h) vsx, vsy = w, h; lastGeo = nil end

function widget:Update(dt)
	frame = frame + 1
	vsx, vsy = Spring.GetViewGeometry()
	Relayout(dt)
	ApplyMinimap()
end

local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end

function widget:DrawScreen()
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
	local W = BASE_W * S
	-- while a panel is dragged: the slot it will snap into
	if drag and target[drag.id] then
		local t = target[drag.id]
		Box(colX, t[1], colX + W, t[2], 0.85, 0.65, 0.2, 0.10)
		Frame(colX, t[1], colX + W, t[2], 0.85, 0.65, 0.2, 0.75)
	end
	-- the minimap slot: plate, title strip and frame around the engine's minimap
	local c = cur.minimap
	if not c then return end
	local y1, y2 = c[1], c[2]
	if drag and drag.id == "minimap" and drag.rect then y1, y2 = drag.rect[1], drag.rect[2] end
	local x1, x2 = colX, colX + W
	Box(x1, y1, x2, y2, 0.06, 0.06, 0.09, 0.88)
	Frame(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.9)
	local sh = MM_STRIP * S
	Box(x1, y2 - sh, x2, y2, 0.14, 0.12, 0.2, 1)
	VBFont.Text("MINIMAP", x1 + 6 * S, y2 - sh + sh * 0.28, 10 * S, "o", 0.9, 0.85, 0.7, 1)
	Box(x1 + 1, y2 - sh - 1, x2 - 1, y2 - sh, 0.85, 0.65, 0.2, 0.35)
end

function widget:IsAbove(x, y)
	local c = cur.minimap
	if not c then return false end
	local sh = MM_STRIP * S
	return x >= colX and x <= colX + BASE_W * S and y >= c[2] - sh and y <= c[2]
end
function widget:MousePress(x, y, button)
	if button ~= 1 or not widget:IsAbove(x, y) then return false end
	Dock.BeginDrag("minimap", x, y)
	return true
end
function widget:MouseMove(x, y) if drag and drag.id == "minimap" then Dock.DragMove(x, y) end end
function widget:MouseRelease() if drag and drag.id == "minimap" then Dock.DragEnd() end end

function widget:TextCommand(cmd)
	local word, rest = cmd:match("^(%S+)%s*(.*)$")
	if word ~= "vbdock" then return false end
	local a, v = rest:match("^(%S*)%s*(.*)$")
	a = a:lower()
	if TOGGLE[a] then
		Dock.ToggleOn(a); Spring.Echo("[VB] " .. TOGGLE[a] .. ": " .. (Dock.IsOn(a) and "on" or "off"))
	elseif a == "reset" then Dock.Reset(); Spring.Echo("[VB] dock: default layout")
	elseif a == "side" then
		if v == "left" or v == "right" then side = v; lastGeo = nil else Spring.Echo("[VB] /vbdock side left|right  (now: " .. side .. ")") end
	elseif a == "scale" then userScale = Clamp(tonumber(v) or 1, 0.6, 1.6); lastGeo = nil
	else
		local names = {}
		for _, id in ipairs(order) do names[#names + 1] = id end
		Spring.Echo("[VB] /vbdock [econ | army | census | reset | side left|right | scale 0.6..1.6]   bottom to top: " .. table.concat(names, " > "))
	end
	return true
end

function widget:GetConfigData() return { side = side, scale = userScale, order = order, on = on, collapsed = collapsed } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.side == "left" or d.side == "right" then side = d.side end
	if tonumber(d.scale) then userScale = Clamp(d.scale, 0.6, 1.6) end
	if type(d.order) == "table" then
		local seen, o = {}, {}
		for _, id in ipairs(d.order) do
			if TITLES[id] and not seen[id] then seen[id] = true; o[#o + 1] = id end
		end
		for i, id in ipairs(DEFAULT_ORDER) do if not seen[id] then table.insert(o, min(i, #o + 1), id) end end
		order = o
	end
	if type(d.on) == "table" then for id in pairs(TOGGLE) do if d.on[id] ~= nil then on[id] = d.on[id] and true or false end end end
	if type(d.collapsed) == "table" then for id, v in pairs(d.collapsed) do if v then collapsed[id] = true end end end
end
