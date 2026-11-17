-- Voidborn unit forge: the unit creation panel.
--
-- Pick a base unit, tune its numbers, design a brand new 3D shape and map a PNG
-- onto it.  CREATE puts the unit in the production queue (it costs metal, energy and
-- build time, see LuaRules/Gadgets/vb_dev_queue.lua), SAVE only stores the design:
-- saved designs show up as tiles in the build panel for the rest of this game.
--
-- Title bar:  [A-] [A+] zoom the contents   [-] minimize   [x] close
-- Mouse wheel scrolls the tab, the corner handle resizes, click the ID to rename.
--
--   /vbforge            open / close the panel
--   /vbcreate <id> ...  still works from the chat (instant, free)
function widget:GetInfo()
	return { name = "Voidborn Unit Forge", desc = "Create units: base unit, numbers, 3D shape and png mapping (drag to move, corner to resize)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 4, enabled = true }
end

-- alien UI font; falls back to the engine font automatically
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
local okG, Forge = pcall(VFS.Include, "LuaUI/Headers/vb_forge.h.lua")
if not okG or type(Forge) ~= "table" then
	Spring.Echo("[VB] unit forge: could not load LuaUI/Headers/vb_forge.h.lua: " .. tostring(Forge))
	Forge = { Ser = function() return "{}" end, PngList = function() return {} end,
		PngPath = function() end, EncodeShape = function() return "" end, DecodeShape = function() end,
		DrawPreview = function() end, RequestOpen = function() end, KINDS = { "box", "sphere", "cylinder", "cone" },
		IsForgeReady = function() return false end, templates = {}, rev = 0, Bump = function() end,
		TemplateIds = function() return {} end, SetTemplate = function() end, DelTemplate = function() end,
		Price = function() return nil end, SafeId = function(s) return tostring(s) end, QueueReady = function() return false end,
		QueueAddSpec = function() return false end, ReadQueue = function() return {}, {} end }
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local vsx, vsy = Spring.GetViewGeometry()
local px, py = 40, 120                 -- bottom left corner of the panel in screen pixels
local pw, ph = 520, 640                -- size of the panel in pixels (the corner handle changes it)
local scale = 1.0                      -- zoom of the contents (A- / A+)
local closed, minimized = true, false  -- the forge starts closed; the [+] tile of the build panel opens it
local MIN_W, MIN_H, MAX_W, MAX_H = 380, 360, 1200, 1100
local MIN_SCALE, MAX_SCALE = 0.7, 2.0

local TABS = { { "BASE", "base" }, { "NUMBERS", "nums" }, { "IMAGE", "img" }, { "SHAPE", "shape" } }
local tab = "base"
local scroll = { base = 0, nums = 0, img = 0, shape = 0 }   -- scroll offset of every tab (pixels)
local contentH = { base = 0, nums = 0, img = 0, shape = 0 }

-- the unit being designed
local spec = {
	id = "custom", base = "", png = "",
	hp = 0, metal = 0, energy = 0, buildtime = 0, sight = 0,
	speed = 1, range = 1, dmg = 1, reload = 1, alt = 0,
	count = 1, pngsize = 120,
}
local stances = { fire = 0, move = 0, ["repeat"] = 0 }
local shape = {}                -- list of primitives
local selPrim = 0               -- index of the selected primitive (0 = none)
local selPng = nil
local status = "ready"
local drag, scaling, dragSlider = nil, nil, nil
local editingId, loadIdx = false, 0

local function Snd(name, vol) Spring.PlaySoundFile("sounds/" .. name .. ".wav", vol or 0.7, "ui") end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function Inside(x, y, r) return r ~= nil and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end
local function Num(v, dec)
	v = tonumber(v) or 0
	if dec then return string.format("%." .. dec .. "f", v) end
	if math.abs(v - math.floor(v + 0.5)) < 0.001 then return string.format("%d", math.floor(v + 0.5)) end
	return string.format("%.2f", v)
end
local function Text(str, x, y, size, r, g, b, a) VBFont.Text(str, x, y, size, "o", r, g, b, a or 1) end

local GOLD = { 0.85, 0.65, 0.2 }

--------------------------------------------------------------------------------
-- the units that can be used as a base
--------------------------------------------------------------------------------
-- NB: Spring.GetActiveCmdDescs() only lists what the CURRENT SELECTION can build, so it is
-- empty while nothing is selected.  The forge lists the unit defs themselves instead.
local unitItems
local function UnitItems()
	if unitItems then return unitItems end
	local list, any = {}, false
	for id, ud in pairs(UnitDefs) do
		if type(id) == "number" and ud.customParams and ud.customParams.faction then any = true; break end
	end
	for id, ud in pairs(UnitDefs) do
		if type(id) == "number" and (not any or (ud.customParams and ud.customParams.faction)) then
			list[#list + 1] = { id = id, name = ud.name, texture = "#" .. id, label = ud.name:sub(1, 4),
				tip = (ud.humanName or ud.name) .. "  (" .. ud.name .. ")" }
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	unitItems = list
	return list
end

local pngItems
local function PngItems()
	if pngItems then return pngItems end
	pngItems = {}
	for _, p in ipairs(Forge.PngList()) do
		pngItems[#pngItems + 1] = { name = p, label = p:sub(1, 3), texture = Forge.PngPath(p), tip = p }
	end
	return pngItems
end

--------------------------------------------------------------------------------
-- the parameter list (label, key, min, max, step, decimals, suffix)
--------------------------------------------------------------------------------
local PARAMS = {
	{ "HEALTH", "hp", 0, 20000, 100, 0, "keep base" },
	{ "METAL", "metal", 0, 2000, 10, 0, "keep base" },
	{ "ENERGY", "energy", 0, 2000, 10, 0, "keep base" },
	{ "BUILD TIME", "buildtime", 0, 600, 5, 0, "keep base" },
	{ "SIGHT", "sight", 0, 3000, 25, 0, "keep base" },
	{ "SPEED", "speed", 0.1, 8, 0.05, 2, "x" },
	{ "RANGE", "range", 0.1, 8, 0.05, 2, "x" },
	{ "DAMAGE", "dmg", 0.1, 20, 0.05, 2, "x" },
	{ "RELOAD", "reload", 0.05, 8, 0.05, 2, "x" },
	{ "ALTITUDE", "alt", 0, 800, 10, 0, "keep base" },
	{ "COUNT", "count", 1, 50, 1, 0, "" },
	{ "IMAGE SIZE", "pngsize", 0, 400, 5, 0, "off" },
}
-- a value of 0 means "keep the base unit's number"; the label says so
local ZERO_TEXT = { hp = "keep base", metal = "keep base", energy = "keep base", buildtime = "keep base",
	sight = "keep base", alt = "keep base", pngsize = "off" }
local NUM_KEYS = { hp = true, metal = true, energy = true, buildtime = true, sight = true, speed = true,
	range = true, dmg = true, reload = true, alt = true, count = true, pngsize = true }

--------------------------------------------------------------------------------
-- immediate mode widgets.  Everything is laid out TOP DOWN: an element is given the y of
-- its top edge and gives back the height it used.  (Screen y grows upwards.)
--------------------------------------------------------------------------------
local s = 1.0                                   -- current scale, set at the start of every frame
local rects = {}
local panelBox, contentBox
local clipTop, clipBot = 0, 0                   -- vertical range of the tab content that is really visible
local curContent = false                        -- are we drawing inside the scrolling tab area?
local mouseX, mouseY = 0, 0
local tip                                       -- tooltip text of the icon under the mouse

local function Add(r) r.c = curContent; rects[#rects + 1] = r; return r end

-- applies a slider value to the spec or to the selected primitive
local function ApplySlider(key, value)
	if NUM_KEYS[key] then spec[key] = value return true end
	local p = shape[selPrim]
	if not p then return false end
	if key == "sizex" then p.size[1] = value
	elseif key == "sizey" then p.size[2] = value
	elseif key == "sizez" then p.size[3] = value
	elseif key == "posx" then p.pos[1] = value
	elseif key == "posy" then p.pos[2] = value
	elseif key == "posz" then p.pos[3] = value
	elseif key == "rotx" then p.rot[1] = value
	elseif key == "roty" then p.rot[2] = value
	elseif key == "rotz" then p.rot[3] = value
	elseif key == "tex" then p.tex = math.floor(value + 0.5)
	elseif key == "cr" then p.color[1] = value
	elseif key == "cg" then p.color[2] = value
	elseif key == "cb" then p.color[3] = value
	elseif key == "uvw" then p.uv[3] = math.min(1, p.uv[1] + value / 100)
	elseif key == "uvh" then p.uv[4] = math.min(1, p.uv[2] + value / 100)
	elseif key == "uvx" then
		local w = p.uv[3] - p.uv[1]
		p.uv[1] = math.min(value / 100, 1 - w)
		p.uv[3] = p.uv[1] + w
	else return false end
	return true
end

-- turns a mouse position into a slider value and applies it
local function SliderTo(d, x)
	local sl = d.s
	local t = Clamp((x - d.x1) / math.max(1, d.w), 0, 1)
	local v = sl.min + t * (sl.max - sl.min)
	if sl.step and sl.step > 0 then v = math.floor(v / sl.step + 0.5) * sl.step end
	ApplySlider(d.key, Clamp(v, sl.min, sl.max))
end

-- horizontal slider, 30 px high.  Returns the height used.
local function Slider(x, yTop, w, label, value, min, max, step, decimals, suffix, key)
	local h = 30 * s
	local barY = yTop - 25 * s
	Text(label, x, yTop - 11 * s, 10 * s, 0.62, 0.62, 0.72)
	local txt
	if value == 0 and ZERO_TEXT[key] then txt = ZERO_TEXT[key] else txt = Num(value, decimals) .. (suffix or "") end
	Text(txt, x + w - VBFont.Width(txt, 10 * s), yTop - 11 * s, 10 * s, 0.95, 0.85, 0.55)
	Box(x, barY, x + w, barY + 4 * s, 0.14, 0.14, 0.2, 1)
	local t = Clamp((value - min) / (max - min), 0, 1)
	Box(x, barY, x + w * t, barY + 4 * s, 0.35, 0.75, 1.0, 0.85)
	Box(x + w * t - 2 * s, barY - 3 * s, x + w * t + 2 * s, barY + 7 * s, 0.45, 0.9, 1.0, 1)
	Add { x, yTop - h, x + w, yTop, slider = { min = min, max = max, step = step, key = key } }
	return h
end

-- toggle button with a state led
local function Toggle(x, yTop, w, h, label, on, key, onCol)
	local y = yTop - h
	Box(x, y, x + w, yTop, on and 0.18 or 0.12, on and 0.18 or 0.12, on and 0.28 or 0.2, 1)
	Frame(x, y, x + w, yTop, GOLD[1], GOLD[2], GOLD[3], on and 0.9 or 0.35)
	local c = onCol or { 0.2, 0.95, 0.35 }
	Box(x + 4 * s, y + h / 2 - 3 * s, x + 10 * s, y + h / 2 + 3 * s, on and c[1] or 0.25, on and c[2] or 0.25, on and c[3] or 0.3, 1)
	local v = on and 1 or 0.6
	Text(label, x + 14 * s, y + h * 0.3, 9 * s, v, v, v)
	Add { x, y, x + w, yTop, toggle = { key = key } }
	return h
end

-- plain action button, label centred
local function Button(x, yTop, w, h, label, action, col)
	local y = yTop - h
	local over = Inside(mouseX, mouseY, { x, y, x + w, yTop }) and (not curContent or Inside(mouseX, mouseY, contentBox))
	Box(x, y, x + w, yTop, over and 0.22 or 0.16, over and 0.22 or 0.16, over and 0.32 or 0.24, 1)
	Frame(x, y, x + w, yTop, col and col[1] or GOLD[1], col and col[2] or GOLD[2], col and col[3] or GOLD[3], over and 1 or 0.75)
	Text(label, x + (w - VBFont.Width(label, 10 * s)) / 2, y + h * 0.3, 10 * s, 0.95, 0.9, 0.8)
	Add { x, y, x + w, yTop, button = { action = action } }
	return h
end

-- grid of icons (unit defs or png files); returns the height of the whole grid.  Rows that are
-- scrolled out of sight are skipped.
local function IconGrid(x, yTop, w, items, size, isSel)
	local gap = 4 * s
	local cols = math.max(1, math.floor((w + gap) / (size + gap)))
	local rows = math.ceil(#items / cols)
	local first = math.max(0, math.floor((yTop - clipTop) / (size + gap)))
	local last = math.min(rows - 1, math.ceil((yTop - clipBot) / (size + gap)))
	for row = first, last do
		for col = 0, cols - 1 do
			local it = items[row * cols + col + 1]
			if not it then break end
			local ix, iy = x + col * (size + gap), yTop - row * (size + gap) - size
			if it.texture then
				gl.Color(1, 1, 1, 1); gl.Texture(it.texture); gl.TexRect(ix, iy, ix + size, iy + size); gl.Texture(false)
			else
				Box(ix, iy, ix + size, iy + size, 0.2, 0.2, 0.28, 1)
				Text(it.label or "?", ix + 2, iy + size / 2 - 4 * s, 8 * s, 0.8, 0.8, 0.9)
			end
			if isSel(it) then Frame(ix, iy, ix + size, iy + size, 0.35, 0.95, 1, 1)
			else Frame(ix, iy, ix + size, iy + size, 0.5, 0.5, 0.6, 0.6) end
			Add { ix, iy, ix + size, iy + size, icon = it }
			if tip == nil and it.tip and Inside(mouseX, mouseY, { ix, iy, ix + size, iy + size }) and Inside(mouseX, mouseY, contentBox) then
				tip = it.tip
			end
		end
	end
	return rows * (size + gap)
end

--------------------------------------------------------------------------------
-- creating, spawning, saving
--------------------------------------------------------------------------------
local function BuildSpec()
	local t = {}
	for k in pairs(NUM_KEYS) do
		if k ~= "pngsize" then t[k] = spec[k] end
	end
	if spec.pngsize > 0 then t.pngsize = spec.pngsize end
	t.id = Forge.SafeId(spec.id)
	if t.id == "" then t.id = "custom" end
	t.base = spec.base
	t.team = Spring.GetMyTeamID()
	if spec.png and spec.png ~= "" then t.png = spec.png end
	if #shape > 0 then t.shape = Forge.EncodeShape(shape) end
	if stances.fire ~= 0 then t.fire = stances.fire end
	if stances.move ~= 0 then t.move = stances.move end
	if stances["repeat"] ~= 0 then t["repeat"] = stances["repeat"] end
	return t
end

local function BaseOk()
	if not spec.base or spec.base == "" or not UnitDefNames[spec.base] then
		status = "pick a base unit first (BASE tab)"; Snd("ui_close", 0.5)
		return false
	end
	return true
end

local function Report(queued, n, id)
	if queued then status = "queued " .. n .. " x " .. id .. "  (see the build panel)"
	else status = "queue gadget missing: created " .. n .. " x " .. id .. " instantly and for free" end
end

local function CreateUnit()
	if not BaseOk() then return end
	local t = BuildSpec()
	spec.id = t.id
	Forge.SetTemplate(t.id, t)                 -- creating also saves: the design is now in the build panel
	local n = math.max(1, math.floor(spec.count + 0.5))
	Report(Forge.QueueAddSpec(t, n), n, t.id)
	Snd("ui_select")
end

local function SpawnMore()
	local id = Forge.SafeId(spec.id)
	local t = Forge.templates[id]
	if not t then status = "no saved design '" .. id .. "' (SAVE or CREATE it first)"; Snd("ui_close", 0.5) return end
	local n = math.max(1, math.floor(spec.count + 0.5))
	Report(Forge.QueueAddSpec(t, n), n, id)
	Snd("ui_select")
end

local function SaveTemplate()
	if not BaseOk() then return end
	local t = BuildSpec()
	spec.id = t.id
	Forge.SetTemplate(t.id, t)
	status = "saved '" .. t.id .. "' - it is in the build panel for this game"
	Snd("ui_click")
end

local function LoadTemplate(id)
	local t = Forge.templates[id]
	if not t then return end
	for k in pairs(NUM_KEYS) do
		if t[k] ~= nil then spec[k] = t[k] end
	end
	if t.pngsize == nil then spec.pngsize = 0 end
	spec.id, spec.base, spec.png = id, t.base or spec.base, t.png or ""
	selPng = t.png
	stances.fire, stances.move, stances["repeat"] = t.fire or 0, t.move or 0, t["repeat"] or 0
	local dec = t.shape and Forge.DecodeShape(t.shape)
	shape = dec or {}
	selPrim = #shape > 0 and 1 or 0
	status = "loaded '" .. id .. "'"
	Snd("ui_open")
end

--------------------------------------------------------------------------------
-- the tabs.  Each one is drawn from the top of the content area downwards and returns the
-- height it needs, which is what the scrolling is based on.
--------------------------------------------------------------------------------
local function DrawBase(x, yTop, w)
	local y = yTop
	Text("BASE UNIT", x, y - 11 * s, 11 * s, GOLD[1], GOLD[2], GOLD[3])
	Text("the unit your design is built on", x + VBFont.Width("BASE UNIT", 11 * s) + 10 * s, y - 11 * s, 9 * s, 0.55, 0.58, 0.65)
	y = y - 18 * s
	local ud = spec.base ~= "" and UnitDefNames[spec.base] or nil
	Box(x, y - 36 * s, x + w, y, 0.12, 0.12, 0.18, 1)
	Text("base: " .. (ud and (ud.humanName or ud.name) or "(none picked)"), x + 6 * s, y - 15 * s, 10 * s, 0.95, 0.9, 0.7)
	if ud then
		Text(string.format("hp %s   metal %s   energy %s   speed %s", Num(ud.health or 0), Num(ud.metalCost or 0), Num(ud.energyCost or 0), Num(ud.speed or 0, 1)),
			x + 6 * s, y - 29 * s, 8 * s, 0.5, 0.55, 0.62)
	end
	y = y - 42 * s
	local gh = IconGrid(x, y, w, UnitItems(), 36 * s, function(it) return it.name == spec.base end)
	return (yTop - y) + gh
end

local function DrawNums(x, yTop, w)
	local half = (w - 12 * s) / 2
	local rowH = 34 * s
	for i, p in ipairs(PARAMS) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		Slider(x + col * (half + 12 * s), yTop - row * rowH, half, p[1], spec[p[2]] or 0, p[3], p[4], p[5], p[6], p[7], p[2])
	end
	local y = yTop - math.ceil(#PARAMS / 2) * rowH - 6 * s
	Text("STARTING STANCE", x, y - 11 * s, 11 * s, GOLD[1], GOLD[2], GOLD[3])
	y = y - 18 * s
	local bw = (w - 12 * s) / 3
	local th = 22 * s
	Toggle(x, y, bw, th, "FIRE " .. ({ "RETURN", "HOLD", "ALWAYS" })[stances.fire + 1], stances.fire ~= 0, "fire", { 1, 0.5, 0.2 })
	Toggle(x + bw + 6 * s, y, bw, th, "MOVE " .. ({ "LAND", "AIR" })[stances.move + 1], stances.move ~= 0, "move", { 0.3, 0.6, 1 })
	Toggle(x + (bw + 6 * s) * 2, y, bw, th, "REPEAT " .. (stances["repeat"] ~= 0 and "ON" or "OFF"), stances["repeat"] ~= 0, "repeat", { 0.2, 0.95, 0.35 })
	y = y - th - 6 * s
	return yTop - y
end

local function DrawImage(x, yTop, w)
	local y = yTop
	Text("IMAGE (PNG)", x, y - 11 * s, 11 * s, GOLD[1], GOLD[2], GOLD[3])
	Text("shown above the unit and mapped onto the 3D shape", x + VBFont.Width("IMAGE (PNG)", 11 * s) + 10 * s, y - 11 * s, 9 * s, 0.55, 0.58, 0.65)
	y = y - 18 * s
	-- the chosen picture, its name and the size slider come first so they never scroll away
	local pv = 64 * s
	Box(x, y - pv, x + pv, y, 0.08, 0.08, 0.12, 1)
	Frame(x, y - pv, x + pv, y, GOLD[1], GOLD[2], GOLD[3], 0.6)
	local path = selPng and Forge.PngPath(selPng)
	if path then
		gl.Color(1, 1, 1, 1); gl.Texture(path); gl.TexRect(x + 2, y - pv + 2, x + pv - 2, y - 2); gl.Texture(false)
	end
	Text(selPng or "no image picked", x + pv + 10 * s, y - 12 * s, 10 * s, 0.95, 0.9, 0.7)
	Slider(x + pv + 10 * s, y - 20 * s, w - pv - 10 * s, "SIZE (elmos)", spec.pngsize, 0, 400, 5, 0, "", "pngsize")
	y = y - pv - 8 * s
	local items = PngItems()
	Text("pick a picture  (" .. #items .. " available)", x, y - 10 * s, 9 * s, 0.55, 0.58, 0.65)
	y = y - 16 * s
	local gh = IconGrid(x, y, w, items, 32 * s, function(it) return it.name == selPng end)
	return (yTop - y) + gh
end

local function DrawShape(x, yTop, w)
	local y = yTop
	Text("3D SHAPE", x, y - 11 * s, 11 * s, GOLD[1], GOLD[2], GOLD[3])
	Text("primitives, then map the png onto them", x + VBFont.Width("3D SHAPE", 11 * s) + 10 * s, y - 11 * s, 9 * s, 0.55, 0.58, 0.65)
	y = y - 18 * s
	local pvS = 112 * s
	local lw = w - pvS - 8 * s                  -- width of the left column
	-- left column: add buttons, delete / clear, the list of primitives
	local ly = y
	local bw = (lw - 3 * 4 * s) / 4
	for i, kind in ipairs(Forge.KINDS) do
		Button(x + (i - 1) * (bw + 4 * s), ly, bw, 20 * s, string.upper(kind:sub(1, 4)), "add:" .. kind)
	end
	ly = ly - 24 * s
	local hw = (lw - 4 * s) / 2
	Button(x, ly, hw, 20 * s, "DELETE", "delprim", { 1, 0.5, 0.4 })
	Button(x + hw + 4 * s, ly, hw, 20 * s, "CLEAR ALL", "clearshape", { 1, 0.5, 0.4 })
	ly = ly - 26 * s
	local chipW = (lw - 2 * 4 * s) / 3
	for i, p in ipairs(shape) do
		local cx = x + ((i - 1) % 3) * (chipW + 4 * s)
		local cy = ly - math.floor((i - 1) / 3) * 20 * s
		local sel = (i == selPrim)
		Box(cx, cy - 18 * s, cx + chipW, cy, sel and 0.2 or 0.14, sel and 0.28 or 0.14, sel and 0.38 or 0.2, 1)
		if sel then Frame(cx, cy - 18 * s, cx + chipW, cy, 0.35, 0.95, 1, 0.9) end
		Text(i .. ". " .. p.type, cx + 4 * s, cy - 13 * s, 9 * s, sel and 0.45 or 0.6, sel and 0.95 or 0.6, sel and 1 or 0.6)
		Add { cx, cy - 18 * s, cx + chipW, cy, prim = i }
	end
	ly = ly - math.ceil(math.max(#shape, 1) / 3) * 20 * s
	-- right column: the preview
	local vx, vy = x + lw + 8 * s, y
	Box(vx, vy - pvS, vx + pvS, vy, 0.06, 0.07, 0.11, 1)
	Frame(vx, vy - pvS, vx + pvS, vy, GOLD[1], GOLD[2], GOLD[3], 0.55)
	if #shape > 0 then
		Forge.DrawPreview(shape, vx + 6 * s, vy - pvS + 6 * s, pvS - 12 * s, pvS - 12 * s, 35, 25)
	else
		Text("no shape yet", vx + 20 * s, vy - pvS / 2, 9 * s, 0.45, 0.48, 0.55)
	end
	y = math.min(ly, vy - pvS) - 10 * s
	-- properties of the selected primitive, two columns
	local p = shape[selPrim]
	if p then
		Text("PRIMITIVE " .. selPrim .. "  (" .. p.type .. ")", x, y - 10 * s, 10 * s, GOLD[1], GOLD[2], GOLD[3])
		y = y - 16 * s
		local half = (w - 12 * s) / 2
		local rowH = 34 * s
		local x2 = x + half + 12 * s
		local list = Forge.PngList()
		local texName = "none"
		if (p.tex or -1) >= 0 then texName = list[(p.tex or 0) + 1] or "?" end
		local rows = {
			{ { "SIZE X", p.size[1], 1, 400, 1, 0, "", "sizex" }, { "SIZE Y", p.size[2], 1, 400, 1, 0, "", "sizey" } },
			{ { "SIZE Z", p.size[3], 1, 400, 1, 0, "", "sizez" }, { "POS X", p.pos[1], -400, 400, 1, 0, "", "posx" } },
			{ { "POS Y", p.pos[2], -400, 400, 1, 0, "", "posy" }, { "POS Z", p.pos[3], -400, 400, 1, 0, "", "posz" } },
			{ { "ROT X", p.rot[1], -180, 180, 5, 0, "", "rotx" }, { "ROT Y", p.rot[2], -180, 180, 5, 0, "", "roty" } },
			{ { "ROT Z", p.rot[3], -180, 180, 5, 0, "", "rotz" }, { "TEXTURE  " .. texName, p.tex or -1, -1, #list, 1, 0, "", "tex" } },
			{ { "COL R", p.color[1], 0, 1, 0.02, 2, "", "cr" }, { "COL G", p.color[2], 0, 1, 0.02, 2, "", "cg" } },
			{ { "COL B", p.color[3], 0, 1, 0.02, 2, "", "cb" }, { "UV W", (p.uv[3] - p.uv[1]) * 100, 1, 100, 1, 0, "%", "uvw" } },
			{ { "UV H", (p.uv[4] - p.uv[2]) * 100, 1, 100, 1, 0, "%", "uvh" }, { "UV X", p.uv[1] * 100, 0, 99, 1, 0, "%", "uvx" } },
		}
		for _, row in ipairs(rows) do
			local a, b = row[1], row[2]
			Slider(x, y, half, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8])
			Slider(x2, y, half, b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
			y = y - rowH
		end
	else
		Text("select a primitive to edit it", x, y - 12 * s, 9 * s, 0.45, 0.48, 0.55)
		y = y - 20 * s
	end
	return yTop - y
end

--------------------------------------------------------------------------------
-- the widget
--------------------------------------------------------------------------------
local TITLE, TABH, FOOT = 24, 22, 96

function widget:Initialize()
	Spring.Echo("[VB] Unit forge loaded: /vbforge or the [+] tile of the build panel opens it")
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbforge", function() closed = not closed return true end, nil, "t")
	end
	-- let the other widgets (the build panel) open this one
	Forge.open = function()
		closed = false
		pw, ph = math.min(pw, vsx - 20), math.min(ph, vsy - 20)
		px = Clamp(px, 10, math.max(10, vsx - pw - 10))
		py = Clamp(py, 10, math.max(10, vsy - ph - 10))
		return true
	end
	if WG then WG.VBForge = Forge end
	if spec.base == "" or not UnitDefNames[spec.base] then
		local items = UnitItems()
		if items[1] then spec.base = items[1].name end
	end
	if #shape == 0 then
		shape = { { type = "box", size = { 40, 40, 40 }, pos = { 0, 20, 0 }, rot = { 0, 0, 0 },
			color = { 0.75, 0.8, 0.9, 1 }, tex = 0, uv = { 0, 0, 1, 1 } } }
		selPrim = 1
	end
end

function widget:Shutdown()
	Forge.open = nil
	if WG and WG.VBForge == Forge then WG.VBForge = nil end
end

function widget:TextCommand(cmd)
	if cmd == "vbforge" then closed = not closed return true end
	-- /vbcreate from the chat fills the id of the forge
	local id = cmd:match("^vbcreate%s+(%S+)")
	if id then spec.id = Forge.SafeId(id); status = "id set to " .. spec.id end
end

-- NB: the templates are NOT saved here: saved designs live for this game only.
function widget:GetConfigData()
	local sp = {}
	for k, v in pairs(spec) do sp[k] = v end
	return { px = px, py = py, pw = pw, ph = ph, scale = scale, minimized = minimized, tab = tab,
		spec = sp, stances = stances, shape = shape, selPrim = selPrim }
end

function widget:SetConfigData(d)
	if not d then return end
	if d.px then px, py = d.px, d.py end
	if d.pw then pw = d.pw end
	if d.ph then ph = d.ph end
	if d.scale then scale = Clamp(d.scale, MIN_SCALE, MAX_SCALE) end
	if d.minimized ~= nil then minimized = d.minimized end
	if d.tab then tab = d.tab end
	if type(d.spec) == "table" then
		for k, v in pairs(d.spec) do if k ~= "team" then spec[k] = v end end
		if spec.png ~= "" then selPng = spec.png end
	end
	if type(d.stances) == "table" then
		for k, v in pairs(d.stances) do stances[k] = v end
	end
	if type(d.shape) == "table" and #d.shape > 0 then
		shape = d.shape
		selPrim = d.selPrim or 1
	end
end

function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:Update()
	-- another widget (the build panel) asked for the forge to open / to edit a saved unit
	if Forge.openRequest then
		Forge.openRequest = false
		if Forge.open then Forge.open() end
	end
	if Forge.loadRequest then
		local id = Forge.loadRequest
		Forge.loadRequest = nil
		LoadTemplate(id)
		closed = false
	end
end

local function TitleButton(x, y, size, kind, over)
	local r, g, b = 0.22, 0.2, 0.3
	if kind == "close" then r, g, b = over and 0.7 or 0.4, 0.1, 0.1
	elseif over then r, g, b = 0.32, 0.3, 0.42 end
	Box(x, y, x + size, y + size, r, g, b, 1)
	local cx, cy = x + size / 2, y + size / 2
	gl.Color(1, 1, 1, 1)
	if kind == "min" then gl.Rect(cx - size * 0.28, cy - 1, cx + size * 0.28, cy + 1)
	elseif kind == "restore" then Frame(cx - size * 0.26, cy - size * 0.22, cx + size * 0.26, cy + size * 0.22, 1, 1, 1, 1)
	else
		local label = (kind == "close") and "x" or (kind == "zin" and "A+" or "A-")
		local fs = (kind == "close") and 12 or 9
		VBFont.Text(label, cx - VBFont.Width(label, fs) / 2, cy - fs * 0.35, fs, "o", 1, 1, 1, 1)
	end
end

function widget:DrawScreen()
	rects, panelBox, contentBox, tip = {}, nil, nil, nil
	curContent = false
	if closed then return end
	s = scale
	mouseX, mouseY = Spring.GetMouseState()

	pw, ph = Clamp(pw, MIN_W, math.min(MAX_W, vsx)), Clamp(ph, MIN_H, math.min(MAX_H, vsy))
	if scaling then py = scaling.top - ph end
	px = Clamp(px, 0, math.max(0, vsx - pw))
	local titleH = TITLE * s
	-- the panel is anchored at its top edge, so that minimizing keeps the title bar where it is
	local top = Clamp(py + ph, titleH, vsy)
	py = top - ph
	local x1, x2, y2 = px, px + pw, top
	local y1 = minimized and (y2 - titleH) or py
	panelBox = { x = x1, y = y1, w = pw, h = y2 - y1 }

	-- frame + title bar
	Box(x1, y1, x2, y2, 0.05, 0.05, 0.09, 0.94)
	Frame(x1, y1, x2, y2, GOLD[1], GOLD[2], GOLD[3], 0.9)
	Box(x1, y2 - titleH, x2, y2, 0.14, 0.12, 0.2, 1)
	Text("VOIDBORN UNIT FORGE", x1 + 8 * s, y2 - titleH + titleH * 0.3, 12 * s, 0.9, 0.85, 0.7)
	-- buttons, from the right: close, minimize, zoom in, zoom out.  Registered BEFORE the drag area.
	local bs = titleH
	local btns = {
		{ "close", x2 - bs }, { minimized and "restore" or "min", x2 - 2 * bs },
		{ "zin", x2 - 3 * bs }, { "zout", x2 - 4 * bs },
	}
	for _, b in ipairs(btns) do
		local r = { b[2], y2 - bs, b[2] + bs, y2, titlebtn = b[1] }
		rects[#rects + 1] = r
		TitleButton(b[2], y2 - bs, bs, b[1], Inside(mouseX, mouseY, r))
	end
	rects[#rects + 1] = { x1, y2 - titleH, x2 - 4 * bs, y2, drag = true }
	if minimized then return end

	-- resize handle (bottom right corner), registered before the footer buttons
	local hs = 14 * s
	local hr = { x2 - hs, y1, x2, y1 + hs, resize = true }
	rects[#rects + 1] = hr
	gl.Color(GOLD[1], GOLD[2], GOLD[3], Inside(mouseX, mouseY, hr) and 1 or 0.7)
	for k = 1, 3 do gl.Rect(x2 - 2 - k * 3 * s, y1 + 2, x2 - 2, y1 + 2 + k * 3 * s - 2 * s) end

	-- tab bar
	local m = 8 * s
	local tabTop = y2 - titleH - 4 * s
	local tabH = TABH * s
	local tw = (pw - 2 * m) / #TABS
	for i, t in ipairs(TABS) do
		local tx = x1 + m + (i - 1) * tw
		local active = (tab == t[2])
		Box(tx, tabTop - tabH, tx + tw - 4, tabTop, active and 0.2 or 0.11, active and 0.18 or 0.11, active and 0.3 or 0.17, 1)
		if active then gl.Color(GOLD[1], GOLD[2], GOLD[3], 0.9); gl.Rect(tx, tabTop - tabH, tx + tw - 4, tabTop - tabH + 2) end
		Text(t[1], tx + (tw - 4 - VBFont.Width(t[1], 10 * s)) / 2, tabTop - tabH * 0.7, 10 * s,
			active and 1 or 0.55, active and 0.95 or 0.58, active and 0.7 or 0.62)
		rects[#rects + 1] = { tx, tabTop - tabH, tx + tw - 4, tabTop, tab = t[2] }
	end

	-- the scrolling content area
	local cx, cw = x1 + m, pw - 2 * m
	local cTop, cBot = tabTop - tabH - 8 * s, y1 + FOOT * s
	local visH = math.max(10, cTop - cBot)
	contentBox = { cx - 2, cBot, cx + cw + 2, cTop }
	clipTop, clipBot = cTop, cBot
	local maxScroll = math.max(0, contentH[tab] - visH)
	scroll[tab] = Clamp(scroll[tab], 0, maxScroll)
	local ch = cw - (maxScroll > 0 and 8 * s or 0)             -- leave room for the scroll bar
	gl.Scissor(math.floor(cx - 2), math.floor(cBot), math.ceil(cw + 4), math.ceil(visH))
	curContent = true
	local yTop = cTop + scroll[tab]
	local used = 0
	if tab == "base" then used = DrawBase(cx, yTop, ch)
	elseif tab == "nums" then used = DrawNums(cx, yTop, ch)
	elseif tab == "img" then used = DrawImage(cx, yTop, ch)
	elseif tab == "shape" then used = DrawShape(cx, yTop, ch) end
	curContent = false
	gl.Scissor(false)
	contentH[tab] = used
	if maxScroll > 0 then                                       -- scroll bar
		local th = math.max(16 * s, visH * visH / used)
		local ty = cTop - (visH - th) * (scroll[tab] / maxScroll)
		Box(cx + cw - 4 * s, cBot, cx + cw, cTop, 0.12, 0.12, 0.18, 1)
		Box(cx + cw - 4 * s, ty - th, cx + cw, ty, GOLD[1], GOLD[2], GOLD[3], 0.8)
	end

	-- footer, from the bottom up: actions, id, price, status
	gl.Color(GOLD[1], GOLD[2], GOLD[3], 0.5); gl.Rect(x1 + 6, cBot, x2 - 6, cBot + 1)
	local fw = pw - 2 * m - 16 * s                              -- keep clear of the resize handle
	local gap = 4 * s
	local bw = (fw - 3 * gap) / 4
	local ay = y1 + 6 * s + 22 * s
	Button(x1 + m, ay, bw, 22 * s, "SAVE", "save", { 1, 0.7, 0.3 })
	Button(x1 + m + (bw + gap), ay, bw, 22 * s, "LOAD", "load", { 0.4, 0.7, 1 })
	Button(x1 + m + (bw + gap) * 2, ay, bw, 22 * s, "CREATE", "create", { 0.3, 0.9, 0.45 })
	Button(x1 + m + (bw + gap) * 3, ay, bw, 22 * s, "SPAWN", "spawn", { 0.4, 0.8, 1 })
	-- the id field (click to rename)
	local iy = ay + 6 * s + 20 * s
	local idw = math.min(180 * s, fw)
	local idr = { x1 + m, iy - 20 * s, x1 + m + idw, iy, idfield = true }
	rects[#rects + 1] = idr
	Box(idr[1], idr[2], idr[3], idr[4], 0.1, 0.1, 0.16, 1)
	Frame(idr[1], idr[2], idr[3], idr[4], editingId and 0.35 or 0.5, editingId and 0.95 or 0.5, editingId and 1 or 0.6, 0.9)
	local idTxt = spec.id .. ((editingId and (math.floor(os.clock() * 2) % 2 == 0)) and "_" or "")
	Text(idTxt, idr[1] + 6 * s, idr[2] + 6 * s, 10 * s, 0.95, 0.9, 0.7)
	Text(editingId and "type a name, Enter to finish" or "click to rename", idr[3] + 8 * s, idr[2] + 6 * s, 9 * s, 0.5, 0.55, 0.62)
	-- price (what the queue really charges) and the state of the queue
	local price = Forge.Price(spec)
	local n = math.max(1, math.floor(spec.count + 0.5))
	local line = "pick a base unit"
	if price then
		line = string.format("%smetal %s   energy %s   time %ss", n > 1 and ("x" .. n .. ":  ") or "",
			Num(price.metal * n), Num(price.energy * n), Num(price.build * n))
		if (price.premium or 0) > 0 then line = line .. string.format("   (+%s for the extra power)", Num(price.premium * n)) end
	end
	Text(line, x1 + m, iy + 10 * s, 10 * s, 0.95, 0.8, 0.45)
	local q, order = Forge.ReadQueue()
	local qn = 0
	for _, id in ipairs(order) do qn = qn + q[id].n end
	local stat = (qn > 0 and ("queue: " .. qn .. " unit" .. (qn == 1 and "" or "s") .. "   ") or "") .. status
	Text(stat, x1 + m, iy + 26 * s, 9 * s, 0.55, 0.9, 0.65)

	-- tooltip of the icon under the mouse (drawn last, so it is not clipped)
	if tip then
		local tw2 = VBFont.Width(tip, 10 * s) + 10 * s
		local tx, ty = math.min(mouseX + 14, vsx - tw2 - 4), mouseY + 14
		Box(tx, ty - 3, tx + tw2, ty + 14 * s, 0.05, 0.05, 0.09, 0.95)
		Frame(tx, ty - 3, tx + tw2, ty + 14 * s, GOLD[1], GOLD[2], GOLD[3], 0.8)
		Text(tip, tx + 5 * s, ty, 10 * s, 1, 0.95, 0.7)
	end
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------
function widget:IsAbove(x, y)
	return not closed and panelBox ~= nil and x >= panelBox.x and x <= panelBox.x + panelBox.w
		and y >= panelBox.y and y <= panelBox.y + panelBox.h
end

local function Action(a)
	if a == "create" then CreateUnit()
	elseif a == "spawn" then SpawnMore()
	elseif a == "save" then SaveTemplate()
	elseif a == "load" then
		local ids = Forge.TemplateIds()
		if #ids == 0 then status = "nothing saved yet"; return end
		loadIdx = loadIdx % #ids + 1                 -- every click loads the next saved design
		LoadTemplate(ids[loadIdx])
		return
	elseif a == "delprim" then
		if shape[selPrim] then
			table.remove(shape, selPrim)
			selPrim = #shape > 0 and math.min(selPrim, #shape) or 0
		end
	elseif a == "clearshape" then shape = {}; selPrim = 0
	elseif a:sub(1, 4) == "add:" then
		local n = #shape + 1
		shape[n] = { type = a:sub(5), size = { 30, 30, 30 }, pos = { 0, 20 + (n - 1) * 12, 0 },
			rot = { 0, 0, 0 }, color = { 0.8, 0.85, 0.95, 1 }, tex = 0, uv = { 0, 0, 1, 1 } }
		selPrim = n
	end
	Snd("ui_click")
end

function widget:MousePress(x, y, button)
	if not widget:IsAbove(x, y) then
		if editingId then editingId = false end
		return false
	end
	local inContent = Inside(x, y, contentBox)
	for _, r in ipairs(rects) do
		if Inside(x, y, r) and (not r.c or inContent) then
			if r.titlebtn then
				local k = r.titlebtn
				if k == "close" then closed = true; editingId = false; Snd("ui_close")
				elseif k == "min" then minimized = true; editingId = false; Snd("ui_click")
				elseif k == "restore" then minimized = false; Snd("ui_open")
				elseif k == "zin" then scale = Clamp(scale + 0.1, MIN_SCALE, MAX_SCALE); Snd("ui_click")
				elseif k == "zout" then scale = Clamp(scale - 0.1, MIN_SCALE, MAX_SCALE); Snd("ui_click") end
				return true
			end
			if r.resize then scaling = { x0 = x, y0 = y, top = py + ph, w0 = pw, h0 = ph }; return true end
			if r.drag then drag = { x - px, y - py }; return true end
			if r.idfield then editingId = true; Snd("ui_click"); return true end
			editingId = false
			if r.tab then tab = r.tab; Snd("ui_click"); return true end
			if r.slider then
				dragSlider = { s = r.slider, x1 = r[1], w = r[3] - r[1], key = r.slider.key }
				SliderTo(dragSlider, x)
				return true
			end
			if r.toggle then
				local k = r.toggle.key
				if k == "fire" then stances.fire = (stances.fire + 1) % 3
				elseif k == "move" then stances.move = (stances.move + 1) % 2
				elseif k == "repeat" then stances["repeat"] = stances["repeat"] ~= 0 and 0 or 1 end
				Snd("ui_click")
				return true
			end
			if r.button then Action(r.button.action) return true end
			if r.prim then selPrim = r.prim; Snd("ui_click"); return true end
			if r.icon then
				if r.icon.id then
					spec.base = r.icon.name
					status = "base: " .. spec.base
				elseif r.icon.name then
					selPng = r.icon.name
					spec.png = r.icon.name
					for _, p in ipairs(shape) do p.tex = (p.tex and p.tex >= 0) and p.tex or 0 end
					status = "image: " .. r.icon.name
				end
				Snd("ui_select")
				return true
			end
		end
	end
	editingId = false
	return true
end

function widget:MouseMove(x, y, dx, dy)
	if drag then px, py = x - drag[1], y - drag[2]
	elseif scaling then
		pw = Clamp(scaling.w0 + (x - scaling.x0), MIN_W, math.min(MAX_W, vsx))
		ph = Clamp(scaling.h0 - (y - scaling.y0), MIN_H, math.min(MAX_H, vsy))
		py = scaling.top - ph                    -- the top edge stays where it is
	elseif dragSlider then
		SliderTo(dragSlider, x)
	end
end

function widget:MouseRelease() drag, scaling, dragSlider = nil, nil, nil end

function widget:MouseWheel(up, value)
	if closed or minimized or not contentBox then return false end
	local mx, my = Spring.GetMouseState()
	if not Inside(mx, my, contentBox) then return false end
	scroll[tab] = math.max(0, scroll[tab] + (up and -1 or 1) * 48 * s)    -- the next DrawScreen clamps it
	return true
end

-- typing in the id field
function widget:TextInput(ch)
	if not editingId then return false end
	if #spec.id < 24 and ch:match("^[%w_%-]$") then spec.id = spec.id .. ch end
	return true
end

function widget:KeyPress(key, mods, isRepeat)
	if not editingId then return false end
	if key == 8 then spec.id = spec.id:sub(1, -2)                            -- backspace
	elseif key == 13 or key == 271 or key == 27 then                         -- enter / keypad enter / escape
		spec.id = Forge.SafeId(spec.id)
		if spec.id == "" then spec.id = "custom" end
		editingId = false
	end
	return true        -- while typing, no other hotkey may fire
end
