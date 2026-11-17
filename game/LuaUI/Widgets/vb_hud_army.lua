function widget:GetInfo()
	return { name = "Voidborn Army Radar", desc = "Docked HUD panel: radar chart of the army (damage dealt and taken, kills, losses, army and defence value, damage/s) of every team",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true }
end
-- Self-contained: its own - (fold) and x (off) buttons; switched on and off in the dashboard SETTINGS or with /vbdock army.
-- Placement: LuaUI/Widgets/vb_dock.lua.  Drawing and data: LuaUI/Headers/vb_hud_radar.h.lua.
local ok, HudRadar = pcall(VFS.Include, "LuaUI/Headers/vb_hud_radar.h.lua")
if ok and type(HudRadar) == "table" then
	HudRadar.Install(widget, { id = "army", title = "ARMY RADAR", radar = "combat", headline = "av", open = "combat" })
else
	Spring.Echo("[VB] army radar: " .. tostring(HudRadar))
end
