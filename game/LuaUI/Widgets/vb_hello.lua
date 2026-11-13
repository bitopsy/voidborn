function widget:GetInfo()
	return { name = "Voidborn Hello", desc = "Prints a line to infolog so you can confirm LuaUI widgets load", author = "Voidborn", date = "2026", license = "GPL", layer = 0, enabled = true }
end
function widget:Initialize()
	Spring.Echo("[VB] LuaUI widget handler is working - widgets in LuaUI/Widgets are loading")
end
