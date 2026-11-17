function widget:GetInfo()
	return { name = "Voidborn Economy Radar", desc = "Docked HUD panel: radar chart of the economy (income, stores, spending, build power, extractors) of every team",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true }
end
-- Self-contained: its own - (fold) and x (off) buttons; switched on and off in the dashboard SETTINGS or with /vbdock econ.
-- Placement: LuaUI/Widgets/vb_dock.lua.  Drawing and data: LuaUI/Headers/vb_hud_radar.h.lua.
local ok, HudRadar = pcall(VFS.Include, "LuaUI/Headers/vb_hud_radar.h.lua")
if ok and type(HudRadar) == "table" then
	HudRadar.Install(widget, { id = "econ", title = "ECONOMY RADAR", radar = "economy", headline = "mi", open = "economy" })
else
	Spring.Echo("[VB] economy radar: " .. tostring(HudRadar))
end
