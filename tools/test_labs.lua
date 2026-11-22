-- Mock-engine test of the build panel's category sections and per-lab roster/queue.  Run: python3 tools/test_labs.py
local noop = function() end
gl = setmetatable({}, { __index = function() return noop end })
GL = setmetatable({}, { __index = function() return 0 end })
CMD = { OPT_SHIFT = 32 }; CMDTYPE = { ICON = 0, ICON_MODE = 5 }
UnitDefs = {
	[1] = { id = 1, name = "mw_hive", humanName = "Hive", buildOptions = { 2 }, canMove = false, isFactory = true, customParams = { kind = "fac" }, metalCost = 400, energyCost = 0, buildTime = 3000, health = 100 },
	[5] = { id = 5, name = "mw_hive2", humanName = "Hive2", buildOptions = { 2, 3 }, canMove = false, isFactory = true, customParams = { kind = "fac2", tier = "2" }, metalCost = 900, energyCost = 0, buildTime = 3000, health = 100 },
	[2] = { id = 2, name = "mw_gnasher", humanName = "Gnasher", canMove = true, customParams = { kind = "raider" }, metalCost = 52, energyCost = 208, buildTime = 468, health = 100, weapons = {} },
	[3] = { id = 3, name = "mw_ravager", humanName = "Ravager", canMove = true, customParams = { kind = "assault" }, metalCost = 300, energyCost = 600, buildTime = 2000, health = 100, weapons = {} },
	[4] = { id = 4, name = "mw_extractor", humanName = "Extractor", canMove = false, customParams = { kind = "mex" }, metalCost = 60, energyCost = 0, buildTime = 800, health = 100, weapons = {} },
	[6] = { id = 6, name = "mw_sensor", humanName = "Sensor", canMove = false, customParams = { kind = "radar" }, metalCost = 60, energyCost = 0, buildTime = 800, health = 100, weapons = {} },
}
UnitDefNames = {}; for _, d in pairs(UnitDefs) do UnitDefNames[d.name] = d end
WeaponDefs = {}; Game = { armorTypes = {} }
local selected, texts = {}, {}
local defOf = { [77] = 1, [78] = 5 }
Spring = setmetatable({
	GetViewGeometry = function() return 1320, 950 end,
	GetActiveCmdDescs = function() return { { id = -4, name = "mw_extractor", type = 0, params = {}, tooltip = "" }, { id = -6, name = "mw_sensor", type = 0, params = {}, tooltip = "" } } end,
	GetMouseState = function() return 0, 0 end, GetActiveCommand = function() return nil end,
	GetGameRulesParam = function() return 1 end, GetMyTeamID = function() return 0 end,
	GetTeamUnits = function() return { 78, 77 } end, GetUnitDefID = function(u) return defOf[u] end,
	GetUnitHealth = function() return 100, 100, 0, 0, 1 end, GetUnitIsBuilding = function() end,
	GetSelectedUnits = function() return selected end, GetModKeyState = function() return false, false, false, false end,
	GetTeamRulesParam = function() return "d_mw_gnasher|2|500|b|77;d_mw_gnasher|1|100|b|78" end,
	SendLuaRulesMsg = noop, Echo = noop, PlaySoundFile = noop, GetTimer = noop, DiffTimers = function() return 1 end,
}, { __index = function() return noop end })
VFS = { Include = function(p) return dofile(ROOT .. "/game/" .. p) end }
widgetHandler = { commands = {}, AddAction = noop }
WG = {}
local w = {}; setmetatable(w, { __index = _G })
local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/vb_buildpanel.lua"))
w.widget = w; setfenv(chunk, w); chunk(); w.widget = w
w:Initialize()
gl.Text = function(str) texts[#texts + 1] = tostring(str) end
local fails = 0
local function check(n, ok, i) print((ok and "ok    " or "FAIL  ") .. n .. (i and ("  (" .. tostring(i) .. ")") or "")); if not ok then fails = fails + 1 end end
local function frame() texts = {}; for i = 1, 11 do w:Update() end; w:DrawScreen(); return "|" .. table.concat(texts, "|") .. "|" end
local function has(j, s) return j:find("|" .. s .. "|", 1, true) ~= nil end

local j = frame()
check("four category sections are all shown at once", has(j, "ECONOMY") and has(j, "COMBAT") and has(j, "UTILITY") and has(j, "BUILD"))
check("one chip per lab, with its tier", has(j, "LAB 1 T1") and has(j, "LAB 2 T2"))
check("nothing selected: the first lab (T1) is active, only its own queue shows (50%)", has(j, "50%") and not has(j, "10%"))

selected = { 78 }; w:SelectionChanged(); j = frame()
check("T2 lab selected: its own queue shows (10%), not the T1 lab's", has(j, "10%") and not has(j, "50%"))

selected = { 77 }; w:SelectionChanged(); j = frame()
check("T1 lab selected again: back to its queue", has(j, "50%") and not has(j, "10%"))

-- the T1 lab offers 1 unit, the T2 lab 2: the COMBAT count follows the lab (+1 for the [+] tile)
local function combatCount(j) return tonumber(j:match("|COMBAT|(%d+)|")) end
check("T1 lab: COMBAT holds 1 unit + the [+] tile", combatCount(j) == 2, combatCount(j))
selected = { 78 }; w:SelectionChanged(); j = frame()
check("T2 lab: COMBAT holds 2 units + the [+] tile", combatCount(j) == 3, combatCount(j))
check("structures are sorted too: ECONOMY has the mex, UTILITY the radar", j:match("|ECONOMY|1|") ~= nil and j:match("|UTILITY|1|") ~= nil)
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("labs test failed") end
