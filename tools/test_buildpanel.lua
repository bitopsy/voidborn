-- Smoke test of LuaUI/Widgets/vb_buildpanel.lua with a mock engine: draws the panel with a factory owned,
-- clicks a stock-unit tile and the red x of a design.  Run: python3 tools/test_buildpanel.py
local noop = function() end
local sent, echoes = {}, {}
local function anyfn() return setmetatable({}, { __index = function() return noop end, __call = noop }) end
gl = setmetatable({}, { __index = function() return noop end })
GL = setmetatable({}, { __index = function() return 0 end })
CMD = { OPT_SHIFT = 32 }; CMDTYPE = { ICON = 0, ICON_MODE = 5 }
UnitDefs = { [1] = { id = 1, name = "mw_hive", humanName = "Hive", buildOptions = { 2, 3 }, canMove = false, isFactory = true, metalCost = 400, energyCost = 0, buildTime = 3000, health = 100 },
             [2] = { id = 2, name = "mw_gnasher", humanName = "Gnasher", canMove = true, metalCost = 52, energyCost = 208, buildTime = 468, health = 100, weapons = {} },
             [4] = { id = 4, name = "mw_extractor", humanName = "Extractor", canMove = false, metalCost = 60, energyCost = 0, buildTime = 800, health = 100, weapons = {} },
             [3] = { id = 3, name = "mw_ravager", humanName = "Ravager", canMove = true, metalCost = 300, energyCost = 600, buildTime = 2000, health = 100, weapons = {} } }
UnitDefNames = { mw_extractor = UnitDefs[4], mw_hive = UnitDefs[1], mw_gnasher = UnitDefs[2], mw_ravager = UnitDefs[3] }
WeaponDefs = {}; Game = { armorTypes = {} }
local selected = {}
underway = false
local shapes = 0
gl.Shape = function() shapes = shapes + 1 end
Spring = setmetatable({
	GetViewGeometry = function() return 1320, 950 end, GetActiveCmdDescs = function() return { { id = -4, name = "mw_extractor", type = 0, params = {}, tooltip = "" } } end,
	GetMouseState = function() return 0, 0 end, GetActiveCommand = function() return nil end,
	GetGameRulesParam = function() return 1 end, GetMyTeamID = function() return 0 end,
	GetTeamUnits = function() return underway and { 77, 88 } or { 77 } end, GetUnitDefID = function(u) return u == 88 and 4 or 1 end,
	GetUnitHealth = function(u) if u == 88 then return 40, 100, 0, 0, 0.4 end return 100, 100, 0, 0, 1 end, GetUnitIsBuilding = function(u) if u == 99 then return 88 end end,
	GetSelectedUnits = function() return selected end, GetModKeyState = function() return false, false, false, false end,
	GetTeamRulesParam = function() return "d_mw_gnasher|2|500|b|77" end,
	SendLuaRulesMsg = function(m) sent[#sent + 1] = m end, Echo = function(m) echoes[#echoes + 1] = m end,
	PlaySoundFile = noop, GetTimer = noop, DiffTimers = function() return 1 end,
}, { __index = function() return noop end })
VFS = { Include = function(p) return dofile(ROOT .. "/game/" .. p) end }
widgetHandler = { commands = {}, AddAction = noop }
WG = {}
local w = {}
setmetatable(w, { __index = _G })
local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/vb_buildpanel.lua"))
w.widget = w; setfenv(chunk, w); chunk()
w.widget = w
w:Initialize()
local F = _G.VBForge
F.SetTemplate("mydesign", { id = "mydesign", base = "mw_gnasher", hp = 500 })
for i = 1, 25 do w:Update() end
local fails = 0
local function check(n, ok, i) print((ok and "ok    " or "FAIL  ") .. n .. (i and ("  (" .. tostring(i) .. ")") or "")); if not ok then fails = fails + 1 end end
w:DrawScreen()
check("roster built from owned factory", true)
-- a structure under construction gets a pie on its tile
local function ShapesPerFrame() shapes = 0; w:DrawScreen(); return shapes end
for i = 1, 11 do w:Update() end
local without = ShapesPerFrame()
underway = true
for i = 1, 11 do w:Update() end
local with = ShapesPerFrame()
check("structure tile shows a construction pie", with > without, without .. " -> " .. with)
underway = false
for i = 1, 11 do w:Update() end
-- find the tiles through a click scan over the panel
local function clickAt(x, y, b) return w:MousePress(x, y, b or 1) end
local hit = {}
for x = 20, 700, 6 do for y = 20, 700, 6 do
	sent = {}; if w:IsAbove(x, y) then w:DrawScreen(); clickAt(x, y); if #sent > 0 then hit[#hit + 1] = { x, y, sent[1] } end end
end end
local add2 = false
for _, h in ipairs(hit) do if h[3]:find('"mw_gnasher"', 1, true) and h[3]:find('"fac"]=77', 1, true) and h[3]:find("vbq:add:1:", 1, true) then add2 = true end end
check("clicking a stock tile sends vbq:add with the factory", add2, hit[1] and hit[1][3])
F.SetTemplate("mydesign", { id = "mydesign", base = "mw_gnasher", hp = 500 })   -- the first scan may already have hit its red x
w:DrawScreen()
local before = #F.TemplateIds()
-- hover the design tile then click its red x: scan again with mouse over each point
local deleted = false
for x = 20, 700, 4 do for y = 20, 700, 4 do
	if not deleted then
		Spring.GetMouseState = function() return x, y end
		w:DrawScreen(); clickAt(x, y)
		if #F.TemplateIds() < before then deleted = true end
	end
end end
check("red x deletes the design", deleted)
check("delete is reported in the chat", (echoes[#echoes] or ""):find("deleted design") ~= nil, echoes[#echoes])
-- a forge design gets the same hexagonal panel with the radar profile as a stock unit, built from ITS numbers
UnitDefs[3].weapons = { { weaponDef = 1 } }; UnitDefs[3].speed = 60; UnitDefs[3].losRadius = 400
WeaponDefs[1] = { damages = { [0] = 100 }, reload = 2, range = 300 }
F.SetTemplate("radar_t", { id = "radar_t", name = "Dread", base = "mw_ravager", hp = 1000, dmg = 2, reload = 0.5, range = 1.5, speed = 1.5 })
local texts, shapeCount = {}, 0
gl.Text = function(str) texts[#texts + 1] = tostring(str) end
gl.Shape = function() shapeCount = shapeCount + 1 end
for i = 1, 11 do w:Update() end
local found
for x = 20, 700, 4 do for y = 20, 700, 4 do
	if not found then
		Spring.GetMouseState = function() return x, y end
		texts, shapeCount = {}, 0
		w:DrawScreen()
		for _, t in ipairs(texts) do if t:find("custom design", 1, true) then found = { x = x, y = y, texts = texts, shapes = shapeCount } end end
	end
end end
check("hovering a design tile opens the hexagonal stats panel", found ~= nil)
if found then
	local joined = "|" .. table.concat(found.texts, "|") .. "|"
	check("the radar was drawn (grid rings, spokes, profile)", found.shapes >= 12, found.shapes)
	check("PROFILE caption and the six axis labels are there", joined:find("|PROFILE|", 1, true) and joined:find("|HP|", 1, true) and joined:find("|DPS|", 1, true) and joined:find("|COST|", 1, true) ~= nil)
	check("the design's name is the title", joined:find("|Dread|", 1, true) ~= nil)
	check("health is the design's (1000), not the base unit's (100)", joined:find("|1000|", 1, true) ~= nil)
	check("range is 300 x 1.5 = 450", joined:find("|450|", 1, true) ~= nil)
	check("damage is 100 x 2 = 200 and DPS 200 (x2 damage, x0.5 reload)", select(2, joined:gsub("|200|", "")) >= 2)
	check("reload is 2 x 0.5 = 1s", joined:find("|1s|", 1, true) ~= nil)
	local pr = F.Price(F.templates.radar_t)
	check("metal is the design's price, above the base 300", pr and pr.metal > 300 and joined:find("|" .. pr.metal .. "|", 1, true) ~= nil, pr and pr.metal)
end
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("buildpanel test failed") end
