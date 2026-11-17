function widget:GetInfo()
	return { name = "Voidborn Tooltip", desc = "Draws the engine's hover tooltip (terrain, units, widget hints) with the Voidborn font, smaller, on a plate; can also just hide the engine tooltip",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 10, enabled = true }
end

-- The engine tooltip (position, elevation, terrain type, unit info, and the hints that other widgets return
-- from widget:GetTooltip) is plain engine text in the top left corner.  This widget asks the engine for the
-- same text (Spring.GetCurrentTooltip) and draws it itself, in the game's font, at a smaller size.
--
--   /vbtooltip              switches the widget off and on (the engine tooltip comes back when it is off)
--   /vbtooltip draw         hide the engine tooltip and draw the Voidborn plate instead (default)
--   /vbtooltip hide         ONLY hide the engine tooltip, draw nothing
--   /vbtooltip off          engine tooltip back, nothing drawn by this widget
--   /vbtooltip dock         the plate sits at the bottom of the dock column (default; needs vb_dock): same width as the build
--                           menu, a fixed height so the panels above it do not jump around
--   /vbtooltip pos br       free-floating plate instead of the dock, in a corner: bl, br, tl, tr
--                           (also: topleft, topright, bottomleft, bottomright, lowerleft, lowerright)
--   /vbtooltip scale 1.2    text size (0.6 .. 2.0, default 0.9)
-- Everything is remembered with the other widget settings.

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local glColor, glRect = gl.Color, gl.Rect
local min, max = math.min, math.max

local vsx, vsy = Spring.GetViewGeometry()
local mode  = "draw"   -- "draw" = own plate | "hide" = only hide the engine tooltip | "off" = engine tooltip as usual
local pos   = "bl"     -- tl | tr | bl | br   (default: bottom left)
local scale = 0.9     -- default text size
local engineHidden = false
local docked = true     -- in the dock column (when the dock widget is there); /vbtooltip pos ... floats it
local DOCK_LINES, DOCK_H, DOCK_SIZE, DOCK_PAD = 7, 104, 11, 8      -- dock units
local lines, lastText = {}, nil

local POS_ALIAS = {
	tl = "tl", topleft = "tl",
	tr = "tr", topright = "tr",
	bl = "bl", bottomleft = "bl", lowerleft = "bl",
	br = "br", bottomright = "br", lowerright = "br",
}
local POS_NAME = { tl = "top left", tr = "top right", bl = "bottom left", br = "bottom right" }

local function Sc(v) return v * scale * max(0.75, min(1.8, vsy / 1080)) end

local function HideEngine(hide)
	if hide == engineHidden then return end
	engineHidden = hide
	-- the engine's own tooltip is switched off while this widget hides/draws it (and back on afterwards)
	pcall(Spring.SendCommands, hide and "tooltip 0" or "tooltip 1")
end

local function Apply()
	HideEngine(mode ~= "off")
	if mode ~= "draw" then lines = {} end
	lastText = nil
end

-- engine colour escapes (\255\r\g\b) and the reset marker are removed: the widget colours the lines itself
local function Clean(s) return (s:gsub("\255...", ""):gsub("\008", "")) end

-- break a long line at spaces so the plate stays narrow
local function Wrap(text, size, maxW, out)
	local line = ""
	for word in text:gmatch("%S+") do
		local try = line == "" and word or (line .. " " .. word)
		if VBFont.Width(try, size) > maxW and line ~= "" then out[#out + 1] = line; line = word else line = try end
	end
	if line ~= "" then out[#out + 1] = line end
end

local function Dock() return docked and WG and WG.VBDock or nil end

local function Update(text)
	lastText = text
	lines = {}
	if not text or text == "" then return end
	local dock = Dock()
	local size, maxW, maxLines = Sc(12), vsx * 0.34, 14
	if dock then          -- dock units: one wrapping for every scale, the size is applied when drawing
		size, maxW, maxLines = DOCK_SIZE * scale / 0.9, dock.BASE_W - 2 * DOCK_PAD, DOCK_LINES
	end
	for raw in Clean(text):gmatch("[^\n]+") do
		if raw:match("%S") then Wrap(raw, size, maxW, lines) end
		if #lines >= maxLines then break end
	end
	if #lines > maxLines then for i = #lines, maxLines + 1, -1 do lines[i] = nil end end
end

local wasDocked = false
function widget:Update()
	if mode ~= "draw" then return end
	local d = Dock() ~= nil
	if d ~= wasDocked then wasDocked = d; lastText = nil end     -- the dock came or went: wrap the text again
	local text = Spring.GetCurrentTooltip and Spring.GetCurrentTooltip() or ""
	if text ~= lastText then Update(text) end
end

local function DrawDocked(dock)
	-- a fixed-height plate at the bottom of the column, always there so that nothing above it moves when the text changes
	dock.Report("tooltip", DOCK_H, DOCK_H)
	local x1, y1, x2, y2, S = dock.Rect("tooltip")
	if not x1 then return end
	glColor(0.06, 0.06, 0.09, 0.88); glRect(x1, y1, x2, y2)
	glColor(0.85, 0.65, 0.2, 0.9)
	glRect(x1, y1, x2, y1 + 1); glRect(x1, y2 - 1, x2, y2); glRect(x1, y1, x1 + 1, y2); glRect(x2 - 1, y1, x2, y2)
	local size = DOCK_SIZE * scale / 0.9 * S
	local lh, pad = size * 1.3, DOCK_PAD * S
	local ty = y2 - pad - size * 0.85
	for i, l in ipairs(lines) do
		local r, g, b, a = 0.74, 0.78, 0.86, 0.95
		if i == 1 then r, g, b, a = 1, 1, 1, 1 end
		if l:match("^Hardness") and l:match("Metal%s+[%d%.]*[1-9]") then r, g, b = 0.55, 0.85, 1.0 end
		VBFont.Text(l, x1 + pad, ty, size, "o", r, g, b, a)
		ty = ty - lh
	end
end

function widget:DrawScreen()
	if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
	if mode ~= "draw" then return end
	local dock = Dock()
	if dock then return DrawDocked(dock) end
	if #lines == 0 then return end
	local size = Sc(12)
	local lh = size * 1.32
	local pad = Sc(8)
	local margin = Sc(8)
	local w = 0
	for _, l in ipairs(lines) do w = max(w, VBFont.Width(l, size)) end

	local plateW = w + pad * 2
	local plateH = #lines * lh + pad * 2 - (lh - size)
	local right  = (pos == "tr" or pos == "br")
	local bottom = (pos == "bl" or pos == "br")

	local x1 = right and (vsx - margin - plateW) or margin
	local x2 = x1 + plateW
	local y1, y2
	if bottom then
		y1 = margin
		y2 = y1 + plateH
	else
		y2 = vsy - margin
		y1 = y2 - plateH
	end

	-- plate: a bright line on top, and an accent bar on the screen side of the corner it sits in
	glColor(0.03, 0.035, 0.05, 0.78); glRect(x1, y1, x2, y2)
	glColor(0.35, 0.7, 1.0, 0.55);   glRect(x1, y2 - 1, x2, y2)
	glColor(0.35, 0.7, 1.0, 0.30)
	if right then glRect(x2 - 2, y1, x2, y2) else glRect(x1, y1, x1 + 2, y2) end

	-- text: the first line is the headline, the others are dimmer; a "Metal" value is highlighted
	local ty = y2 - pad - size * 0.85
	for i, l in ipairs(lines) do
		local r, g, b, a = 0.74, 0.78, 0.86, 0.95
		if i == 1 then r, g, b, a = 1, 1, 1, 1 end
		if l:match("^Hardness") and l:match("Metal%s+[%d%.]*[1-9]") then r, g, b = 0.55, 0.85, 1.0 end
		VBFont.Text(l, x1 + pad, ty, size, "o", r, g, b, a)
		ty = ty - lh
	end
end

function widget:ViewResize(w, h) vsx, vsy = w, h; lastText = nil end

function widget:Initialize()
	vsx, vsy = Spring.GetViewGeometry()
	Apply()
end

function widget:Shutdown() HideEngine(false) end

local lastOnMode = "draw"   -- what a bare "/vbtooltip" switches back on to

function widget:TextCommand(cmd)
	local word, rest = cmd:match("^(%S+)%s*(.*)$")
	if word ~= "vbtooltip" then return false end
	local arg, val = rest:match("^(%S*)%s*(.*)$")
	arg = arg:lower()

	if arg == "scale" then
		scale = max(0.6, min(2.0, tonumber(val) or 1)); lastText = nil
		Spring.Echo("[VB] tooltip scale " .. scale)
	elseif arg == "dock" then
		docked = true; lastText = nil
		Spring.Echo("[VB] tooltip: docked at the bottom of the column" .. (WG.VBDock and "" or " (the dock widget is not running, so it is drawn in the corner)"))
	elseif arg == "pos" or arg == "position" then
		local p = POS_ALIAS[(val or ""):lower():gsub("[^%a]", "")]
		if p then
			pos = p; docked = false; lastText = nil
			Spring.Echo("[VB] tooltip position: " .. POS_NAME[p])
		else
			Spring.Echo("[VB] tooltip position: tl | tr | bl | br  (now: " .. POS_NAME[pos] .. ")")
		end
	elseif arg == "hide" then
		mode = "hide"; lastOnMode = mode; Apply()
		Spring.Echo("[VB] tooltip: engine tooltip hidden, nothing drawn")
	elseif arg == "draw" or arg == "on" then
		mode = "draw"; lastOnMode = mode; Apply()
		Spring.Echo("[VB] tooltip: Voidborn plate on (" .. POS_NAME[pos] .. ")")
	elseif arg == "off" then
		mode = "off"; Apply()
		Spring.Echo("[VB] tooltip off (engine tooltip restored)")
	elseif arg == "" then
		if mode == "off" then mode = lastOnMode else lastOnMode = mode; mode = "off" end
		Apply()
		Spring.Echo("[VB] tooltip " .. (mode == "off" and "off (engine tooltip restored)" or mode))
	else
		Spring.Echo("[VB] /vbtooltip [draw | hide | off | dock | pos tl|tr|bl|br | scale 0.6..2.0]")
	end
	return true
end

function widget:GetConfigData() return { mode = mode, pos = pos, scale = scale, docked = docked } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.mode == "draw" or d.mode == "hide" or d.mode == "off" then
		mode = d.mode
	elseif d.enabled ~= nil then          -- settings saved by the older version
		mode = d.enabled and "draw" or "off"
	end
	if mode ~= "off" then lastOnMode = mode end
	if POS_ALIAS[d.pos or ""] then pos = POS_ALIAS[d.pos] end
	if d.docked ~= nil then docked = d.docked and true or false end
	if d.scale then scale = max(0.6, min(2.0, d.scale)) end
end
