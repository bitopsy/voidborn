-- Voidborn UI font helper. Widgets load it with:
--   local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
-- VBFont.Text(str, x, y, size, opts, r, g, b, a)   same arguments as gl.Text, plus an explicit colour
-- VBFont.Width(str, size)                          text width in pixels
-- VBFont.Face()                                    the loaded font object (or nil), for code that prints itself
-- VBFont.File()                                    the font file in use, also used for the engine's own font
-- The whole game uses Georgia. Georgia is Microsoft's and cannot be redistributed, so the archive ships
-- fonts/Gelasio.ttf (SIL OFL, made to be metric-compatible with Georgia) and uses it unless the real thing is
-- there: put your own Georgia.ttf into game/fonts/ and it is picked up first.
-- If no file or gl.LoadFont is unavailable it quietly falls back to the engine font, so a UI never breaks over a font.
local FONT_CHOICES = { "fonts/Georgia.ttf", "fonts/georgia.ttf", "fonts/Gelasio.ttf" }
local BASE_SIZE = 32

local M = {}
local font, tried = nil, false
local FONT_FILE

local function PickFile()
	if FONT_FILE ~= nil then return FONT_FILE or nil end
	FONT_FILE = false
	for _, f in ipairs(FONT_CHOICES) do
		local ok, has = pcall(VFS.FileExists, f)
		if ok and has then FONT_FILE = f break end
	end
	return FONT_FILE or nil
end
function M.File() return PickFile() end

local function Load()
	if tried then return font end
	tried = true
	local file = PickFile()
	if file and gl and gl.LoadFont then
		local ok, f = pcall(gl.LoadFont, file, BASE_SIZE, 3, 1.5)
		if ok and f then font = f
		else Spring.Echo("[VB] could not load " .. file .. " - using the default font") end
	end
	return font
end
function M.Face() return Load() end

function M.Text(str, x, y, size, opts, r, g, b, a)
	local f = Load()
	if f then
		f:Begin()
		f:SetTextColor(r or 1, g or 1, b or 1, a or 1)
		f:SetOutlineColor(0, 0, 0, (a or 1) * 0.85)
		f:Print(str, x, y, size, opts or "o")
		f:End()
	else
		gl.Color(r or 1, g or 1, b or 1, a or 1)
		gl.Text(str, x, y, size, opts or "o")
	end
end

function M.Width(str, size)
	local f = Load()
	if f and f.GetTextWidth then return f:GetTextWidth(str) * size end
	return #str * size * 0.6
end

return M
