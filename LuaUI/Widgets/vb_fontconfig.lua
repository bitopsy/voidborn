function widget:GetInfo()
	return { name = "Voidborn Font Config", desc = "Points the engine's global UI font at the Voidborn glyph font",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = -1000, enabled = true }
end

-- The engine reads FontFile/SmallFontFile when it (re)loads fonts. The game archive also ships
-- fonts/FreeSansBold.otf (a copy of the glyph font) which overrides the engine default through the VFS.
-- Setting the config here makes the choice stick even if the user's springsettings.cfg names another font.
local FONT = "fonts/VoidbornGlyph.ttf"

function widget:Initialize()
	if not (Spring.GetConfigString and Spring.SetConfigString) then return end
	for _, key in ipairs({ "FontFile", "SmallFontFile" }) do
		if Spring.GetConfigString(key, "") ~= FONT then
			pcall(Spring.SetConfigString, key, FONT)
		end
	end
end
