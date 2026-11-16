--[[
  Voidborn statistics: the data side of the dashboard (no drawing in here).

    local Stats = VFS.Include("LuaUI/Headers/vb_stats_data.h.lua")

  LuaRules/Gadgets/vb_stats.lua measures every team every 5 seconds and sends the results; the dashboard
  widget forwards them to Stats.OnSample / OnUnits / OnDefs / OnEvent / OnOver. This file keeps them as one
  column per statistic (team.v.av[i] is the army value of sample i), knows what every statistic is called
  and how it is written, and derives the ones the gadget does not send (damage per second, ratios ...).

  A statistic the gadget starts to send shows up in team.v without any change here; it is only drawn once
  it is listed in METRICS below.
]]

local S = {}

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local FPS = 30

S.teams   = {}      -- teamID -> team record
S.order   = {}      -- teamIDs, ascending
S.events  = {}      -- { frame, teamID, kind, defID, otherTeamID }
S.over    = nil     -- { frame = f, winners = { [allyTeamID] = true } } when the game has ended
S.version = 0       -- grows with every change: caches key on it
S.lastFrame = 0

--------------------------------------------------------------------------------
-- writing numbers
--------------------------------------------------------------------------------
function S.Num(v, dec)
	v = tonumber(v) or 0
	local a = abs(v)
	if a >= 1e9 then return string.format("%.2fB", v / 1e9) end
	if a >= 1e6 then return string.format("%.2fM", v / 1e6) end
	if a >= 1e4 then return string.format("%.1fk", v / 1e3) end
	if dec then return string.format("%." .. dec .. "f", v) end
	if a >= 1000 then return string.format("%.0f", v) end
	if a >= 100 or abs(v - floor(v + 0.5)) < 0.05 then return string.format("%.0f", v) end
	return string.format("%.1f", v)
end
function S.Rate(v)
	v = tonumber(v) or 0
	if abs(v) >= 1000 then return S.Num(v) end
	return string.format("%.1f", v)
end
function S.Signed(v)
	v = tonumber(v) or 0
	return (v > 0 and "+" or "") .. S.Rate(v)
end
function S.Pct(v) return string.format("%.0f%%", tonumber(v) or 0) end
function S.Ratio(v)
	v = tonumber(v) or 0
	if v >= 100 then return ">99" end
	return string.format("%.2f", v)
end
function S.Time(frame)
	local s = floor((frame or 0) / FPS)
	local h = floor(s / 3600)
	local m = floor((s % 3600) / 60)
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
	return string.format("%d:%02d", m, s % 60)
end
S.FORMATS = { num = S.Num, rate = S.Rate, signed = S.Signed, pct = S.Pct, ratio = S.Ratio, int = function(v) return string.format("%.0f", tonumber(v) or 0) end }

--------------------------------------------------------------------------------
-- the statistics
--------------------------------------------------------------------------------
-- id, label, group, format, [key | fn(v, i)], description
-- A "key" statistic is one the gadget sends; a function derives its value from the columns of one team.
local C_METAL, C_ENERGY = { 0.62, 0.78, 1.00 }, { 1.00, 0.88, 0.30 }
local C_DMG, C_TAKEN, C_ARMY, C_DEF, C_BUILD, C_KILL = { 1.00, 0.45, 0.35 }, { 0.80, 0.50, 1.00 }, { 0.40, 0.95, 0.60 }, { 0.35, 0.85, 1.00 }, { 1.00, 0.70, 0.30 }, { 1.00, 0.35, 0.55 }

local function col(v, k, i) return v[k] and v[k][i] or 0 end
local function div(a, b) return a / max(b, 100) end

local METRICS = {
	-- overall
	{ "sc",  "Score",              "sum", "num",    C_BUILD,  function(v, i) return max(0, col(v, "uv", i) + 1.5 * col(v, "kv", i) + 0.05 * col(v, "dd", i) + 0.2 * col(v, "mp", i) - 0.25 * col(v, "lv", i)) end, "Summary of the statistics: value alive + 1.5 x enemy value destroyed + 0.05 x damage dealt + 0.2 x metal produced - 0.25 x value lost" },
	-- economy
	{ "mi",  "Metal income",       "eco", "rate",   C_METAL,  "mi", "Metal produced per second" },
	{ "ei",  "Energy income",      "eco", "rate",   C_ENERGY, "ei", "Energy produced per second" },
	{ "mx",  "Metal spending",     "eco", "rate",   C_METAL,  "mx", "Metal spent per second (building, repairing)" },
	{ "ex",  "Energy spending",    "eco", "rate",   C_ENERGY, "ex", "Energy spent per second" },
	{ "mn",  "Metal net",          "eco", "signed", C_METAL,  function(v, i) return col(v, "mi", i) - col(v, "mx", i) end, "Metal income minus spending. Below zero the stock is running down" },
	{ "en",  "Energy net",         "eco", "signed", C_ENERGY, function(v, i) return col(v, "ei", i) - col(v, "ex", i) end, "Energy income minus spending" },
	{ "ms",  "Metal stored",       "eco", "num",    C_METAL,  "ms", "Metal in the stores" },
	{ "es",  "Energy stored",      "eco", "num",    C_ENERGY, "es", "Energy in the stores" },
	{ "mp",  "Metal produced",     "eco", "num",    C_METAL,  "mp", "All the metal produced so far" },
	{ "ep",  "Energy produced",    "eco", "num",    C_ENERGY, "ep", "All the energy produced so far" },
	{ "mu",  "Metal spent",        "eco", "num",    C_METAL,  "mu", "All the metal spent so far" },
	{ "eu",  "Energy spent",       "eco", "num",    C_ENERGY, "eu", "All the energy spent so far" },
	{ "mw",  "Metal wasted",       "eco", "num",    C_METAL,  "mw", "Metal that overflowed a full store" },
	{ "ew",  "Energy wasted",      "eco", "num",    C_ENERGY, "ew", "Energy that overflowed a full store" },
	{ "mf",  "Metal efficiency",   "eco", "pct",    C_METAL,  function(v, i) return 100 * col(v, "mu", i) / max(col(v, "mp", i), 1) end, "Metal spent as a share of all metal produced. Low means it sat in the store or overflowed" },
	{ "ef",  "Energy efficiency",  "eco", "pct",    C_ENERGY, function(v, i) return 100 * col(v, "eu", i) / max(col(v, "ep", i), 1) end, "Energy spent as a share of all energy produced" },
	{ "bp",  "Build power",        "eco", "num",    C_BUILD,  "bp", "Combined build speed of every builder and factory" },
	{ "mex", "Metal extractors",   "eco", "int",    C_METAL,  "mex", "Number of metal extractors" },
	{ "ev",  "Economy value",      "eco", "num",    C_ENERGY, "ev", "Metal value of the extractors, generators and stores" },
	-- forces
	{ "av",  "Army value",         "mil", "num",    C_ARMY,   "av", "Metal value of the mobile units alive (commanders and builders not counted)" },
	{ "dv",  "Defense value",      "mil", "num",    C_DEF,    "dv", "Metal value of the defensive structures alive" },
	{ "uv",  "Total value",        "mil", "num",    C_BUILD,  "uv", "Metal value of everything alive" },
	{ "ac",  "Army units",         "mil", "int",    C_ARMY,   "ac", "Number of mobile units alive" },
	{ "dc",  "Defenses",           "mil", "int",    C_DEF,    "dc", "Number of defensive structures alive" },
	{ "uc",  "Units and structures", "mil", "int",  C_BUILD,  "uc", "Everything alive" },
	{ "hp",  "Total health",       "mil", "num",    C_ARMY,   "hp", "Health of everything alive" },
	-- combat
	{ "dd",  "Damage dealt",       "cmb", "num",    C_DMG,    "dd", "Damage done to enemy units so far (overkill not counted)" },
	{ "dt",  "Damage received",    "cmb", "num",    C_TAKEN,  "dt", "Damage taken from enemies so far" },
	{ "dps", "Damage per second",  "cmb", "rate",   C_DMG,    "@dd", "Damage dealt per second, averaged over the last 15 seconds" },
	{ "rps", "Damage taken per second", "cmb", "rate", C_TAKEN, "@dt", "Damage received per second, averaged over the last 15 seconds" },
	{ "dr",  "Damage ratio",       "cmb", "ratio",  C_DMG,    function(v, i) return div(col(v, "dd", i), col(v, "dt", i)) end, "Damage dealt per point of damage received. Above 1 the team wins its fights" },
	{ "kv",  "Enemy value killed", "cmb", "num",    C_KILL,   "kv", "Metal value of the enemy units destroyed" },
	{ "lv",  "Value lost",         "cmb", "num",    C_TAKEN,  "lv", "Metal value of the units lost" },
	{ "kc",  "Kills",              "cmb", "int",    C_KILL,   "kc", "Enemy units destroyed" },
	{ "lc",  "Losses",             "cmb", "int",    C_TAKEN,  "lc", "Units lost" },
	{ "kd",  "Trade ratio",        "cmb", "ratio",  C_KILL,   function(v, i) return div(col(v, "kv", i), col(v, "lv", i)) end, "Enemy value killed per point of value lost" },
	{ "bv",  "Value built",        "cmb", "num",    C_BUILD,  "bv", "Metal value of everything finished so far" },
	{ "bc",  "Units built",        "cmb", "int",    C_BUILD,  "bc", "Everything finished so far" },
}
S.METRICS, S.M = {}, {}
for _, m in ipairs(METRICS) do
	local t = { id = m[1], label = m[2], group = m[3], fmt = m[4], color = m[5], src = m[6], desc = m[7] }
	if type(t.src) == "string" and t.src:sub(1, 1) == "@" then t.rate = t.src:sub(2); t.src = nil end
	S.METRICS[#S.METRICS + 1] = t
	S.M[t.id] = t
end
S.GROUPS = { { "sum", "OVERALL" }, { "eco", "ECONOMY" }, { "mil", "FORCES" }, { "cmb", "COMBAT" } }
function S.Format(metric, v)
	local f = S.FORMATS[metric and metric.fmt or "num"] or S.Num
	return f(v)
end

-- the statistics that are running totals: they only ever grow
S.CUMULATIVE = { mp = 1, ep = 1, mu = 1, eu = 1, mw = 1, ew = 1, dd = 1, dt = 1, kv = 1, lv = 1, kc = 1, lc = 1, bv = 1, bc = 1 }

-- the radar charts
S.RADARS = {
	{ id = "combat", name = "COMBAT", axes = { "dd", "dt", "kv", "lv", "av", "dv", "dps", "bv" },
	  short = { dd = "Dmg dealt", dt = "Dmg taken", kv = "Killed", lv = "Lost", av = "Army", dv = "Defense", dps = "Dmg/s", bv = "Built" },
	  hud = { dd = "Dealt", dt = "Taken", kv = "Kills", lv = "Lost", av = "Army", dv = "Def", dps = "DPS", bv = "Built" } },
	{ id = "economy", name = "ECONOMY", axes = { "mi", "ei", "mp", "ep", "mu", "bp", "mex", "ev" },
	  short = { mi = "Metal/s", ei = "Energy/s", mp = "Metal total", ep = "Energy total", mu = "Metal spent", bp = "Build pwr", mex = "Extractors", ev = "Eco value" },
	  hud = { mi = "M/s", ei = "E/s", mp = "M tot", ep = "E tot", mu = "M used", bp = "Build", mex = "Mex", ev = "Eco" } },
}

--------------------------------------------------------------------------------
-- teams
--------------------------------------------------------------------------------
local function Bump() S.version = S.version + 1 end

local function TeamMeta(team)
	local id = team.id
	local name, side
	if Spring.GetTeamInfo then
		local _, leader, _, isAI, sideName, ally = Spring.GetTeamInfo(id, false)
		team.ally = ally or team.ally or id
		side = sideName
		if isAI then
			local _, aiName = Spring.GetAIInfo(id)
			if aiName and aiName ~= "" then name = aiName end
		elseif leader and leader >= 0 then
			local pname = Spring.GetPlayerInfo(leader, false)
			if pname and pname ~= "" then name = pname end
		end
	end
	if Spring.GetTeamColor then
		local r, g, b = Spring.GetTeamColor(id)
		if r then team.color = { r, g, b } end
	end
	team.name = name or team.name or ("Team " .. id)
	team.side = (side and side ~= "") and side or team.side or ""
	if Spring.GetTeamInfo then
		local _, _, dead = Spring.GetTeamInfo(id, false)
		team.dead = dead and true or false
	end
end

function S.Team(id)
	local t = S.teams[id]
	if t then return t end
	t = { id = id, ally = id, name = "Team " .. id, side = "", color = { 0.7, 0.7, 0.7 }, n = 0, f = {}, byFrame = {}, v = {},
		units = {}, defs = { dd = {}, dt = {}, kl = {}, ls = {}, bt = {} }, cache = {} }
	S.teams[id] = t
	S.order[#S.order + 1] = id
	table.sort(S.order)
	TeamMeta(t)
	Bump()
	return t
end

function S.Refresh()
	for _, t in pairs(S.teams) do TeamMeta(t) end
	Bump()
end

-- the colour a team is drawn with: very dark team colours are lifted so they show on the dark background
function S.ViewColor(team)
	local c = team.color
	local r, g, b = c[1], c[2], c[3]
	local lum = 0.3 * r + 0.59 * g + 0.11 * b
	if lum < 0.35 then
		local k = (0.35 - lum) / 0.65 + 0.15
		r, g, b = r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
	end
	return { r, g, b }
end

--------------------------------------------------------------------------------
-- receiving
--------------------------------------------------------------------------------
function S.OnSample(frame, teamID, str)
	frame, teamID = tonumber(frame), tonumber(teamID)
	if not frame or not teamID or type(str) ~= "string" then return end
	local t = S.Team(teamID)
	local i = t.byFrame[frame]
	if not i then
		i = t.n + 1
		-- samples arrive in order; a replay of the history finds every frame already known
		if i > 1 and t.f[i - 1] >= frame then return end
		t.n = i; t.f[i] = frame; t.byFrame[frame] = i
	end
	for k, v in str:gmatch("([%w_]+)=(%-?[%d%.eE+%-]+)") do
		local col = t.v[k]
		if not col then col = {}; t.v[k] = col end
		col[i] = tonumber(v) or 0
	end
	t.cache = {}
	if frame > S.lastFrame then S.lastFrame = frame end
	Bump()
end

local function ParseIdList(str)
	local r = {}
	for id, n in str:gmatch("(%d+):(%-?[%d%.]+)") do r[tonumber(id)] = tonumber(n) end
	return r
end

function S.OnUnits(frame, teamID, str)
	local t = S.teams[tonumber(teamID)]
	local i = t and t.byFrame[tonumber(frame)]
	if i and type(str) == "string" then t.units[i] = ParseIdList(str); Bump() end
end

function S.OnDefs(frame, teamID, kind, str)
	local t = S.teams[tonumber(teamID)]
	if not t or not t.defs[kind] or type(str) ~= "string" then return end
	local i = t.byFrame[tonumber(frame)]
	if not i then return end
	t.defs[kind][i] = ParseIdList(str)
	Bump()
end

function S.OnEvent(frame, teamID, kind, defID, other)
	frame, teamID = tonumber(frame), tonumber(teamID)
	if not frame or not teamID then return end
	for _, e in ipairs(S.events) do          -- a replay sends the same events again
		if e[1] == frame and e[2] == teamID and e[3] == kind then return end
	end
	S.Team(teamID)
	S.events[#S.events + 1] = { frame, teamID, kind, tonumber(defID) or 0, tonumber(other) or -1 }
	Bump()
end

function S.OnOver(frame, winners)
	local w = {}
	if type(winners) == "string" then for a in winners:gmatch("%d+") do w[tonumber(a)] = true end end
	S.over = { frame = tonumber(frame) or S.lastFrame, winners = w }
	Bump()
end

--------------------------------------------------------------------------------
-- reading
--------------------------------------------------------------------------------
-- the index of the last sample at or before `frame` (nil when there is none)
function S.IndexAt(team, frame)
	local n, f = team.n, team.f
	if n == 0 then return nil end
	if not frame or frame >= f[n] then return n end
	if frame < f[1] then return nil end
	local lo, hi = 1, n
	while lo < hi do
		local mid = floor((lo + hi + 1) / 2)
		if f[mid] <= frame then lo = mid else hi = mid - 1 end
	end
	return lo
end

-- the nearest sample, before or after
function S.NearestIndex(team, frame)
	local i = S.IndexAt(team, frame)
	if not i then return team.n > 0 and 1 or nil end
	if i < team.n and (team.f[i + 1] - frame) < (frame - team.f[i]) then return i + 1 end
	return i
end

local SMOOTH = 3            -- samples (= 15 seconds) the per-second figures are averaged over
local function Rates(team, key)
	local c, f, out = team.v[key], team.f, {}
	for i = 1, team.n do
		local j = max(1, i - SMOOTH)
		local dt = (f[i] - f[j]) / FPS
		out[i] = (dt > 0 and c) and max(0, ((c[i] or 0) - (c[j] or 0)) / dt) or 0
	end
	return out
end

-- the whole column of one statistic for one team (cached)
function S.Series(team, id)
	local c = team.cache[id]
	if c then return c end
	local m = S.M[id]
	local out
	if not m then
		out = {}
	elseif m.src then
		if type(m.src) == "string" then
			local col = team.v[m.src] or {}
			out = {}
			for i = 1, team.n do out[i] = col[i] or 0 end
		else
			out = {}
			for i = 1, team.n do out[i] = m.src(team.v, i) end
		end
	elseif m.rate then
		out = Rates(team, m.rate)
	end
	team.cache[id] = out
	return out
end

function S.Value(team, id, i)
	if not i then return 0 end
	local s = S.Series(team, id)
	return s and s[i] or 0
end

function S.Peak(team, id)
	local s, best = S.Series(team, id), 0
	for i = 1, team.n do if s[i] and s[i] > best then best = s[i] end end
	return best
end

-- unit mix at a sample, and the cumulative per-unit-type tables at (or before) a sample
function S.UnitsAt(team, i)
	if not i then return {} end
	for j = i, 1, -1 do if team.units[j] then return team.units[j] end end
	return {}
end
function S.DefsAt(team, kind, i)
	if not i then return {} end
	local d = team.defs[kind]
	for j = i, 1, -1 do if d[j] then return d[j] end end
	return {}
end

function S.UnitName(defID)
	local ud = UnitDefs and UnitDefs[defID]
	return ud and (ud.humanName or ud.name) or ("unit " .. tostring(defID))
end

function S.EventText(e)
	local team = S.teams[e[2]]
	local who = team and team.name or "?"
	local kind = e[3]
	local other = S.teams[e[5]]
	if kind == "firstblood" then return who .. ": first blood" .. (other and (" (" .. other.name .. ")") or "")
	elseif kind == "commander" then return who .. ": commander lost"
	elseif kind == "factory" then return who .. ": first factory"
	elseif kind == "heavy" then return who .. ": first " .. S.UnitName(e[4])
	elseif kind == "tower" then return who .. ": first " .. S.UnitName(e[4]) end
	return who .. ": " .. tostring(kind)
end

-- Fog of war. Whose numbers may the local player see?
--   mod option stats_visibility = "fog" (default): your own side's. Enemies only as far as you have scouted them (see Intel).
--                               = "all": everybody's.
-- Spectators, cheaters and the end of the game show everything. (A courtesy of the UI: every client runs the same
-- simulation, so this is not a secret-keeping device.)
function S.Visible(teamID)
	local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
	if mo.stats_visibility == "all" then return true end
	if S.over then return true end
	if Spring.GetSpectatingState and Spring.GetSpectatingState() then return true end
	if Spring.IsCheatingEnabled and Spring.IsCheatingEnabled() then return true end
	local t = S.teams[teamID]
	return t ~= nil and t.ally == Spring.GetMyAllyTeamID()
end

-- Intel on the teams that are hidden: what has been SEEN of them. Units are remembered by id until they are seen
-- to die or have not been seen for 5 minutes.  intel[teamID] = { units = { [unitID] = { defID, lastSeenFrame } },
-- value, count, lastSeen }
S.intel = {}
local STALE = 300 * FPS
function S.UpdateIntel(frame)
	for _, id in ipairs(S.order) do
		if not S.Visible(id) then
			local I = S.intel[id]
			if not I then I = { units = {}, value = 0, count = 0 }; S.intel[id] = I end
			local ok, list = pcall(Spring.GetTeamUnits, id)      -- under fog the engine only lists what we can see
			if ok and type(list) == "table" then
				for _, u in ipairs(list) do
					local d = Spring.GetUnitDefID(u)               -- nil while it is only a radar blip
					if d then I.units[u] = { d, frame } end
				end
			end
			local v, c = 0, 0
			for u, e in pairs(I.units) do
				if frame - e[2] > STALE then I.units[u] = nil
				else
					local ud = UnitDefs[e[1]]
					v = v + (ud and ud.metalCost or 0); c = c + 1
					if not I.lastSeen or e[2] > I.lastSeen then I.lastSeen = e[2] end
				end
			end
			I.value, I.count = v, c
		end
	end
end
function S.IntelForget(unitID) for _, I in pairs(S.intel) do I.units[unitID] = nil end end

-- the standings: one row per team, best first.  Teams we can see are scored from their statistics;
-- hidden teams only from what has been seen of them (est = true), and teams never seen come last (score = nil).
function S.Leaderboard()
	local rows = {}
	for _, id in ipairs(S.order) do
		local t = S.teams[id]
		local row = { team = t, id = id }
		if S.Visible(id) then
			row.score = S.Value(t, "sc", t.n)
		else
			local I = S.intel[id]
			row.est = true
			row.intel = I
			if I and I.lastSeen then row.score = I.value end
		end
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		if (a.score ~= nil) ~= (b.score ~= nil) then return a.score ~= nil end
		if a.team.dead ~= b.team.dead then return not a.team.dead end
		if a.score ~= b.score then return (a.score or 0) > (b.score or 0) end
		return a.id < b.id
	end)
	for k, r in ipairs(rows) do r.rank = k end
	return rows
end

-- how many are playing
function S.PlayerCounts()
	local total, humans, ais, alive = 0, 0, 0, 0
	local gaia = Spring.GetGaiaTeamID and Spring.GetGaiaTeamID()
	for _, id in ipairs(Spring.GetTeamList and Spring.GetTeamList() or S.order) do
		if id ~= gaia then
			local _, _, dead, isAI = Spring.GetTeamInfo(id, false)
			total = total + 1
			if isAI then ais = ais + 1 else humans = humans + 1 end
			if not dead then alive = alive + 1 end
		end
	end
	return total, humans, ais, alive
end

function S.VisibleTeams()
	local r = {}
	for _, id in ipairs(S.order) do if S.Visible(id) then r[#r + 1] = S.teams[id] end end
	return r
end

function S.Reset()
	S.teams, S.order, S.events, S.over, S.lastFrame, S.intel = {}, {}, {}, nil, 0, {}
	Bump()
end

return S
