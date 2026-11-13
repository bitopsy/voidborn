-- Voidborn LuaUI entry. Newer Recoil runs LuaUI/main.lua directly (no luaui.lua), so the
-- globals the old luaui.lua set must be defined here. Errors are echoed to the infolog.
LUAUI_DIRNAME = LUAUI_DIRNAME or 'LuaUI/'
LUAUI_VERSION = LUAUI_VERSION or 'LuaUI v0.3 (Voidborn)'
-- ZIP_FIRST, not RAW_FIRST: the engine's data directory ships its own loose LuaUI/ files
-- (selector.lua, widgets.lua, layout.lua, ...) which would otherwise shadow the ones in
-- this game archive - the F11 widget selector would then be the stock engine one without
-- the memory columns and histograms. Files that only exist loose (fonts, icons, images)
-- still fall back to the raw filesystem.
VFS.DEF_MODE = VFS.ZIP_FIRST
Spring.Echo('[VB] LuaUI/main.lua entered, dir=' .. LUAUI_DIRNAME)

local text = VFS.LoadFile(LUAUI_DIRNAME .. 'main_stock.lua')
if not text then Spring.Echo('[VB] ERROR: cannot read ' .. LUAUI_DIRNAME .. 'main_stock.lua') return end
local chunk, err = loadstring(text, 'main_stock.lua')
if not chunk then Spring.Echo('[VB] ERROR compiling main_stock.lua: ' .. tostring(err)) return end
local ok, e = xpcall(chunk, function(m) return debug and debug.traceback and debug.traceback(tostring(m), 2) or tostring(m) end)
if not ok then Spring.Echo('[VB] ERROR running main_stock.lua: ' .. tostring(e)) error(e, 0) end
Spring.Echo('[VB] main_stock.lua finished OK')
