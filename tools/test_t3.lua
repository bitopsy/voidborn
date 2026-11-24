-- Mock-engine test of the Tier 2 -> Tier 3 upgrade in LuaRules/Gadgets/vb_factory_upgrade.lua.  Run:  python3 tools/test_t3.py
local res, rules, msgs, created, destroyed, cmds = { metal = 1e6, energy = 1e6 }, {}, {}, {}, {}, {}
local alive, frame = { [10] = true }, 0
UnitDefs = { [1] = { id = 1, name = "mw_hive2", humanName = "Great Brood Hive", customParams = { tier = "2", kind = "fac2", upgrade_to = "mw_hive3", upgrade_metal = "4500", upgrade_energy = "7500", upgrade_seconds = "70", upgrade_tier = "3" } },
             [2] = { id = 2, name = "mw_hive3", humanName = "Primeval Brood Hive", customParams = { tier = "3", kind = "fac3" } } }
UnitDefNames = { mw_hive2 = UnitDefs[1], mw_hive3 = UnitDefs[2] }
CMDTYPE = { ICON = 1 }
Spring = {
	GetModOptions = function() return {} end,
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
	SetUnitHealth = function() end, IsCheatingEnabled = function() return false end }
unsyncedMsgs = {}
SendToUnsynced = function(...) unsyncedMsgs[#unsyncedMsgs + 1] = { ... } end
gadgetHandler = { IsSyncedCode = function() return true end }
GG = { VB_FactorySwap = function() end }
gadget = {}
dofile(GADGET)
gadget:Initialize()
local fails = 0
local function check(n, ok, info) print((ok and "ok    " or "FAIL  ") .. n .. (info and ("  (" .. tostring(info) .. ")") or "")); if not ok then fails = fails + 1 end end
local function run(n) for _ = 1, n do frame = frame + 1; gadget:GameFrame(frame) end end

gadget:UnitFinished(10, 1, 0)
check("a finished T2 lab gets the Upgrade T3 button", cmds[10] and cmds[10].name == "Upgrade T3", cmds[10] and cmds[10].name)
check("the tooltip names Tier 3 and the price", cmds[10].tooltip:find("Tier 3") and cmds[10].tooltip:find("4500") and cmds[10].tooltip:find("7500"))
check("a T2 lab counts for the forge", rules.vb_t2 == 1 and rules.vb_t3 == 0, tostring(rules.vb_t2) .. "/" .. tostring(rules.vb_t3))
check("the order is consumed", gadget:AllowCommand(10, 1, 0, 34920) == false)
check("the lab is busy and the label says T3", GG.VB_FactoryBusy(10) == true and cmds[10].name:find("^T3 "))
run(30 * 35)
local m = tonumber((rules.vbu_list or ""):match("^10:(%d+)") or 0)
check("about half way after 35 s of 70", m > 450 and m < 550, rules.vbu_list)
check("about half the T3 price paid", math.abs((1e6 - res.metal) - 2250) < 120, 1e6 - res.metal)
gadget:AllowCommand(10, 1, 0, 34920)
check("cancel refunds everything", math.abs(res.metal - 1e6) < 1e-3 and math.abs(res.energy - 1e6) < 1e-3)
check("cancel restores the Upgrade T3 label", cmds[10].name == "Upgrade T3")
gadget:AllowCommand(10, 1, 0, 34920); run(30 * 71)
check("the T3 lab is created at the same spot, the T2 lab leaves", created[1] == 2 and destroyed[1] == 10)
check("total paid = 4500 metal + 7500 energy", math.abs((1e6 - res.metal) - 4500) < 5 and math.abs((1e6 - res.energy) - 7500) < 5, (1e6 - res.metal) .. "/" .. (1e6 - res.energy))
check("the old T2 lab no longer counts", rules.vb_t2 == 0, rules.vb_t2)
gadget:UnitFinished(101, 2, 0)
check("the finished T3 lab keeps the forge open and counts as T3", GG.VB_ForgeUnlocked(0) == true and rules.vb_t2 == 1 and rules.vb_t3 == 1, tostring(rules.vb_t2) .. "/" .. tostring(rules.vb_t3))
check("the message says the heavy is unlocked", msgs[#msgs] and msgs[#msgs]:find("T3 heavy"), msgs[#msgs])
check("a T3 lab has no further upgrade button", cmds[101] == nil)
gadget:UnitDestroyed(101, 2, 0)
check("losing the T3 lab clears both counts", rules.vb_t2 == 0 and rules.vb_t3 == 0)
print(fails == 0 and "\nALL PASSED" or ("\n" .. fails .. " FAILED"))
if fails > 0 then error("failed") end
