function widget:GetInfo()
	return { name = "Voidborn Hide Stock Panel", desc = "Forces the engine's default build/order panel to be invisible",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -1000, enabled = true }
end

-- The engine only reads ctrlpanel.txt from the VFS, where a loose copy in the data directory (or an older
-- game archive) can shadow the one in this game. Spring.LoadCtrlPanelConfig() takes the config as a STRING,
-- so it cannot be shadowed. Same values as game/ctrlpanel.txt.
local CFG = [[
outlinefont    0
textureAlpha   0.0
frameAlpha     0.0
selectGaps     0
selectThrough  1
xIcons         2
yIcons         2
xIconSize      0.001
yIconSize      0.001
iconBorder     0.000
frameBorder    0.000
prevPageSlot   none
nextPageSlot   none
deadIconSlot   none
xPos           3.000
yPos           0.215
xSelectionPos  0.018
ySelectionPos  0.127
]]

local frames, done = 0, false

local function Apply()
	if not Spring.LoadCtrlPanelConfig then
		Spring.Echo("[VB] hidepanel: Spring.LoadCtrlPanelConfig missing in this engine")
		return
	end
	local ok, err = pcall(Spring.LoadCtrlPanelConfig, CFG)
	Spring.Echo("[VB] hidepanel: LoadCtrlPanelConfig " .. (ok and "applied" or ("FAILED: " .. tostring(err))))
	if Spring.ForceLayoutUpdate then pcall(Spring.ForceLayoutUpdate) end
end

function widget:Initialize() Apply() end

-- once more shortly after start, in case something reloaded the stock config after the widgets loaded
function widget:Update()
	if done then return end
	frames = frames + 1
	if frames == 30 then done = true; Apply() end
end
