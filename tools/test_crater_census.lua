-- Mock-engine test of vb_crater.lua (ground deformation) and the census drawer (vb_unitstats.lua).
local noop = function() end
local fails = 0
local function check(n, ok, i) print((ok and "ok    " or "FAIL  ") .. n .. (i and ("  (" .. tostring(i) .. ")") or "")); if not ok then fails = fails + 1 end end

-- ---------------------------------------------------------------- crater
Game = { mapSizeX = 4096, mapSizeZ = 4096, squareSize = 8 }
local heights, watched = {}, {}
WeaponDefNames = { vb_big = { id = 7, damageAreaOfEffect = 170 }, vb_med = { id = 8, damageAreaOfEffect = 70 } }
Script = { SetWatchExplosion = function(id) watched[id] = true end }
GG = {}
gadgetHandler = { IsSyncedCode = function() return true end }
Spring = { GetGroundHeight = function() return 100 end,
	SetHeightMapFunc = function(f) f() end,
	AddHeightMap = function(x, z, h) heights[#heights + 1] = { x = x, z = z, h = h } end }
local g = {}; gadget = g
dofile(ROOT .. "/game/LuaRules/Gadgets/vb_crater.lua")
g:Initialize()
check("both death weapons are watched", watched[7] and watched[8])
g:Explosion(7, 2000, 100, 2000); g:GameFrame()
local centre, rim, minH, maxH = nil, nil, 0, 0
for _, p in ipairs(heights) do
	if p.x == 2000 and p.z == 2000 then centre = p.h end
	if p.h < minH then minH = p.h end; if p.h > maxH then maxH = p.h end
end
check("a vb_big blast on the ground digs (centre goes down)", centre and centre < -5, centre)
check("and raises a rim around the crater", maxH > 0.5, maxH)
check("the crater is bounded (depth <= 48, a few thousand squares)", minH >= -48 and #heights < 12000, #heights)
heights = {}
g:Explosion(7, 2000, 900, 2000); g:GameFrame()
check("a blast high in the air digs nothing", #heights == 0)
GG.VB_Crater(1000, 100, 1000, 30); g:GameFrame()
check("a small blast digs nothing", #heights == 0)
for i = 1, 5 do GG.VB_Crater(500 * i, 100, 500, 1900) end
heights = {}; g:GameFrame()
local n1 = #heights; g:GameFrame()
check("a mass detonation is spread over frames (one crater per frame)", n1 > 0 and #heights > n1)

-- ---------------------------------------------------------------- census drawer
gl = setmetatable({}, { __index = function() return noop end }); GL = setmetatable({}, { __index = function() return 0 end })
UnitDefs = {}; WeaponDefs = {}
local boxed = true
WG = { VBBuildPanel = { Box = function() if boxed then return 12, 300, 400, 500 end end } }
widgetHandler = { AddAction = noop, RemoveAction = noop }
VFS = { Include = function(p) return dofile(ROOT .. "/game/" .. p) end }
Spring = setmetatable({ GetViewGeometry = function() return 1920, 1080 end, GetMouseState = function() return 0, 0 end, Echo = noop,
	GetSelectedUnitsCount = function() return 0 end, GetGameFrame = function() return 0 end }, { __index = function() return noop end })
local w = {}; setmetatable(w, { __index = _G })
local chunk = assert(loadfile(ROOT .. "/game/LuaUI/Widgets/vb_unitstats.lua"))
w.widget = w; setfenv(chunk, w); chunk(); w.widget = w
w:Initialize()
check("census loads enabled by default", w.widget.GetInfo and w:GetInfo().enabled == true)
check("closed: the drawer takes only the tab's width", WG.VBCensus.Width() == 18, WG.VBCensus.Width())
w:DrawScreen()
check("the CENSUS tab sits on the right edge of the build menu", w:IsAbove(12 + 400 + 5, 300 + 500 - 40))
w:MousePress(12 + 400 + 5, 300 + 500 - 40, 1)
for _ = 1, 60 do w:Update(0.03) end
check("clicking the tab slides the drawer out", WG.VBCensus.Width() > 300, WG.VBCensus.Width())
w:DrawScreen()
check("the drawer itself takes clicks", w:IsAbove(12 + 400 + 18 + 100, 300 + 50))
boxed = false
for _ = 1, 3 do w:Update(0.03) end
check("without the build menu the drawer takes no room", WG.VBCensus.Width() == 0)
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("crater/census test failed") end
