-- Mock-engine test of LuaRules/Gadgets/vb_dev_queue.lua.  Run:  python3 tools/test_queue.py
-- Globals GADGET and HDR (paths) are set by the runner.
local res, created, rules, spawned, msgs = { metal = 1e6, energy = 1e6 }, {}, {}, {}, {}
local alive = { [77] = true, [78] = true, [79] = true, [80] = true, [81] = true }
local defOf = { [80] = 4, [81] = 4 }          -- 80 and 81 are tier 2 labs, every other unit is the tier 1 hive
local building = {}          -- unitID -> true while the unit is still under construction
UnitDefs = { [1] = { id = 1, name = "mw_hive", buildOptions = { 2 }, canMove = false, isFactory = true, metalCost = 400, energyCost = 0, buildTime = 3000, health = 100 },
             [2] = { id = 2, name = "mw_gnasher", canMove = true, metalCost = 52, energyCost = 208, buildTime = 468, health = 100, losRadius = 100 },
             [3] = { id = 3, name = "mw_leviathan", canMove = true, metalCost = 900, energyCost = 0, buildTime = 9000, health = 100 },
             [4] = { id = 4, name = "mw_hive2", buildOptions = { 2, 3 }, canMove = false, isFactory = true, metalCost = 2400, energyCost = 0, buildTime = 3000, health = 100,
                     customParams = { tier = "2" } } }
UnitDefNames = { mw_hive = UnitDefs[1], mw_gnasher = UnitDefs[2], mw_leviathan = UnitDefs[3] }
Game = { mapSizeX = 8192, mapSizeZ = 8192 }
CMD = { MOVE = 10 }
VFS = { Include = function() return dofile(HDR) end }
local forgeOn, cheats = true, false
Spring = {
	GetPlayerInfo = function() return "p", true, false, 0 end,
	SetTeamRulesParam = function(_, k, v) rules[k] = v end, SetGameRulesParam = function() end,
	GetTeamResources = function(_, r) return res[r] end,
	UseTeamResource = function(_, r, a) res[r] = res[r] - a end, AddTeamResource = function(_, r, a) res[r] = res[r] + a end,
	ValidUnitID = function(id) return alive[id] end, GetUnitTeam = function() return 0 end,
	GetUnitPosition = function() return 1000, 0, 1000 end, GetUnitRadius = function() return 40 end,
	GetUnitDefID = function(id) return defOf[id] or 1 end, GetGroundHeight = function() return 0 end,
	CreateUnit = function(d) created[#created + 1] = d; return #created end,
	GiveOrderToUnit = function() end, GetTeamStartPosition = function() return 500, 0, 500 end,
	SendMessageToPlayer = function(_, m) msgs[#msgs + 1] = m end, Echo = function() end,
	GetUnitIsBeingBuilt = function(id) return building[id] == true end }
gadgetHandler = { IsSyncedCode = function() return true end }
GG = { VB_ForgeAllowed = function() return forgeOn or cheats end, VB_DevAllowed = function() return cheats end,
       VB_QueueSpawn = function(spec) spawned[#spawned + 1] = spec end }
local g = {}; gadget = g
dofile(GADGET)
g:Initialize()

local fails = 0
local function check(name, ok, info) print((ok and "ok    " or "FAIL  ") .. name .. (info and ("  (" .. tostring(info) .. ")") or "")); if not ok then fails = fails + 1 end end
local frame = 0
local function run(maxf, stop) for _ = 1, maxf do frame = frame + 1; g:GameFrame(frame); if stop and stop() then break end end end
local function add(n, spec) g:RecvLuaMsg("vbq:add:" .. n .. ":" .. spec, 0); run(1) end   -- state is published on the next frame

-- 1. two factories build side by side, each at its own rate
add(2, '{["base"]="mw_gnasher",["fac"]=77,["id"]="d_mw_gnasher",["plain"]=1}')
add(2, '{["base"]="mw_gnasher",["fac"]=78,["id"]="d_mw_gnasher",["plain"]=1}')
run(3000, function() return #created >= 4 end)
check("2 factories x 2 gnashers finish in ~10 s (parallel)", #created == 4 and frame < 30 * 12, frame / 30 .. " s")

-- 2. a factory cannot build what it does not offer, nor use someone else's/dead id
add(1, '{["base"]="mw_leviathan",["fac"]=77,["id"]="d_mw_leviathan",["plain"]=1}')
add(1, '{["base"]="mw_gnasher",["fac"]=999,["id"]="d_x",["plain"]=1}')
check("invalid orders are ignored", (rules.vbq or "") == "", rules.vbq)

-- 3. per-factory hold / remove addressing
add(3, '{["base"]="mw_gnasher",["fac"]=77,["id"]="d_mw_gnasher",["plain"]=1}')
g:RecvLuaMsg("vbq:hold:1:d_mw_gnasher@77", 0); run(1)
check("hold shows as h", (rules.vbq or ""):find("|h|77", 1, true) ~= nil, rules.vbq)
g:RecvLuaMsg("vbq:rem:1:d_mw_gnasher@77", 0); run(1)
check("remove takes one out", (rules.vbq or ""):find("d_mw_gnasher|2|") ~= nil, rules.vbq)

-- 4. a factory that is still being built: the unit waits for it and says so
local n0c, metal0 = #created, res.metal
building[79] = true
add(1, '{["base"]="mw_gnasher",["fac"]=79,["id"]="d_mw_gnasher",["plain"]=1}')
run(30 * 10)
check("nothing is produced while the factory is unfinished", #created == n0c, #created - n0c)
check("  ... the entry waits (state p)", (rules.vbq or ""):find("|p|79", 1, true) ~= nil, rules.vbq)
check("  ... and nothing was paid for it", res.metal == metal0, res.metal - metal0)
building[79] = nil
run(3000, function() return #created > n0c end)
check("the unit is built once the factory is finished", #created == n0c + 1, #created - n0c)

-- 5. factory dies: line removed and paid resources refunded
local before = res.metal
run(10)
alive[77] = false
g:UnitDestroyed(77, 1, 0)
g:GameFrame(frame + 1)
check("dead factory's line is gone", (rules.vbq or "") == "", rules.vbq)

-- 6. forge designs: allowed -> spawn at the team start with a sane build time; lua stripped for non-cheaters
local n0 = #spawned
add(1, '{["base"]="mw_gnasher",["id"]="mydesign",["hp"]=500,["lua"]="print(1)"}')
check("forge design queued (modoption on)", (rules.vbq or ""):find("mydesign|1|") ~= nil, rules.vbq)
run(30 * 60, function() return #spawned > n0 end)
local sp = spawned[#spawned]
check("forge design spawned", #spawned == n0 + 1)
check("  ... in a few seconds, not minutes", frame < 30 * 80, frame / 30 .. " s total")
check("  ... lua= removed for a normal player", sp and sp.lua == nil)
check("  ... spawn position set (not map centre)", sp and sp.x and math.abs(sp.x - 4096) > 100, sp and sp.x)

-- 6b. every lab has its own line: designs go to a TIER 2 lab and each such lab keeps its own queue; a design named
--     for a tier 1 lab falls back to the team line; clearing a design without naming a lab clears every line
local function lineOf(id, lab) return (rules.vbq or ""):find(id .. "|%d+|%d+|%a|" .. lab .. "[;$]") or (rules.vbq or ""):find(id .. "|%d+|%d+|%a|" .. lab .. "$") end
add(1, '{["base"]="mw_gnasher",["fac"]=80,["id"]="dA"}')
add(2, '{["base"]="mw_gnasher",["fac"]=81,["id"]="dA"}')
check("a design queued at T2 lab 80 has line 80", lineOf("dA", 80) ~= nil, rules.vbq)
check("the same design at T2 lab 81 is a separate entry with line 81", lineOf("dA", 81) ~= nil, rules.vbq)
add(1, '{["base"]="mw_gnasher",["fac"]=77,["id"]="dB"}')
check("a design named for a tier 1 lab uses the team line (0)", lineOf("dB", 0) ~= nil, rules.vbq)
g:RecvLuaMsg("vbq:rem:1:dA@81", 0); run(1)
check("removing one unit at lab 81 leaves lab 80 alone", lineOf("dA", 80) ~= nil and (rules.vbq or ""):find("dA|1|%d+|%a|81") ~= nil, rules.vbq)
g:RecvLuaMsg("vbq:clear:1:dA", 0); run(1)
check("clearing a design without a lab clears it on every line", (rules.vbq or ""):find("dA") == nil and (rules.vbq or ""):find("dB") ~= nil, rules.vbq)
g:RecvLuaMsg("vbq:clear:1:dB", 0); run(1)

-- 7. modoption off: forge designs refused
forgeOn = false
add(1, '{["base"]="mw_gnasher",["id"]="blocked"}')
check("forge refused when vb_forge is off", (rules.vbq or ""):find("blocked") == nil and #msgs > 0, msgs[#msgs])

print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("queue test failed") end
