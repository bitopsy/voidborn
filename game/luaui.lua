-- Voidborn LuaUI entry point (shipped inside the game archive so the engine does not
-- fall back to its loose, RAW-only cont/luaui.lua, which never finds our widgets).
LUAUI_VERSION = "LuaUI v0.3 (Voidborn)"
LUAUI_DIRNAME = 'LuaUI/'
VFS.DEF_MODE = VFS.ZIP_FIRST
local STARTUP_FILENAME = LUAUI_DIRNAME .. 'main.lua'

Spring.Echo('[VB] luaui.lua running, using LUAUI_DIRNAME = ' .. LUAUI_DIRNAME)

-- The engine's default build/order panel is hidden: the Voidborn Build Panel widget
-- (LuaUI/Widgets/vb_buildpanel.lua) is the only build menu. This has to be applied HERE,
-- before the GUI is built, otherwise the engine first tries to lay out its stock panel
-- with xIcons/yIcons = 0 and logs "LayoutButtons() bad xButtons or yButtons values"
-- plus "can not load default GUI from a LuaUI callin".
-- Same values as ctrlpanel.txt / LuaUI/Widgets/vb_hidepanel.lua.
local CTRL_PANEL_CFG = [[
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

if Spring.LoadCtrlPanelConfig then
	local ok, err = pcall(Spring.LoadCtrlPanelConfig, CTRL_PANEL_CFG)
	if not ok then
		Spring.Echo('[VB] luaui.lua: LoadCtrlPanelConfig failed: ' .. tostring(err))
	end
end

local text = VFS.LoadFile(STARTUP_FILENAME, VFS.ZIP)
if text == nil then
	Script.Kill('Failed to load ' .. STARTUP_FILENAME .. ' from game archive')
end
local chunk, err = loadstring(text, STARTUP_FILENAME)
if chunk == nil then
	Script.Kill('Failed to compile ' .. STARTUP_FILENAME .. ' (' .. tostring(err) .. ')')
end
chunk()
