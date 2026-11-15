-- Smoke test of LuaUI/Widgets/vb_ranges.lua with a mock engine.  Run: python3 tools/test_ranges.py
local circles = {}
gl = setmetatable({ DrawGroundCircle = function(x, y, z, r) circles[#circles + 1] = r end }, { __index = function() return function() end end })
GL = setmetatable({}, { __index = function() return 0 end })
UnitDefs = { [1] = { losRadius = 500, radarRadius = 0 }, [2] = { losRadius = 480, radarRadius = 2300 }, [3] = { losRadius = 0, radarRadius = 0 },
	[-5] = nil, [5] = { losRadius = 300, radarRadius = 1000 } }
local sel, units = { 11, 12, 13 }, { [11] = 1, [12] = 2, [13] = 3 }
local live = { [11] = { los = 650 }, [12] = { los = 480, radar = 2300 }, [13] = {} }
local active = nil
Spring = setmetatable({
	GetSelectedUnits = function() return sel end, GetTeamUnits = function() return { 11, 12, 13, 14 } end, GetMyTeamID = function() return 0 end,
	GetUnitDefID = function(u) return units[u] or 1 end, GetUnitPosition = function(u) return u * 100, 0, u * 100 end,
	GetUnitSensorRadius = function(u, k) return (live[u] or { los = 500 })[k] or 0 end,
	GetUnitIsBeingBuilt = function() return false end, GetActiveCommand = function() if active then return 1, active end end,
	GetMouseState = function() return 10, 10 end, TraceScreenRay = function() return "ground", { 700, 0, 700 } end,
	Echo = function() end,
}, { __index = function() return function() end end })
widgetHandler = { AddAction = function() end, RemoveAction = function() end }
local w = {}; setmetatable(w, { __index = _G }); w.widget = w
local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/vb_ranges.lua")); setfenv(chunk, w); chunk()
local fails = 0
local function check(n, ok, i) print((ok and "ok    " or "FAIL  ") .. n .. (i and ("  (" .. tostring(i) .. ")") or "")); if not ok then fails = fails + 1 end end
local function has(r) for _, c in ipairs(circles) do if c == r then return true end end return false end
w:Initialize()
w:DrawWorld()
check("selected: LIVE sight radius is used (650, not the def's 500)", has(650) and not has(500), table.concat(circles, ","))
check("selected: a radar unit gets its sight AND its radar circle", has(480) and has(2300))
check("selected: a unit with no sensors draws nothing; 3 units -> 3 circles", #circles == 3, #circles)
active = -5; circles = {}
w:DrawWorld()
check("placing a structure shows its ranges at the mouse (300 sight, 1000 radar) on top of the selection", has(300) and has(1000) and #circles == 5, #circles)
active = nil
w:TextCommand("vbranges"); circles = {}; w:DrawWorld()
check("all: the whole team is drawn (stacks on one spot drawn once)", #circles >= 3, #circles)
w:TextCommand("vbranges"); circles = {}; w:DrawWorld()
check("off: nothing is drawn", #circles == 0, #circles)
w:TextCommand("vbranges")
check("mode is saved", w:GetConfigData().mode == "selected")
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("ranges test failed") end
