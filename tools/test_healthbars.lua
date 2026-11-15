-- Smoke test of LuaUI/Widgets/vb_healthbars.lua with a mock engine.  Run: python3 tools/test_healthbars.py
local rects, verts = 0, 0
gl = setmetatable({ BeginEnd = function(_, fn, ...) rects = rects + 1; fn(...) end, Vertex = function() verts = verts + 1 end }, { __index = function() return function() end end })
GL = setmetatable({}, { __index = function() return 0 end })
local hp = { [1] = { 100, 100 }, [2] = { 40, 100 }, [3] = { 10, 100, 0, 0, 0.3 } }
local echoes = {}
Spring = setmetatable({
	GetVisibleUnits = function() return { 1, 2, 3 } end,
	GetUnitHealth = function(u) local h = hp[u]; return h[1], h[2], 0, 0, h[5] or 1 end,
	GetUnitPosition = function() return 100, 0, 100 end, GetUnitHeight = function() return 30 end, GetUnitRadius = function() return 20 end,
	GetUnitTeam = function(u) return u == 2 and 1 or 0 end, IsUnitSelected = function() return false end,
	GetMyTeamID = function() return 0 end, AreTeamsAllied = function() return false end,
	Echo = function(m) echoes[#echoes + 1] = m end,
}, { __index = function() return function() end end })
widgetHandler = { AddAction = function() end }
local w = {}; setmetatable(w, { __index = _G }); w.widget = w
local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/vb_healthbars.lua")); setfenv(chunk, w); chunk()
local fails = 0
local function check(n, ok, i) print((ok and "ok    " or "FAIL  ") .. n .. (i and ("  (" .. tostring(i) .. ")") or "")); if not ok then fails = fails + 1 end end
w:Initialize()
rects = 0; w:DrawWorld()
check("always: 6 pills per tube (outline, glass, body, light, highlight, gloss); the unfinished unit has a second tube", rects == 6 + 6 + 12, rects)
hp[2] = { 0, 100 }
rects = 0; w:DrawWorld()
check("a dead-empty unit shows only the empty tube (3 pills: outline, glass, gloss)", rects == 6 + 3 + 12, rects)
hp[2] = { 40, 100 }
w:TextCommand("vbhealth")     -- -> damaged
rects = 0; w:DrawWorld()
check("damaged: the full-health unit gets no bar", rects == 6 + 12, rects)
w:TextCommand("vbhealth")     -- -> off
rects = 0; w:DrawWorld()
check("every pill is a closed fan of vertices", verts > 0 and verts % 16 == 0, verts)
check("off: nothing is drawn", rects == 0, rects)
w:TextCommand("vbhealth")     -- -> always
check("mode is saved", w:GetConfigData().mode == "always")
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("healthbar test failed") end
