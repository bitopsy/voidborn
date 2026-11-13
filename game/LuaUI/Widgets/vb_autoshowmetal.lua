function widget:GetInfo()
	return { name = "Voidborn Auto Show Metal", desc = "Switches to the metal map while a metal extractor is selected",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -50, enabled = true }
end

-- The engine deprecated mapinfo's autoShowMetal flag ("please enable manually from
-- lua instead"). This widget does exactly that: the engine's automatic metal view is
-- switched off and the metal map is toggled by hand whenever a metal extractor build
-- command is the active command.

local isMex = {}

function widget:Initialize()
	if Spring.SetAutoShowMetal then
		pcall(Spring.SetAutoShowMetal, false)
	end
	for uDefID, uDef in pairs(UnitDefs) do
		if uDef and uDef.extractsMetal > 0 then isMex[uDefID] = true end
	end
end

function widget:ActiveCommandChanged(cmdID)
	local wantsMetal = (cmdID and isMex[-cmdID]) or false
	local isMetalViewOn = (Spring.GetMapDrawMode() == 'metal')
	if wantsMetal ~= isMetalViewOn then
		Spring.SendCommands("showmetalmap")
	end
end
