-- Voidborn LuaUI entry point (shipped inside the game archive so the engine does not
-- fall back to its loose, RAW-only cont/luaui.lua, which never finds our widgets).
LUAUI_VERSION = "LuaUI v0.3 (Voidborn)"
LUAUI_DIRNAME = 'LuaUI/'
VFS.DEF_MODE = VFS.ZIP_FIRST
local STARTUP_FILENAME = LUAUI_DIRNAME .. 'main.lua'

Spring.Echo('[VB] luaui.lua running, using LUAUI_DIRNAME = ' .. LUAUI_DIRNAME)

local text = VFS.LoadFile(STARTUP_FILENAME, VFS.ZIP)
if text == nil then
	Script.Kill('Failed to load ' .. STARTUP_FILENAME .. ' from game archive')
end
local chunk, err = loadstring(text, STARTUP_FILENAME)
if chunk == nil then
	Script.Kill('Failed to compile ' .. STARTUP_FILENAME .. ' (' .. tostring(err) .. ')')
end
chunk()
