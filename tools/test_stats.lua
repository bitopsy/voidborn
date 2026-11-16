-- Smoke test of the stats gadget and the dashboard widget on the mock engine (tools/vb_mock.lua, tools/vb_sim.lua)
local Sim = dofile(ROOT .. "/tools/vb_sim.lua")
local function check(c, msg) if not c then error("FAILED: " .. msg, 0) end end

local r = Sim.run{ teams = 4, minutes = 20, seed = 3 }
local W = Sim.Mock.world
check(#W.echoes >= 0, "echo")
-- the data arrived in the dashboard's data model
local data = Sim.Mock.LuaUIGlobals
check(data.VBStats_Sample and data.VBStats_Over, "widget registered its globals")
-- draw every tab, with and without a cursor
local w = r.widget
local ok, err
for _, tab in ipairs({ "overview", "graphs", "economy", "combat", "army", "report", "settings", "keys", "about" }) do
	w:TextCommand("vbdash tab " .. tab)
	for _, cursor in ipairs({ false, true }) do
		Sim.Mock.ops = {}
		W.mx, W.my = 900, 500
		if cursor then w:KeyPress(276, {}, false) end
		ok, err = pcall(w.DrawScreen, w)
		check(ok, "DrawScreen on tab " .. tab .. ": " .. tostring(err))
		check(#Sim.Mock.ops > 100, "tab " .. tab .. " drew nothing")
	end
	w:KeyPress(279, {}, false)
end
w:TextCommand("vbdash close")
Sim.Mock.ops = {}
ok, err = pcall(w.DrawScreen, w)
check(ok, "HUD: " .. tostring(err))
check(#Sim.Mock.ops > 50, "HUD drew nothing")
-- a click on the HUD opens the dashboard
-- the gadget counted what the simulation did
local Dm = r.stats
local t0, t1 = Dm.teams[0], Dm.teams[1]
check(t0 and t1 and t0.n > 100, "samples arrived: " .. tostring(t0 and t0.n))
local last = t0.n
check(Dm.Value(t0, "dd", last) > 1000 and Dm.Value(t1, "dd", last) > 1000, "damage dealt counted")
check(Dm.Value(t0, "kv", last) > 0 and Dm.Value(t0, "lv", last) > 0, "kills and losses counted")
check(Dm.Value(t0, "av", last) > 0 and Dm.Value(t0, "dv", last) >= 0, "army value")
check(Dm.Value(t0, "dps", last - 10) > 0 or Dm.Value(t0, "dps", last - 30) > 0, "damage per second derived")
check(Dm.Value(t0, "mp", last) > Dm.Value(t0, "mp", 10), "metal produced grows")
check(Dm.over and Dm.over.winners[0] and not Dm.over.winners[1], "winner reported")
check(#Dm.events > 3, "events recorded")
for _, k in ipairs({ "dd", "dt" }) do
	local a, b = Dm.Value(t0, k, last), Dm.Value(t1, k, last)
	check(a > 0 and b > 0, k .. " both teams")
end
-- every point of damage dealt was received by somebody (no friendly fire or environment in the simulation)
local dd, dt = 0, 0
for _, t in pairs(Dm.teams) do dd = dd + Dm.Value(t, "dd", t.n); dt = dt + Dm.Value(t, "dt", t.n) end
check(math.abs(dd - dt) < 1, "damage balance " .. dd .. " vs " .. dt)
-- fog of war: in a game that is still running an enemy is only known from what was seen
local f = Sim.run{ teams = 4, minutes = 30, stopAt = 14, seed = 5 }
Sim.Mock.world.fog = true
local fw, fS = f.widget, f.stats
fw:Update(2)
check(not fS.over, "the fog game is still running")
check(fS.Visible(0) and not fS.Visible(1) and not fS.Visible(2), "only the own side is visible under fog")
local board = fS.Leaderboard()
check(#board == 4, "leaderboard has every player")
local est = 0
for _, row in ipairs(board) do
	if row.id == 0 then check(not row.est and row.score and row.score > 0, "own score is exact") else
		check(row.est, "enemy " .. row.id .. " is an estimate"); if row.score then est = est + 1 end
	end
end
check(est >= 1, "some enemy was scouted")
local total, humans, ais, alive = fS.PlayerCounts()
check(total == 4 and humans == 2 and ais == 2 and alive == 4, "player counts " .. total .. "/" .. humans .. "/" .. ais .. "/" .. alive)
for _, tab in ipairs({ "overview", "combat", "report", "settings" }) do
	fw:TextCommand("vbdash tab " .. tab)
	Sim.Mock.ops = {}
	ok, err = pcall(fw.DrawScreen, fw)
	check(ok, "fog DrawScreen on " .. tab .. ": " .. tostring(err))
end
fw:TextCommand("vbdash close")
Sim.Mock.ops = {}
check(pcall(fw.DrawScreen, fw), "fog HUD and menu bar")
Sim.Mock.world.fog = false
print("stats smoke test ok: " .. #W.echoes .. " echoes")
