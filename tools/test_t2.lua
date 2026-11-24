-- Mock-engine test of LuaRules/Gadgets/vb_factory_upgrade.lua.  Run:  python3 tools/test_t2.py   (GADGET is set by the runner)
local res, rules, msgs, created, destroyed, cmds, swaps = { metal = 1e6, energy = 1e6 }, {}, {}, {}, {}, {}, {}
local alive, frame = { [10] = true }, 0
UnitDefs = { [1] = { id = 1, name = "mw_hive", humanName = "Brood Hive", customParams = { upgrade_to = "mw_hive2", upgrade_metal = "2000", upgrade_energy = "2800", upgrade_seconds = "45", kind = "fac" } },
             [2] = { id = 2, name = "mw_hive2", humanName = "Great Brood Hive", customParams = { tier = "2", kind = "fac2" } } }
UnitDefNames = { mw_hive = UnitDefs[1], mw_hive2 = UnitDefs[2] }
CMDTYPE = { ICON = 1 }
local cheats, modopt = false, nil
Spring = {
	GetModOptions = function() return { vb_forge_needs_t2 = modopt } end,
	SetGameRulesParam = function(k, v) rules[k] = v end, SetTeamRulesParam = function(_, k, v) rules[k] = v end,
	SetUnitRulesParam = function() end, GetTeamList = function() return { 0 } end, GetAllUnits = function() return {} end,
	GetUnitDefID = function() return 1 end, GetUnitTeam = function() return 0 end, GetUnitIsBeingBuilt = function() return false end,
	FindUnitCmdDesc = function(u, id) return cmds[u] and 1 or nil end,
	InsertUnitCmdDesc = function(u, d) cmds[u] = d end, EditUnitCmdDesc = function(u, i, t) for k, v in pairs(t) do cmds[u][k] = v end end,
	GetGameFrame = function() return frame end, SendMessageToTeam = function(_, m) msgs[#msgs + 1] = m end,
	GetTeamResources = function(_, r) return res[r] end, UseTeamResource = function(_, r, a) res[r] = res[r] - a end,
	AddTeamResource = function(_, r, a) res[r] = res[r] + a end, ValidUnitID = function(id) return alive[id] end,
	GetUnitPosition = function() return 100, 0, 100 end, GetUnitBuildFacing = function() return 1 end, GetUnitHealth = function() return 500, 1000 end,
	DestroyUnit = function(id) alive[id] = nil; destroyed[#destroyed + 1] = id; gadget:UnitDestroyed(id, 1, 0) end,
	CreateUnit = function(d) created[#created + 1] = d; alive[100 + #created] = true; return 100 + #created end,
	SetUnitHealth = function() end, IsCheatingEnabled = function() return cheats end }
unsyncedMsgs = {}
SendToUnsynced = function(...) unsyncedMsgs[#unsyncedMsgs + 1] = { ... } end
gadgetHandler = { IsSyncedCode = function() return true end }
GG = { VB_FactorySwap = function(o, n) swaps[#swaps + 1] = { o, n } end }
gadget = {}
dofile(GADGET)
gadget:Initialize()
local fails = 0
local function check(n, ok, info) print((ok and "ok    " or "FAIL  ") .. n .. (info and ("  (" .. tostring(info) .. ")") or "")); if not ok then fails = fails + 1 end end
local function run(n) for _ = 1, n do frame = frame + 1; gadget:GameFrame(frame) end end

check("gate on by default", rules.vb_t2_gate == 1)
check("forge locked at the start", GG.VB_ForgeUnlocked(0) == false)
gadget:UnitFinished(10, 1, 0)
check("finished T1 factory gets the Upgrade T2 button", cmds[10] and cmds[10].name == "Upgrade T2")
check("order is consumed by the gadget", gadget:AllowCommand(10, 1, 0, 34920) == false)
check("other orders pass", gadget:AllowCommand(10, 1, 0, 40) == true)   -- (this toggled nothing: it is a different id)
check("factory reports busy", GG.VB_FactoryBusy(10) == true)
run(30 * 22)
check("half way after ~22 s", (rules.vbu_list or ""):match("^10:(%d+)") and tonumber(rules.vbu_list:match("^10:(%d+)")) > 450, rules.vbu_list)
check("about half the price paid", math.abs((1e6 - res.metal) - 1000) < 60, 1e6 - res.metal)
gadget:AllowCommand(10, 1, 0, 34920)       -- cancel
check("cancel refunds everything", math.abs(res.metal - 1e6) < 1e-3 and math.abs(res.energy - 1e6) < 1e-3)
check("cancel frees the factory", not GG.VB_FactoryBusy(10) and cmds[10].name == "Upgrade T2")

-- stall
res.metal, res.energy = 0, 0
gadget:AllowCommand(10, 1, 0, 34920); run(60)
check("no resources: stalled", rules.vbu_list:find(":s") ~= nil, rules.vbu_list)
res.metal, res.energy = 1e6, 1e6
run(30 * 46)
check("T2 factory created at the same spot", created[1] == 2 and destroyed[1] == 10, #created)
local sndStart, sndDone = false, false
for _, m in ipairs(unsyncedMsgs) do if m[1] == "vbfacup" and m[3] == "start" then sndStart = true end; if m[1] == "vbfacup" and m[3] == 2 then sndDone = true end end
check("upgrade start sound is sent", sndStart)
check("T2 ready sound is sent when the upgrade finishes", sndDone)
check("queue lines handed over", swaps[1] and swaps[1][1] == 10 and swaps[1][2] == 101)
check("total paid = the price", math.abs((1e6 - res.metal) - 2000) < 5 and math.abs((1e6 - res.energy) - 2800) < 5, (1e6 - res.metal) .. "/" .. (1e6 - res.energy))
gadget:UnitFinished(101, 2, 0)
check("forge unlocked with a T2 factory", GG.VB_ForgeUnlocked(0) == true and rules.vb_t2 == 1)
gadget:UnitDestroyed(101, 2, 0)
check("forge locks again when it dies", GG.VB_ForgeUnlocked(0) == false and rules.vb_t2 == 0)
cheats = true
check("cheats open the forge", GG.VB_ForgeUnlocked(0) == true)
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("failed") end
