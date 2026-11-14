-- Voidborn unit forge: the unit creation panel.
--
-- Pick a base unit, tune its numbers, design a brand new 3D shape and map a PNG
-- onto it, then create the unit (or stamp out more of it later with /vbspawn).
--
-- The panel is draggable (title bar) and resizeable (corner handle).  Everything
-- it does goes through the same wire format as /vbcreate, so the console and the
-- forge share one template store and one set of units.
--
--   /vbforge            open / close the panel
--   /vbcreate <id> ...  still works from the chat, and the forge picks it up
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
	Forge = { Ser = function() return "{}" end, PngList = function() return {} end,
		PngPath = function() end, EncodeShape = function() return "" end, DecodeShape = function() end,
		CopyShape = function() end, Mesh = function() return { verts = {}, tris = {} } end,
		DrawPreview = function() end, DrawShape = function() end, RequestOpen = function() end,
		IsForgeReady = function() return false end,
		templates = {}, rev = 0, Bump = function() end, TemplateIds = function() return {} end,
		SetTemplate = function() end, DelTemplate = function() end }
end
-- the price rules (the same file the LuaRules gadget uses)
local okC, Cost = pcall(VFS.Include, "LuaRules/Headers/vb_cost.h.lua")
if not okC or type(Cost) ~= "table" or type(Cost.Cost) ~= "function" then
	Cost = { Cost = function() return nil end }
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local vsx, vsy = Spring.GetViewGeometry()
local px, py = 40, 120                 -- top left corner in screen pixels
local pw, ph = 520, 640                -- the size of the panel (the corner handle changes it)
local scale = 1.0                      -- the zoom of the text and the widgets inside
local closed = false
local MIN_W, MIN_H, MAX_W, MAX_H = 380, 420, 1200, 1100

local TABS = { { "BASE", "base" }, { "NUMBERS", "nums" }, { "IMAGE", "img" }, { "SHAPE", "shape" } }
local tab = "base"

-- the unit being designed
local spec = {
	id = "custom", base = "ch_hoplite",
	hp = 0, metal = 0, energy = 0, buildtime = 0, sight = 0,
	speed = 1, range = 1, dmg = 1, reload = 1, alt = 0,
	count = 1, team = 0, pngsize = 120,
}
local stances = { fire = 0, move = 0, ["repeat"] = 0 }
local shape = {}            -- list of primitives
local selPrim = 1           -- index of the selected primitive (0 = none)
local selUnit, selPng = nil, nil
local status = "ready"
local drag, scaling, dragSlider = nil, nil, nil

local function Snd(name, vol) Spring.PlaySoundFile("sounds/" .. name .. ".wav", vol or 0.7, "ui") end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------
local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function Inside(x, y, r) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end
local function Num(v, dec)
	if dec then return string.format("%." .. dec .. "f", v) end
	if math.abs(v - math.floor(v + 0.5)) < 0.001 then return string.format("%d", math.floor(v + 0.5)) end
	return string.format("%.2f", v)
end

--------------------------------------------------------------------------------
-- the buildable units (from the engine's own command list)
--------------------------------------------------------------------------------
local unitList
local function Units()
	if unitList then return unitList end
	local seen, list = {}, {}
	local cmds = Spring.GetActiveCmdDescs() or {}
	for i = 1, #cmds do
		local c = cmds[i]
		if type(c) == "table" and c.id and c.id < 0 and UnitDefs[-c.id] then
			local defID = -c.id
			if not seen[defID] then
				seen[defID] = true
				list[#list + 1] = { id = defID, name = UnitDefs[defID].name, cmd = c }
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	unitList = list
	return list
end

--------------------------------------------------------------------------------
-- the parameter list (label, key, min, max, step, decimals)
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
	{ "TEAM", "team", 0, 10, 1, 0, "" },
	{ "IMAGE SIZE", "pngsize", 0, 400, 5, 0, "off" },
}
local NUM_KEYS = { hp = true, metal = true, energy = true, buildtime = true, sight = true, speed = true,
	range = true, dmg = true, reload = true, alt = true, count = true, team = true, pngsize = true }

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------
local rects = {}, panelBox

-- a horizontal slider; returns the rectangle it occupies
local function Slider(x, y, w, label, value, min, max, step, decimals, suffix, key)
	local h = 30
	local barY = y + 15
	VBFont.Text(label, x, y + 2, 10, "o", 0.62, 0.62, 0.72, 1)
	local txt = Num(value, decimals) .. (suffix or "")
	local tw = VBFont.Width(txt, 10)
	VBFont.Text(txt, x + w - tw, y + 2, 10, "or", 0.95, 0.85, 0.55, 1)
	-- the track
	Box(x, barY, x + w, barY + 4, 0.14, 0.14, 0.2, 1)
	local t = (value - min) / (max - min)
	t = Clamp(t, 0, 1)
	Box(x, barY, x + w * t, barY + 4, 0.35, 0.75, 1.0, 0.85)
	-- the handle
	local hx = x + w * t
	Box(hx - 2, barY - 3, hx + 2, barY + 7, 0.45, 0.9, 1.0, 1)
	rects[#rects + 1] = { x, y - 2, x + w, barY + 9, slider = { min = min, max = max, step = step, key = key } }
	return h
end

-- a toggle button with a state led
local function Toggle(x, y, w, h, label, on, key, onCol)
	Box(x, y, x + w, y + h, on and 0.18 or 0.12, on and 0.18 or 0.12, on and 0.28 or 0.2, 1)
	Frame(x, y, x + w, y + h, 0.85, 0.65, 0.2, on and 0.9 or 0.35)
	local c = onCol or { 0.2, 0.95, 0.35 }
	Box(x + 4, y + h / 2 - 4, x + 12, y + h / 2 + 4, on and c[1] or 0.25, on and c[2] or 0.25, on and c[3] or 0.3, 1)
	VBFont.Text(label, x + 16, y + h * 0.28, 9, "o", on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6, 1)
	rects[#rects + 1] = { x, y, x + w, y + h, toggle = { key = key } }
	return h
end

-- a plain action button
local function Button(x, y, w, h, label, action, col)
	Box(x, y, x + w, y + h, 0.16, 0.16, 0.24, 1)
	Frame(x, y, x + w, y + h, col and col[1] or 0.85, col and col[2] or 0.65, col and col[3] or 0.2, 0.8)
	VBFont.Text(label, x + (w - VBFont.Width(label, 10)) / 2, y + h * 0.28, 10, "oc", 0.95, 0.9, 0.8, 1)
	rects[#rects + 1] = { x, y, x + w, y + h, button = { action = action } }
	return h
end

-- a grid of icons (unit defs or png files)
local function IconGrid(x, y, w, h, items, cols, size, onPick)
	local gx, gy = x, y
	local rows = math.ceil(#items / cols)
	for i, it in ipairs(items) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local ix, iy = gx + col * (size + 4), gy + row * (size + 4)
		if iy + size > y + h then break end
		local r = { ix, iy, ix + size, iy + size, icon = it }
		rects[#rects + 1] = r
		local sel = (onPick.sel == it.id) or (onPick.sel == it.name)
		gl.Color(1, 1, 1, 1)
		if it.texture then
			gl.Texture(it.texture)
			gl.TexRect(ix, iy, ix + size, iy + size)
			gl.Texture(false)
		else
			Box(ix, iy, ix + size, iy + size, 0.2, 0.2, 0.28, 1)
			VBFont.Text(it.label or "?", ix + 2, iy + size / 2 - 5, 8, "o", 0.8, 0.8, 0.9, 1)
		end
		if sel then Frame(ix, iy, ix + size, iy + size, 0.35, 0.95, 1, 1)
		else Frame(ix, iy, ix + size, iy + size, 0.5, 0.5, 0.6, 0.6) end
	end
	return rows
end

--------------------------------------------------------------------------------
-- applying a slider value
--------------------------------------------------------------------------------
-- a slider can drive a number of the spec or a property of the selected primitive
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
	elseif key == "uvw" then
		local w = value / 100
		p.uv[3] = math.min(1, p.uv[1] + w)
	elseif key == "uvh" then
		local h = value / 100
		p.uv[4] = math.min(1, p.uv[2] + h)
	elseif key == "uvx" then
		local w = p.uv[3] - p.uv[1]
		p.uv[1] = math.min(value / 100, 1 - w)
		p.uv[3] = p.uv[1] + w
	else return false end
	return true
end

-- turns a mouse position into a slider value and applies it
local function SliderTo(d, x)
	local s = d.s
	local t = Clamp((x - d.x1) / math.max(1, d.w), 0, 1)
	local v = s.min + t * (s.max - s.min)
	if s.step and s.step > 0 then v = math.floor(v / s.step + 0.5) * s.step end
	v = Clamp(v, s.min, s.max)
	ApplySlider(d.key, v)
end

--------------------------------------------------------------------------------
-- building the spec that is sent to the gadget
--------------------------------------------------------------------------------
local function BuildSpec()
	local s = {}
	for k, v in pairs(spec) do
		if NUM_KEYS[k] and k ~= "count" and k ~= "team" and k ~= "pngsize" then s[k] = v end
	end
	s.count = spec.count
	s.team = spec.team
	if spec.pngsize > 0 then s.pngsize = spec.pngsize end
	s.id = spec.id
	s.base = spec.base
	if spec.png and spec.png ~= "" then s.png = spec.png end
	if #shape > 0 then s.shape = Forge.EncodeShape(shape) end
	if stances.fire ~= 0 then s.fire = stances.fire end
	if stances.move ~= 0 then s.move = stances.move end
	if stances["repeat"] ~= 0 then s["repeat"] = stances["repeat"] end
	return s
end

local function Send(s)
	Spring.SendLuaRulesMsg("vbdev:" .. Forge.Ser(s))
end

local function CreateUnit()
	if not spec.base or not UnitDefNames[spec.base] then
		status = "pick a base unit first"; Snd("ui_close", 0.5); return
	end
	local s = BuildSpec()
	Send(s)
	status = "created " .. tostring(spec.id)
	Forge.SetTemplate(spec.id, s)
	Snd("ui_select")
end

local function SpawnMore()
	local t = Forge.templates[spec.id]
	if not t then
		status = "no template '" .. spec.id .. "'"; Snd("ui_close", 0.5); return
	end
	local s = {}
	for k, v in pairs(t) do s[k] = v end
	s.count = spec.count
	Send(s)
	status = "spawned " .. tostring(spec.count) .. " x " .. tostring(spec.id)
	Snd("ui_select")
end

local function SaveTemplate()
	if not spec.id or spec.id == "" then status = "no template id"; return end
	Forge.SetTemplate(spec.id, BuildSpec())
	status = "saved template " .. spec.id
	Snd("ui_click")
end

local function LoadTemplate(id)
	local t = Forge.templates[id]
	if not t then return end
	for k, v in pairs(t) do
		if k ~= "x" and k ~= "z" then spec[k] = v end
	end
	if t.shape then
		local dec = Forge.DecodeShape(t.shape)
		shape = dec or {}
	end
	selPrim = #shape > 0 and 1 or 0
	selUnit = nil
	status = "loaded template " .. id
	Snd("ui_open")
end

--------------------------------------------------------------------------------
-- the price of the unit that is being designed
--------------------------------------------------------------------------------
-- The gadget LuaRules/Gadgets/vb_dev_units.lua puts the same price on the unit
-- when it is created, so what is shown here is what the unit really costs.
local function Price()
	local id = spec.base and UnitDefNames[spec.base]
	if not id then return nil end
	local ud = UnitDefs[id]
	if not ud then return nil end
	local s = {}
	for k, v in pairs(spec) do s[k] = v end
	if #shape > 0 then s.shape = Forge.EncodeShape(shape) end
	return Cost.Cost(s, ud)
end

--------------------------------------------------------------------------------
-- the panel
--------------------------------------------------------------------------------
local TITLE, TABH, FOOT = 24, 22, 54

local function DrawBase(x, y, w, h)
	local units = Units()
	VBFont.Text("BASE UNIT", x, y, 11, "o", 0.85, 0.65, 0.2, 1)
	local sub = "pick the unit to build on"
	VBFont.Text(sub, x + VBFont.Width("BASE UNIT", 11) + 10, y, 9, "o", 0.55, 0.58, 0.65, 1)
	-- the currently selected base
	local ud = spec.base and UnitDefNames[spec.base]
	Box(x, y + 14, x + w, y + 44, 0.12, 0.12, 0.18, 1)
	local baseName = ud and (ud.humanName or ud.name) or "(none)"
	VBFont.Text("base: " .. baseName, x + 6, y + 22, 10, "o", 0.95, 0.9, 0.7, 1)
	if ud then
		local info = string.format("hp %d  metal %d  speed %.1f", ud.health or 0, ud.metalCost or 0, ud.speed or 0)
		VBFont.Text(info, x + 6, y + 32, 8, "o", 0.5, 0.55, 0.62, 1)
	end
	-- the grid
	local gy = y + 50
	local size = 34
	local cols = math.max(1, math.floor((w - 8) / (size + 4)))
	local items = {}
	for _, u in ipairs(units) do
		-- the icon of a build command is the texture "#<unitdefid>"
		items[#items + 1] = { id = u.id, label = u.name:sub(1, 4), texture = "#" .. u.id }
	end
	local rows = IconGrid(x, gy, w, h - (gy - y) - 4, items, cols, size, { sel = selUnit })
	-- click on the grid picks the unit
	-- the name of the picked unit under the mouse
	local mx, my = Spring.GetMouseState()
	for _, r in ipairs(rects) do
		if r.icon and r.icon.id and Inside(mx, my, r) then
			local u = UnitDefs[r.icon.id]
			VBFont.Text(u and (u.humanName or u.name) or "", mx + 12, my + 12, 10, "o", 1, 0.95, 0.7, 1)
			break
		end
	end
end

local function DrawNums(x, y, w, h)
	-- two columns, so every number fits without scrolling
	local half = (w - 10) / 2
	local colW = half - 6
	local cy = y
	local rowH = 32
	for i, p in ipairs(PARAMS) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		Slider(x + col * (half + 4), y + row * rowH, colW, p[1], spec[p[2]] or 0, p[3], p[4], p[5], p[6], p[7], p[2])
	end
	cy = y + math.ceil(#PARAMS / 2) * rowH + 6
	-- stances
	VBFont.Text("STARTING STANCE", x, cy, 11, "o", 0.85, 0.65, 0.2, 1)
	cy = cy + 16
	local bw = (w - 24) / 3
	cy = cy + Toggle(x, cy, bw, 20, "FIRE " .. ({ "RETURN", "HOLD", "ALWAYS" })[stances.fire + 1], stances.fire ~= 0, "fire", { 1, 0.5, 0.2 }) + 4
	cy = cy + Toggle(x, cy, bw, 20, "MOVE " .. ({ "LAND", "AIR" })[stances.move + 1], stances.move ~= 0, "move", { 0.3, 0.6, 1 }) + 4
	cy = cy + Toggle(x, cy, bw, 20, "REPEAT " .. (stances["repeat"] ~= 0 and "ON" or "OFF"), stances["repeat"] ~= 0, "repeat", { 0.2, 0.95, 0.35 })
end

local function DrawImage(x, y, w, h)
	VBFont.Text("IMAGE (PNG)", x, y, 11, "o", 0.85, 0.65, 0.2, 1)
	VBFont.Text("shown above the unit, and mapped onto the 3D shape",
		x + VBFont.Width("IMAGE (PNG)", 11) + 10, y, 9, "o", 0.55, 0.58, 0.65, 1)
	local gy = y + 16
	local pngs = Forge.PngList()
	local size = 30
	local cols = math.max(1, math.floor((w - 8) / (size + 4)))
	local items = {}
	for _, p in ipairs(pngs) do
		items[#items + 1] = { name = p, label = p:sub(1, 3), texture = Forge.PngPath(p) }
	end
	IconGrid(x, gy, w, 120, items, cols, size, { sel = selPng })
	-- the mapped preview
	local px2, py2 = x, gy + 124
	Box(px2, py2, px2 + 64, py2 + 64, 0.08, 0.08, 0.12, 1)
	Frame(px2, py2, px2 + 64, py2 + 64, 0.85, 0.65, 0.2, 0.6)
	if selPng then
		local path = Forge.PngPath(selPng)
		if path then
			gl.Color(1, 1, 1, 1)
			gl.Texture(path)
			gl.TexRect(px2 + 2, py2 + 2, px2 + 62, py2 + 62)
			gl.Texture(false)
		end
	end
	VBFont.Text(selPng or "no image", px2 + 74, py2 + 6, 10, "o", 0.95, 0.9, 0.7, 1)
	VBFont.Text("size " .. Num(spec.pngsize) .. " elmos", px2 + 74, py2 + 20, 9, "o", 0.55, 0.58, 0.65, 1)
	Slider(px2 + 74, py2 + 28, w - 84, "SIZE", spec.pngsize, 0, 400, 5, 0, "", "pngsize")
	-- the mapping toggle
	VBFont.Text("MAP THE IMAGE ONTO THE SHAPE", px2, py2 + 72, 10, "o", 0.85, 0.65, 0.2, 1)
	-- (the shape tab owns the per-primitive mapping)
end

local function DrawShape(x, y, w, h)
	VBFont.Text("3D SHAPE", x, y, 11, "o", 0.85, 0.65, 0.2, 1)
	VBFont.Text("build the body out of primitives, then map the png onto them",
		x + VBFont.Width("3D SHAPE", 11) + 10, y, 9, "o", 0.55, 0.58, 0.65, 1)
	-- add buttons
	local by = y + 16
	local bw = (w - 12) / 4
	for i, kind in ipairs(Forge.KINDS) do
		Button(x + (i - 1) * (bw + 4), by, bw, 20, string.upper(kind:sub(1, 4)), "add:" .. kind)
	end
	by = by + 26
	-- the primitive list
	local listH = 62
	Box(x, by, x + w - 120, by + listH, 0.1, 0.1, 0.15, 1)
	local lx, ly = x + 4, by + 4
	for i, p in ipairs(shape) do
		local row = lx + ((i - 1) % 3) * ((w - 132) / 3)
		local ry = ly + math.floor((i - 1) / 3) * 18
		local label = i .. ". " .. p.type
		local sel = (i == selPrim)
		Box(row, ry, row + (w - 132) / 3 - 6, ry + 16, sel and 0.2 or 0.14, sel and 0.28 or 0.14, sel and 0.38 or 0.2, 1)
		VBFont.Text(label, row + 4, ry + 4, 9, "o", sel and 0.45 or 0.6, sel and 0.95 or 0.6, sel and 1 or 0.6, 1)
		rects[#rects + 1] = { row, ry, row + (w - 132) / 3 - 6, ry + 16, prim = i }
		if #shape > 6 then break end
	end
	-- delete
	Button(x + w - 116, by, 52, 20, "DELETE", "delprim")
	Button(x + w - 60, by, 56, 20, "CLEAR", "clearshape")
	-- the preview
	local pvX, pvY = x + w - 116, by + 26
	Box(pvX, pvY, pvX + 112, pvY + 112, 0.06, 0.07, 0.11, 1)
	Frame(pvX, pvY, pvX + 112, pvY + 112, 0.85, 0.65, 0.2, 0.55)
	if #shape > 0 then
		Forge.DrawPreview(shape, pvX + 6, pvY + 6, 100, 100, 35, 25)
	else
		VBFont.Text("no shape yet", pvX + 18, pvY + 50, 9, "o", 0.45, 0.48, 0.55, 1)
	end
	-- the properties of the selected primitive (two columns)
	local py3 = by + listH + 10
	if selPrim and shape[selPrim] then
		local p = shape[selPrim]
		VBFont.Text("PRIMITIVE " .. selPrim .. " (" .. p.type .. ")", x, py3, 10, "o", 0.85, 0.65, 0.2, 1)
		py3 = py3 + 14
		local half = (w - 16) / 2
		local colW = half - 6
		local rowH = 34
		-- size
		Slider(x, py3, colW, "SIZE X", p.size[1], 1, 400, 1, 0, "", "sizex")
		Slider(x + half + 4, py3, colW, "SIZE Y", p.size[2], 1, 400, 1, 0, "", "sizey")
		py3 = py3 + rowH
		Slider(x, py3, colW, "SIZE Z", p.size[3], 1, 400, 1, 0, "", "sizez")
		Slider(x + half + 4, py3, colW, "POS X", p.pos[1], -400, 400, 1, 0, "", "posx")
		py3 = py3 + rowH
		Slider(x, py3, colW, "POS Y", p.pos[2], -400, 400, 1, 0, "", "posy")
		Slider(x + half + 4, py3, colW, "POS Z", p.pos[3], -400, 400, 1, 0, "", "posz")
		py3 = py3 + rowH
		Slider(x, py3, colW, "ROT X", p.rot[1], -180, 180, 5, 0, "", "rotx")
		Slider(x + half + 4, py3, colW, "ROT Y", p.rot[2], -180, 180, 5, 0, "", "roty")
		py3 = py3 + rowH
		Slider(x, py3, colW, "ROT Z", p.rot[3], -180, 180, 5, 0, "", "rotz")
		-- the texture index walks through the pictures in unitpics/ and icons/
		local texMax = #Forge.PngList()
		Slider(x + half + 4, py3, colW, "TEXTURE", p.tex or -1, -1, texMax, 1, 0, "", "tex")
		-- which png the texture index points at
		local texName = "none"
		if (p.tex or -1) >= 0 then
			local list = Forge.PngList()
			texName = list[(p.tex or 0) + 1] or "?"
		end
		VBFont.Text("mapped: " .. texName, x + half + 4, py3 - 12, 8, "o", 0.5, 0.8, 0.95, 1)
		py3 = py3 + rowH
		Slider(x, py3, colW, "COL R", p.color[1], 0, 1, 0.02, 2, "", "cr")
		Slider(x + half + 4, py3, colW, "COL G", p.color[2], 0, 1, 0.02, 2, "", "cg")
		py3 = py3 + rowH
		Slider(x, py3, colW, "COL B", p.color[3], 0, 1, 0.02, 2, "", "cb")
		Slider(x + half + 4, py3, colW, "UV W", (p.uv[3] - p.uv[1]) * 100, 1, 100, 1, 0, "%", "uvw")
		py3 = py3 + rowH
		Slider(x, py3, colW, "UV H", (p.uv[4] - p.uv[2]) * 100, 1, 100, 1, 0, "%", "uvh")
		Slider(x + half + 4, py3, colW, "UV X", p.uv[1] * 100, 0, 99, 1, 0, "%", "uvx")
	else
		VBFont.Text("select a primitive to edit it", x, py3 + 4, 9, "o", 0.45, 0.48, 0.55, 1)
	end
end

--------------------------------------------------------------------------------
-- the widget
--------------------------------------------------------------------------------
function widget:Initialize()
	Spring.Echo("[VB] Unit forge loaded: drag the title bar, drag the corner to resize, /vbforge toggles it")
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbforge", function() closed = not closed return true end, nil, "t")
	end
	-- let the other widgets (the build panel) open this one
	Forge.open = function()
		closed = false
		-- put the panel where it can be seen
		px = math.max(10, math.min(vsx - pw - 20, px))
		py = math.max(10, math.min(vsy - ph - 20, py))
		if tab == "base" then
			-- start on the base unit, the forge is about making a unit
			tab = "base"
		end
		return true
	end
	-- start from a sensible base
	local units = Units()
	if units[1] then spec.base = UnitDefs[units[1].id].name end
	-- a default shape: a simple body
	shape = {
		{ type = "box", size = { 40, 40, 40 }, pos = { 0, 20, 0 }, rot = { 0, 0, 0 },
		  color = { 0.75, 0.8, 0.9, 1 }, tex = 0, uv = { 0, 0, 1, 1 } },
	}
	selPrim = 1
end

function widget:TextCommand(cmd)
	if cmd == "vbforge" then closed = not closed return true end
	-- /vbcreate from the chat fills the forge
	if cmd:sub(1, 2) == "vb" then
		local id = cmd:match("^vbcreate%s+(%S+)")
		if id then spec.id = id; status = "id set to " .. id end
	end
end

function widget:GetConfigData()
	return { px = px, py = py, pw = pw, ph = ph, scale = scale, closed = closed, tab = tab,
		spec = spec, stances = stances, shape = shape, selPrim = selPrim,
		templates = Forge.templates, rev = Forge.rev }
end

function widget:SetConfigData(d)
	if not d then return end
	if d.px then px, py = d.px, d.py end
	if d.pw then pw = d.pw end
	if d.ph then ph = d.ph end
	if d.scale then scale = Clamp(d.scale, 0.6, 2.2) end
	if d.closed ~= nil then closed = d.closed end
	if d.tab then tab = d.tab end
	if type(d.spec) == "table" then
		for k, v in pairs(d.spec) do spec[k] = v end
	end
	if type(d.stances) == "table" then
		for k, v in pairs(d.stances) do stances[k] = v end
	end
	if type(d.shape) == "table" and #d.shape > 0 then
		shape = d.shape
		selPrim = d.selPrim or 1
	end
	if type(d.templates) == "table" and (d.rev or 0) > (Forge.rev or 0) then
		for k in pairs(Forge.templates) do Forge.templates[k] = nil end
		for k, v in pairs(d.templates) do Forge.templates[k] = v end
		Forge.rev = d.rev
	end
end

function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:Update()
	-- another widget (the build panel) asked for the forge to open
	if Forge.openRequest then
		Forge.openRequest = false
		if Forge.open then Forge.open() end
	end
end

function widget:DrawScreen()
	rects = {}
	if closed then return end
	local s = scale
	local W = Clamp(pw, MIN_W * s, MAX_W * s)
	local H = Clamp(ph, MIN_H * s, MAX_H * s)
	pw, ph = W, H
	if scaling then py = scaling.top - H end
	px = math.max(0, math.min(vsx - W, px)); py = math.max(0, math.min(vsy - H, py))
	panelBox = { w = W, h = H }
	local x1, y1, x2, y2 = px, py, px + W, py + H

	Box(x1, y1, x2, y2, 0.05, 0.05, 0.09, 0.93)
	Frame(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.9)
	-- title bar
	Box(x1, y2 - TITLE * s, x2, y2, 0.14, 0.12, 0.2, 1)
	VBFont.Text("VOIDBORN UNIT FORGE", x1 + 8 * s, y2 - TITLE * s + TITLE * s * 0.25, 12 * s, "o", 0.9, 0.85, 0.7, 1)
	rects[#rects + 1] = { x1, y2 - TITLE * s, x2 - TITLE * s, y2, drag = true }
	-- zoom buttons
	local zb = TITLE * s
	for i, lbl in ipairs({ "-", "+" }) do
		local zx = x2 - zb * 2 + (i - 1) * zb
		local zr = { zx, y2 - zb, zx + zb, y2, zoom = (lbl == "-" and -1 or 1) }
		rects[#rects + 1] = zr
		Box(zr[1], zr[2], zr[3], zr[4], 0.22, 0.2, 0.3, 1)
		VBFont.Text(lbl, zr[1] + zb * 0.3, zr[2] + zb * 0.22, 12 * s, "o", 0.9, 0.9, 0.95, 1)
	end
	local xr = { x2 - TITLE * s, y2 - TITLE * s, x2, y2, close = true }
	rects[#rects + 1] = xr
	Box(xr[1], xr[2], xr[3], xr[4], 0.35, 0.1, 0.1, 1)
	VBFont.Text("x", xr[1] + TITLE * s * 0.33, xr[2] + TITLE * s * 0.25, 11 * s, "o", 1, 1, 1, 1)
	-- the resize handle
	local hs = 14 * s
	local hr = { x2 - hs, y1, x2, y1 + hs, scale = true }
	rects[#rects + 1] = hr
	gl.Color(0.85, 0.65, 0.2, 0.75)
	for k = 1, 3 do gl.Rect(x2 - 2 - k * 3 * s, y1 + 2, x2 - 2, y1 + 2 + k * 3 * s - 2 * s) end

	-- the tab bar
	local ty = y2 - TITLE * s - TABH * s
	local tw = (W - 16) / #TABS
	for i, t in ipairs(TABS) do
		local tx = x1 + 8 + (i - 1) * tw
		local active = (tab == t[2])
		Box(tx, ty, tx + tw - 4, ty + TABH * s - 2, active and 0.2 or 0.11, active and 0.18 or 0.11, active and 0.3 or 0.17, 1)
		if active then gl.Color(0.85, 0.65, 0.2, 0.9); gl.Rect(tx, ty, tx + tw - 4, ty + 2) end
		local lbl = t[1]
		VBFont.Text(lbl, tx + (tw - 4 - VBFont.Width(lbl, 10 * s)) / 2, ty + TABH * s * 0.25, 10 * s, "o",
			active and 1 or 0.55, active and 0.95 or 0.58, active and 0.7 or 0.62, 1)
		rects[#rects + 1] = { tx, ty, tx + tw - 4, ty + TABH * s - 2, tab = t[2] }
	end

	-- the content area
	local cx, cy = x1 + 8, y1 + 8
	local cw, ch = W - 16, H - (TITLE + TABH + FOOT) * s
	if tab == "base" then DrawBase(cx, cy, cw, ch)
	elseif tab == "nums" then DrawNums(cx, cy, cw, ch)
	elseif tab == "img" then DrawImage(cx, cy, cw, ch)
	elseif tab == "shape" then DrawShape(cx, cy, cw, ch) end

	-- the footer: the price, the template id and the actions
	local fy = y2 - FOOT * s
	gl.Color(0.85, 0.65, 0.2, 0.5); gl.Rect(x1 + 6, fy, x2 - 6, fy + 1)
	-- what the unit costs (the gadget charges exactly the same)
	local price = Price()
	local px2 = x1 + 10
	if price then
		local line = string.format("metal %d   energy %d   build %ds", price.metal, price.energy, price.build)
		VBFont.Text(line, px2, fy + 5 * s, 10 * s, "o", 0.95, 0.8, 0.45, 1)
		px2 = px2 + VBFont.Width(line, 10 * s) + 10 * s
		if price.premium > 0 then
			local extra = string.format("(+%d for the extra power)", price.premium)
			VBFont.Text(extra, px2, fy + 5 * s, 9 * s, "o", 0.55, 0.78, 0.55, 1)
		end
	end
	-- the status line, on the right of the footer
	if status ~= "" then
		VBFont.Text(status, x2 - 10 - VBFont.Width(status, 9 * s), fy + 5 * s, 9 * s, "or", 0.55, 0.9, 0.65, 1)
	end
	-- the template id and the actions
	local by = fy + 20 * s
	local idw = 120 * s
	Box(x1 + 8, by, x1 + 8 + idw, by + 20 * s, 0.1, 0.1, 0.16, 1)
	Frame(x1 + 8, by, x1 + 8 + idw, by + 20 * s, 0.5, 0.5, 0.6, 0.6)
	VBFont.Text(spec.id, x1 + 14, by + 4 * s, 10 * s, "o", 0.95, 0.9, 0.7, 1)
	-- the template dropdown
	local ids = Forge.TemplateIds()
	local tbtnW = 90 * s
	local tx2 = x1 + 14 + idw
	Button(tx2, by, tbtnW, 20 * s, "LOAD", "load", { 0.4, 0.7, 1 })
	if ids[1] then
		VBFont.Text(ids[#ids], tx2 + tbtnW + 6, by + 5 * s, 9 * s, "o", 0.6, 0.63, 0.7, 1)
	end
	local bx = tx2 + tbtnW + 46 * s
	Button(bx, by, 74 * s, 20 * s, "CREATE", "create", { 0.3, 0.9, 0.45 })
	Button(bx + 78 * s, by, 74 * s, 20 * s, "SPAWN", "spawn", { 0.4, 0.8, 1 })
	Button(bx + 156 * s, by, 66 * s, 20 * s, "SAVE", "save", { 1, 0.7, 0.3 })
end

function widget:IsAbove(x, y)
	return panelBox ~= nil and x >= px and x <= px + panelBox.w and y >= py and y <= py + panelBox.h
end

function widget:MousePress(x, y, button)
	if not widget:IsAbove(x, y) then return false end
	for _, r in ipairs(rects) do
		if Inside(x, y, r) then
			if r.close then closed = true; Snd("ui_close"); return true end
			if r.scale then scaling = { x0 = x, y0 = y, s0 = scale, top = py + (panelBox and panelBox.h or 0),
				w0 = pw, h0 = ph }; return true end
			if r.drag then drag = { x - px, y - py }; return true end
			if r.zoom then
				scale = Clamp(scale + r.zoom * 0.1, 0.6, 2.2)
				Snd("ui_click")
				return true
			end
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
			if r.button then
				local a = r.button.action
				if a == "create" then CreateUnit()
				elseif a == "spawn" then SpawnMore()
				elseif a == "save" then SaveTemplate()
				elseif a == "load" then
					local ids = Forge.TemplateIds()
					if ids[1] then LoadTemplate(ids[#ids]) end
				elseif a == "delprim" then
					if selPrim and shape[selPrim] then
						table.remove(shape, selPrim)
						selPrim = #shape > 0 and math.min(selPrim, #shape) or 0
					end
				elseif a == "clearshape" then shape = {}; selPrim = 0
				elseif a:sub(1, 4) == "add:" then
					local kind = a:sub(5)
					local n = #shape + 1
					shape[n] = { type = kind, size = { 30, 30, 30 }, pos = { 0, 20 + (n - 1) * 12, 0 },
						rot = { 0, 0, 0 }, color = { 0.8, 0.85, 0.95, 1 }, tex = 0, uv = { 0, 0, 1, 1 } }
					selPrim = n
				end
				Snd("ui_click")
				return true
			end
			if r.prim then selPrim = r.prim; Snd("ui_click"); return true end
			if r.icon then
				if r.icon.id then
					selUnit = r.icon.id
					spec.base = UnitDefs[r.icon.id].name
					status = "base: " .. spec.base
				elseif r.icon.name then
					selPng = r.icon.name
					spec.png = r.icon.name
					-- map it onto every primitive that has no texture of its own
					for _, p in ipairs(shape) do p.tex = p.tex or 0 end
					status = "image: " .. r.icon.name
				end
				Snd("ui_select")
				return true
			end
		end
	end
	return true
end

function widget:MouseMove(x, y)
	if drag then px, py = x - drag[1], y - drag[2]
	elseif scaling then
		-- the corner handle changes the size of the panel
		pw = scaling.w0 + (x - scaling.x0)
		ph = scaling.h0 - (y - scaling.y0)
	elseif dragSlider then
		SliderTo(dragSlider, x)
	end
end

function widget:MouseRelease() drag, scaling, dragSlider = nil, nil, nil end
