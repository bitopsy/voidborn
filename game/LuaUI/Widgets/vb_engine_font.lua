function widget:GetInfo()
	return { name = "Voidborn Engine Font", desc = "The engine's own text (console, chat, clock, stock tooltips) uses the Voidborn UI font (Georgia): font size 24, small font 17",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -2000, enabled = true }
end

-- The widgets draw with LuaUI/Headers/vb_font.h.lua. This widget does the same for the engine's own fonts
-- (FontFile / SmallFontFile): it puts the font and the sizes in the engine config and reloads the fonts with /font.
--
-- The sizes are set as an overlay (memory only, never saved), so no other game on the same engine is touched.
-- /font itself writes the new file names to the player's springsettings.cfg, and a game that has no such file in
-- its archive would then fail to start. So the names that were there before are written straight back.

local FONT_SIZE, SMALL_FONT_SIZE = 22, 15

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")

function widget:Initialize()
	local file = okF and type(VBFont) == "table" and VBFont.File and VBFont.File()
	if not file then return end
	if not (Spring.GetConfigString and Spring.SetConfigString and Spring.SetConfigInt) then return end

	local oldLarge = Spring.GetConfigString("FontFile")
	local oldSmall = Spring.GetConfigString("SmallFontFile")

	Spring.SetConfigInt("FontSize", FONT_SIZE, true)
	Spring.SetConfigInt("SmallFontSize", SMALL_FONT_SIZE, true)
	Spring.SendCommands("font " .. file .. " " .. file)    -- small font file first, then the large one

	if oldLarge and oldLarge ~= "" then Spring.SetConfigString("FontFile", oldLarge) end
	if oldSmall and oldSmall ~= "" then Spring.SetConfigString("SmallFontFile", oldSmall) end
	Spring.Echo("[VB] engine font: " .. file .. ", size " .. FONT_SIZE .. ", small " .. SMALL_FONT_SIZE)
end
