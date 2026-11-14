-- Voidborn game settings: the tunables the host (or a solo player) can change
-- while the game runs.
--
--   SPLIT XP    the experience at which a unit splits in two
--   GROWTH      how much bigger a unit gets before it splits (1.0 = double size)
--
-- The gadget LuaRules/Gadgets/vb_experience.lua owns the values and publishes them
-- as game rules parameters, so this panel always shows what is really in use.
-- The same numbers can be set before the game starts through modoptions.lua.
--
--   /vbsettings            open / close this panel
function widget:GetInfo()
	return { name = "Voidborn Settings", desc = "Host settings: the experience at which units split and how much they grow",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true }
end

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local vsx, vsy = Spring.GetViewGeometry()
local px, py = 40, 40
local scale = 1.0
local closed = false
local drag, scaling, dragSlider = nil, nil, nil

-- the defaults of the gadget (LuaRules/Gadgets/vb_experience.lua)
local DEF_SPLIT, DEF_GROWTH = 0.14, 1.00
local LIM_SPLIT = { 0.01, 2.00, 0.01 }
local LIM_GROWTH = { 0.00, 4.00, 0.05 }

-- the values the gadget is using right now, and the ones the sliders edit
local splitXP, maxGrowth = DEF_SPLIT, DEF_GROWTH
local pSplit, pGrowth = DEF_SPLIT, DEF_GROWTH
local status = ""

local function Snd(name, vol) Spring.PlaySoundFile("sounds/" .. name .. ".wav", vol or 0.7, "ui") end
local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function Inside(x, y, r) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end

local rects = {}, panelBox

-- read the live values from the gadget
local function Refresh()
	local grp = Spring.GetGameRulesParam
	if not grp then return end
	local v = tonumber(grp("vb_split_xp"))
	if v then splitXP = v end
	v = tonumber(grp("vb_max_growth"))
	if v then maxGrowth = v end
end

local function Push()
	Spring.SendLuaRulesMsg(string.format("vbexp:split_xp=%.4g,max_growth=%.4g", pSplit, pGrowth))
	status = string.format("split at %.3f xp, growth %.2fx", pSplit, pGrowth)
	Snd("ui_click")
end

local function ApplySlider(s, x)
	local t = Clamp((x - s.x1) / math.max(1, s.w), 0, 1)
	local v = s.min + t * (s.max - s.min)
	if s.step and s.step > 0 then v = math.floor(v / s.step + 0.5) * s.step end
	v = Clamp(v, s.min, s.max)
	if s.key == "split_xp" then pSplit = v else pGrowth = v end
end

local function Slider(x, y, w, label, value, min, max, step, decimals, suffix, key)
	local barY = y + 15
	VBFont.Text(label, x, y + 2, 10, "o", 0.62, 0.62, 0.72, 1)
	local txt = string.format("%." .. decimals .. "f", value) .. (suffix or "")
	local tw = VBFont.Width(txt, 10)
	VBFont.Text(txt, x + w - tw, y + 2, 10, "or", 0.95, 0.85, 0.55, 1)
	Box(x, barY, x + w, barY + 4, 0.14, 0.14, 0.2, 1)
	local t = Clamp((value - min) / (max - min), 0, 1)
	Box(x, barY, x + w * t, barY + 4, 0.35, 0.75, 1.0, 0.85)
	local hx = x + w * t
	Box(hx - 2, barY - 3, hx + 2, barY + 7, 0.45, 0.9, 1.0, 1)
	rects[#rects + 1] = { x, y - 2, x + w, barY + 9, slider = { min = min, max = max, step = step, key = key, x1 = x, w = w } }
	return 30
end

function widget:Initialize()
	Spring.Echo("[VB] Settings panel loaded: split threshold and growth, /vbsettings toggles it")
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbsettings", function() closed = not closed return true end, nil, "t")
	end
	-- ask the gadget for the current values
	Spring.SendLuaRulesMsg("vbexp:get")
end

function widget:TextCommand(cmd)
	if cmd == "vbsettings" then closed = not closed; if not closed then Refresh(); pSplit, pGrowth = splitXP, maxGrowth end; return true end
end

function widget:GetConfigData() return { px = px, py = py, scale = scale, closed = closed } end
function widget:SetConfigData(d)
	if not d then return end
	if d.px then px, py = d.px, d.py end
	if d.scale then scale = Clamp(d.scale, 0.6, 2.0) end
	if d.closed ~= nil then closed = d.closed end
end
function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:DrawScreen()
	rects = {}
	if closed then return end
	Refresh()
	local s = scale
	local W, H = 310 * s, 205 * s
	if scaling then py = scaling.top - H end
	px = math.max(0, math.min(vsx - W, px)); py = math.max(0, math.min(vsy - H, py))
	panelBox = { w = W, h = H }
	local x1, y1, x2, y2 = px, py, px + W, py + H
	local TITLE = 24 * s

	Box(x1, y1, x2, y2, 0.05, 0.05, 0.09, 0.93)
	Frame(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.9)
	Box(x1, y2 - TITLE, x2, y2, 0.14, 0.12, 0.2, 1)
	VBFont.Text("VOIDBORN SETTINGS", x1 + 8 * s, y2 - TITLE + TITLE * 0.25, 12 * s, "o", 0.9, 0.85, 0.7, 1)
	rects[#rects + 1] = { x1, y2 - TITLE, x2 - TITLE, y2, drag = true }
	local xr = { x2 - TITLE, y2 - TITLE, x2, y2, close = true }
	rects[#rects + 1] = xr
	Box(xr[1], xr[2], xr[3], xr[4], 0.35, 0.1, 0.1, 1)
	VBFont.Text("x", xr[1] + TITLE * 0.33, xr[2] + TITLE * 0.25, 11 * s, "o", 1, 1, 1, 1)
	local hs = 13 * s
	rects[#rects + 1] = { x2 - hs, y1, x2, y1 + hs, scale = true }
	gl.Color(0.85, 0.65, 0.2, 0.75)
	for k = 1, 3 do gl.Rect(x2 - 2 - k * 3 * s, y1 + 2, x2 - 2, y1 + 2 + k * 3 * s - 2 * s) end

	local cx, cy = x1 + 10, y1 + 10
	local cw = W - 20
	VBFont.Text("EXPERIENCE AND GROWTH", cx, cy, 11 * s, "o", 0.85, 0.65, 0.2, 1)
	cy = cy + 18 * s
	cy = cy + Slider(cx, cy, cw, "SPLIT AT (XP)", pSplit, LIM_SPLIT[1], LIM_SPLIT[2], LIM_SPLIT[3], 3, "", "split_xp")
	cy = cy + Slider(cx, cy, cw, "GROWTH BEFORE SPLIT", pGrowth, LIM_GROWTH[1], LIM_GROWTH[2], LIM_GROWTH[3], 2, "x", "max_growth")
	cy = cy + 6 * s
	VBFont.Text("at the threshold the unit is", cx, cy, 9 * s, "o", 0.55, 0.58, 0.65, 1)
	cy = cy + 12 * s
	VBFont.Text(string.format("%.2fx its normal size", 1 + pGrowth), cx, cy, 10 * s, "or", 0.95, 0.85, 0.55, 1)
	cy = cy + 14 * s
	-- buttons
	local bw = 84 * s
	Box(cx, cy, cx + bw, cy + 20 * s, 0.16, 0.16, 0.24, 1)
	Frame(cx, cy, cx + bw, cy + 20 * s, 0.85, 0.65, 0.2, 0.8)
	VBFont.Text("APPLY", cx + 24 * s, cy + 4 * s, 10 * s, "oc", 0.95, 0.9, 0.8, 1)
	rects[#rects + 1] = { cx, cy, cx + bw, cy + 20 * s, button = "apply" }
	Box(cx + bw + 8 * s, cy, cx + 2 * bw + 8 * s, cy + 20 * s, 0.16, 0.16, 0.24, 1)
	Frame(cx + bw + 8 * s, cy, cx + 2 * bw + 8 * s, cy + 20 * s, 0.85, 0.65, 0.2, 0.8)
	VBFont.Text("RESET", cx + bw + 28 * s, cy + 4 * s, 10 * s, "oc", 0.95, 0.9, 0.8, 1)
	rects[#rects + 1] = { cx + bw + 8 * s, cy, cx + 2 * bw + 8 * s, cy + 20 * s, button = "reset" }
	-- what the game is really using right now
	local used = string.format("in use: split %.3f xp, growth %.2fx", splitXP, maxGrowth)
	VBFont.Text(used, x1 + 10, y2 - 12 * s, 9 * s, "o", 0.45, 0.5, 0.58, 1)
	if status ~= "" then
		VBFont.Text(status, x1 + 10, y2 - 24 * s, 9 * s, "o", 0.5, 0.85, 0.6, 1)
	end
end

function widget:IsAbove(x, y)
	return panelBox ~= nil and x >= px and x <= px + panelBox.w and y >= py and y <= py + panelBox.h
end

function widget:MousePress(x, y, button)
	if not widget:IsAbove(x, y) then return false end
	for _, r in ipairs(rects) do
		if Inside(x, y, r) then
			if r.close then closed = true; Snd("ui_close"); return true end
			if r.scale then scaling = { x0 = x, y0 = y, s0 = scale, top = py + (panelBox and panelBox.h or 0) }; return true end
			if r.drag then drag = { x - px, y - py }; return true end
			if r.button == "apply" then Push(); return true end
			if r.button == "reset" then pSplit, pGrowth = DEF_SPLIT, DEF_GROWTH; Push(); return true end
			if r.slider then
				dragSlider = r.slider
				ApplySlider(dragSlider, x)
				return true
			end
		end
	end
	return true
end

function widget:MouseMove(x, y)
	if drag then px, py = x - drag[1], y - drag[2]
	elseif scaling then scale = Clamp(scaling.s0 + ((x - scaling.x0) - (y - scaling.y0)) / 350, 0.6, 2.0)
	elseif dragSlider then ApplySlider(dragSlider, x) end
end

function widget:MouseRelease() drag, scaling, dragSlider = nil, nil, nil end
