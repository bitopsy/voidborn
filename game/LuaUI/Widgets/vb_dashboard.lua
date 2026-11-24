function widget:GetInfo()
	return { name = "Voidborn Dashboard", desc = "Live and end-of-game statistics: graphs and radar charts of damage, economy, army and defence value (Ctrl+Shift+D, /vbdash)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 5, enabled = true }
end

--[[
  THE DASHBOARD

  A small HUD sits at the top right during the game: the standings, a radar chart and three sparklines.
  Click it (or press Ctrl+Shift+D, or type /vbdash) to open the full dashboard:

    OVERVIEW  scoreboard, two radar charts, four graphs        GRAPHS   any statistic as one big graph
    ECONOMY   income, stores, waste, the resource ledger       COMBAT   damage, kills, losses, best unit types
    ARMY      army / defence value and the unit mix            REPORT   the match report and awards

  Everything is clickable: team cards (hide / show, right click = only this one), table headers (sort),
  graphs (a click opens the graph big, in GRAPHS a click or a drag picks a moment), the timeline at the bottom
  (pick a moment: the radar charts and tables then show that moment), the events (jump to them).
  When the game ends the dashboard opens on the REPORT by itself, in place of the engine's end screen.

  Keys:  Esc close   1-9 tabs   left / right step through time   Home start   End back to live   wheel zoom the time axis
  Commands:  /vbdash [open|close|hud|tab <name>|scale <n>]

  SETTINGS has a GRAPHICS panel: the screen resolution (the HUD is stacked again in the default layout column) and the
  graphics quality, lowest to ultra, which is an FPS-OPS preset (LuaUI/Widgets/vb_graphics.lua, gui_fps_ops.lua).

  The numbers come from LuaRules/Gadgets/vb_stats.lua. Drawing is in LuaUI/Headers/vb_stats_draw.h.lua, the data
  model in LuaUI/Headers/vb_stats_data.h.lua.
]]

local okS, Stats = pcall(VFS.Include, "LuaUI/Headers/vb_stats_data.h.lua")
local okD, D = pcall(VFS.Include, "LuaUI/Headers/vb_stats_draw.h.lua")
if not (okS and okD and type(Stats) == "table" and type(D) == "table") then
	Spring.Echo("[VB] dashboard: could not load its headers: " .. tostring(okS and D or Stats))
	return
end
D.Stats = Stats
widget.Stats = Stats          -- (for the smoke test)
local C = D.C
local sc = D.sc
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local FPS = 30

local TABS = {
	{ "overview", "OVERVIEW" }, { "graphs", "GRAPHS" }, { "economy", "ECONOMY" },
	{ "combat", "COMBAT" }, { "army", "ARMY" }, { "report", "REPORT" },
	{ "share", "SHARE" }, { "settings", "SETTINGS" }, { "keys", "KEYS" }, { "about", "ABOUT" },
}
local FIRST_MENU_TAB = 7      -- the tabs from here on are the menu pages, not statistics
local WINDOWS = { { 0, "ALL" }, { 20, "20 MIN" }, { 10, "10 MIN" }, { 5, "5 MIN" } }

local st = {
	open = false, tab = "overview", hud = true, hudCollapsed = false, hudX = nil, hudTop = nil,
	menu = true, hudRadar = 1, focus = "av", cursor = nil, window = 0, hidden = {}, focusTeam = nil,
	sort = { col = "sc", desc = true }, scale = 2.2, autoOpened = false,
	share = { metal = 0.25, energy = 0.25 }, shareTeam = nil, resignArmed = nil,
}

local vsx, vsy = Spring.GetViewGeometry()
local lastClock = os.clock()
local dragging = nil
-- the player dragged the HUD: the default layout (vb_layout.lua) lets go
local function UserTookOver() if WG.VBLayout and WG.VBLayout.Release then WG.VBLayout.Release() end end
local refreshTimer, intelTimer = 0, 0
local panelRect = nil          -- the dashboard's rectangle, to tell clicks inside from clicks outside
local hudRect = nil

local function Snd(name) if Spring.PlaySoundFile then Spring.PlaySoundFile("sounds/" .. name .. ".wav", 0.5, "ui") end end

--------------------------------------------------------------------------------
-- HUD columns and the per-player extras (unit count / limit, ping, fps, flag)
--------------------------------------------------------------------------------
local HUD_W = 420                 -- HUD width in sc() units (was 380); vb_layout's Place() uses the same number
local HUD_COLS = {                -- w = column width in sc() units; columns are laid out from the right edge
	{ id = "sc", head = "SCORE", w = 40 }, { id = "av", head = "ARMY", w = 36 }, { id = "mi", head = "M/S", w = 28 },
	{ id = "ei", head = "E/S", w = 30 }, { id = "units", head = "UNITS", w = 56 },
	{ id = "ping", head = "PING", w = 30 }, { id = "fps", head = "FPS", w = 26 },
}
local FLAG_DIR = "LuaUI/Images/flags/"      -- <cc>.png, lower case: "fr.png", "us.png" ... (BAR's flag set works as is)
local fpsOf = {}                  -- [playerID] = { fps, os.clock() }, what the other clients broadcast
local teamInfo = {}               -- [teamID] = { units, maxUnits, ping, fps, cc, ai, active }
local flagOK = {}                 -- [path] = true / false (does the texture exist)
local fpsTimer = 0

local function RefreshTeamInfo()
	local now = os.clock()
	local myTeam, myPlayer = Spring.GetMyTeamID(), Spring.GetMyPlayerID()
	-- the unit limit is one game-wide number; take it from our own team, else from the game
	local gameMax = Game and Game.maxUnits
	local okM, m = pcall(Spring.GetTeamMaxUnits, myTeam)
	if okM and m and m > 0 then gameMax = m end
	local out = {}
	for _, t in ipairs(Stats.VisibleTeams()) do
		local e = { maxUnits = gameMax }
		local okU, n = pcall(Spring.GetTeamUnitCount, t.id)
		if okU and n then e.units = n end
		local okT, mx = pcall(Spring.GetTeamMaxUnits, t.id)
		if okT and mx and mx > 0 then e.maxUnits = mx end
		local _, leader, _, isAI = Spring.GetTeamInfo(t.id, false)
		e.ai = isAI and true or false
		local pid = leader
		if not e.ai and (not pid or pid < 0) then
			for _, p in ipairs(Spring.GetPlayerList(t.id, true) or {}) do pid = p; break end
		end
		if not e.ai and pid and pid >= 0 then
			-- name, active, spectator, teamID, allyTeamID, pingTime (s), cpuUsage, country, rank
			local _, active, _, _, _, ping, _, cc = Spring.GetPlayerInfo(pid, false)
			e.active = active
			e.ping = ping and floor(ping * 1000 + 0.5) or nil
			e.cc = (cc and cc ~= "") and cc or nil
			if pid == myPlayer then
				e.fps = floor((Spring.GetFPS and Spring.GetFPS() or 0) + 0.5)
			else
				local f = fpsOf[pid]
				if f and now - f[2] < 10 then e.fps = f[1] end
			end
		end
		out[t.id] = e
	end
	teamInfo = out
end

-- the unit count: exact for allies and spectators, the statistics' sample for an enemy we may see
local function UnitsOf(t, e, idx)
	if Spring.GetSpectatingState() or Spring.AreTeamsAllied(Spring.GetMyTeamID(), t.id) then
		if e and e.units then return e.units end
	end
	local v = Stats.Value(t, "uc", idx)
	if v then return floor(v + 0.5) end
end

local function PingText(e)
	if not e then return "-", C.faint end
	if e.ai then return "AI", C.faint end
	if e.active == false then return "OFF", C.bad end
	if not e.ping then return "-", C.faint end
	local ms = e.ping
	local txt = ms >= 1000 and string.format("%.1fs", ms / 1000) or tostring(ms)
	return txt, ms < 100 and C.good or (ms < 250 and C.warn or C.bad)
end

local function FpsText(e)
	if not e then return "-", C.faint end
	if e.ai then return "AI", C.faint end
	if not e.fps then return "-", C.faint end
	return tostring(e.fps), e.fps >= 30 and C.good or (e.fps >= 15 and C.warn or C.bad)
end

-- the flag of the player's country; two letters of text when the game has no picture for it
local function DrawFlag(cc, x, y, w, h)
	if not cc then return end
	local path = FLAG_DIR .. cc:lower() .. ".png"
	if flagOK[path] == nil then flagOK[path] = (VFS.FileExists(path) and true) or false end
	if flagOK[path] then
		gl.Color(1, 1, 1, 1)
		gl.Texture(path)
		gl.TexRect(x, y, x + w, y + h)
		gl.Texture(false)
	else
		D.Mono(cc:upper(), x, y + sc(1), sc(7), "o", C.faint)
	end
end

--------------------------------------------------------------------------------
-- what is shown
--------------------------------------------------------------------------------
local function BuildCtx()
	local all = Stats.VisibleTeams()
	local shown = {}
	for _, t in ipairs(all) do if not st.hidden[t.id] then shown[#shown + 1] = t end end
	if #shown == 0 then shown = all end
	local last = Stats.lastFrame
	local cur = st.cursor and min(st.cursor, last) or nil
	local f1 = max(last, 900)
	local f0 = 0
	if st.window > 0 then f0 = max(0, f1 - st.window * 60 * FPS) end
	local idx = {}
	for _, t in ipairs(all) do idx[t.id] = Stats.IndexAt(t, cur or last) end
	return { all = all, shown = shown, f0 = f0, f1 = f1, cursor = cur, idx = idx, last = last, frame = cur or last }
end

local function ValueOf(ctx, team, id) return Stats.Value(team, id, ctx.idx[team.id]) end

local function SetTab(tab) st.tab = tab; D.dd = nil; Snd("ui_click") end
local function Open(tab) st.open = true; if tab then st.tab = tab end; Snd("ui_open") end
local function Close() st.open = false; D.dd = nil; Snd("ui_close") end

local function Grid(x1, y1, x2, y2, cols, rows, gap)
	local w, h = (x2 - x1 - (cols - 1) * gap) / cols, (y2 - y1 - (rows - 1) * gap) / rows
	local r = {}
	for j = 1, rows do
		for i = 1, cols do
			local rx1 = x1 + (i - 1) * (w + gap)
			local ry2 = y2 - (j - 1) * (h + gap)
			r[#r + 1] = { rx1, ry2 - h, rx1 + w, ry2 }
		end
	end
	return r
end

--------------------------------------------------------------------------------
-- pieces: graphs, radars, tables
--------------------------------------------------------------------------------
local function ChartPanel(rect, id, ctx, o)
	o = o or {}
	local m = Stats.M[id]
	local x1, y1, x2, y2 = D.Panel(rect[1], rect[2], rect[3], rect[4], m.label:upper(), { accent = m.color })
	D.LineChart(x1, y1, x2, y2, {
		teams = ctx.shown, metric = id, f0 = ctx.f0, f1 = ctx.f1, cursor = ctx.cursor,
		fill = #ctx.shown <= 3, events = o.events,
		onClick = function(f, b) if b == 1 then st.focus = id; SetTab("graphs") end end,
	})
end

local function Entries(ctx, ids)
	local e = {}
	for _, t in ipairs(ctx.shown) do
		local vals = {}
		for k, id in ipairs(ids) do vals[k] = ValueOf(ctx, t, id) end
		e[#e + 1] = { name = t.name, color = Stats.ViewColor(t), vals = vals }
	end
	return e
end

local function RadarAxes(def)
	local axes = {}
	for _, id in ipairs(def.axes) do
		local m = Stats.M[id]
		axes[#axes + 1] = { label = def.short[id] or m.label, fmt = function(v) return Stats.Format(m, v) end }
	end
	return axes
end

local function ShareDonut(cx, cy, r, ctx, id, title)
	local m = Stats.M[id]
	local slices = {}
	local total = 0
	for _, t in ipairs(ctx.shown) do
		local v = max(0, ValueOf(ctx, t, id))
		total = total + v
		slices[#slices + 1] = { frac = v, color = Stats.ViewColor(t), name = t.name, value = Stats.Format(m, v) }
	end
	D.Donut(cx, cy, r * 0.62, r, slices, Stats.Format(m, total), "total")
	D.Text(title, cx, cy - r - sc(14), sc(9), "oc", C.dim)
end

local function RadarPanel(rect, def, donuts, ctx)
	local x1, y1, x2, y2 = D.Panel(rect[1], rect[2], rect[3], rect[4], def.name .. " RADAR", { right = ctx.cursor and ("at " .. Stats.Time(ctx.cursor)) or "live" })
	local w, h = x2 - x1, y2 - y1
	local donutH = donuts and min(h * 0.36, sc(170)) or 0
	local rh = h - donutH
	local R = min(w / 2 - sc(58), rh / 2 - sc(28))
	if R < sc(30) then return end
	D.Radar((x1 + x2) / 2, y2 - rh / 2, R, RadarAxes(def), Entries(ctx, def.axes), {})
	if donuts then
		local dr = min(donutH / 2 - sc(22), w / (#donuts * 2) - sc(14))
		for k, d in ipairs(donuts) do
			ShareDonut(x1 + w * (k - 0.5) / #donuts, y1 + donutH / 2 + sc(6), dr, ctx, d[1], d[2])
		end
	end
end

-- a table with one row per team; cols = { { id =, head =, low = true (less is better), get = fn(team, idx), text = fn(v) } }
local function DrawTable(x1, y1, x2, y2, ctx, cols, o)
	o = o or {}
	local n = #ctx.shown
	if n == 0 then return end
	local hh = sc(24)
	local rh = min(sc(34), (y2 - y1 - hh) / n)
	local nameW = sc(o.nameW or 190)
	local cw = (x2 - x1 - nameW) / #cols
	local function Get(t, c)
		local i = ctx.idx[t.id]
		if c.get then return c.get(t, i) end
		return Stats.Value(t, c.id, i)
	end
	D.Rect(x1, y2 - hh, x2, y2, C.panel2, 0.9)
	D.Text("TEAM", x1 + sc(10), y2 - hh + sc(8), sc(9), "o", C.dim)
	for k, c in ipairs(cols) do
		local cx1 = x1 + nameW + (k - 1) * cw
		local active = o.sortable and st.sort.col == c.id
		local label = c.head .. (active and (st.sort.desc and " v" or " ^") or "")
		D.Text(label, cx1 + cw - sc(8), y2 - hh + sc(8), sc(9), "or", active and C.accent or C.dim)
		if o.sortable then
			D.Region(cx1, y2 - hh, cx1 + cw, y2, { tip = c.tip or "Click to sort",
				click = function() if st.sort.col == c.id then st.sort.desc = not st.sort.desc else st.sort.col, st.sort.desc = c.id, true end; Snd("ui_click") end })
		end
	end
	local list = {}
	for _, t in ipairs(ctx.shown) do list[#list + 1] = t end
	if o.sortable then
		local sc_ = nil
		for _, c in ipairs(cols) do if c.id == st.sort.col then sc_ = c end end
		if sc_ then
			table.sort(list, function(a, b)
				local va, vb = Get(a, sc_), Get(b, sc_)
				if va == vb then return a.id < b.id end
				if st.sort.desc then return va > vb end
				return va < vb
			end)
		end
	end
	-- the best and the largest value of every column
	local best, top = {}, {}
	for k, c in ipairs(cols) do
		local bv, tv
		for _, t in ipairs(list) do
			local v = Get(t, c)
			if not tv or v > tv then tv = v end
			if bv == nil or (c.low and v < bv) or (not c.low and v > bv) then bv = v end
		end
		best[k], top[k] = bv, tv or 0
	end
	for r, t in ipairs(list) do
		local ry2 = y2 - hh - (r - 1) * rh
		local ry1 = ry2 - rh
		if ry1 < y1 - 2 then break end
		local c = Stats.ViewColor(t)
		local hot = D.Inside(x1, ry1, x2, ry2) and not D.modalBlocked
		D.Rect(x1, ry1, x2, ry2 - 1, hot and C.panel2 or C.bg, hot and 0.9 or (r % 2 == 0 and 0.30 or 0.55))
		D.Rect(x1, ry1, x1 + sc(4), ry2 - 1, c, 0.95)
		local nm = D.Fit(t.name, sc(11), nameW - sc(24))
		D.Text(nm, x1 + sc(14), ry1 + rh * 0.5 + sc(1), sc(11), "o", st.hidden[t.id] and C.faint or c)
		local sub = t.side ~= "" and t.side or ("team " .. t.id)
		if t.dead then sub = sub .. "  OUT" end
		D.Text(sub, x1 + sc(14), ry1 + rh * 0.5 - sc(10), sc(8), "o", t.dead and C.bad or C.faint)
		for k, col in ipairs(cols) do
			local cx1 = x1 + nameW + (k - 1) * cw
			local v = Get(t, col)
			local frac = top[k] > 0 and max(0, v) / top[k] or 0
			if frac > 0 then D.Rect(cx1 + sc(4), ry1 + sc(4), cx1 + sc(4) + (cw - sc(8)) * frac, ry2 - sc(5), c, 0.13) end
			local isBest = v == best[k] and #list > 1 and (v ~= 0)
			local text = col.text and col.text(v) or Stats.Format(Stats.M[col.id], v)
			D.Mono(text, cx1 + cw - sc(8), ry1 + rh * 0.5 - sc(4), sc(11), "or", isBest and C.text or C.dim)
			if isBest then D.Rect(cx1 + cw - sc(5), ry1 + sc(5), cx1 + cw - sc(3), ry2 - sc(6), C.good, 0.8) end
		end
		D.Region(x1, ry1, x2, ry2, { tip = "Click: focus this team", click = function() st.focusTeam = t.id; Snd("ui_click") end })
	end
end

local SCORE_COLS = {
	{ id = "sc", head = "SCORE" },
	{ id = "av", head = "ARMY" }, { id = "dv", head = "DEFENSE" }, { id = "mi", head = "METAL/S" }, { id = "ei", head = "ENERGY/S" },
	{ id = "dd", head = "DMG DEALT" }, { id = "dt", head = "DMG TAKEN", low = true }, { id = "kv", head = "KILLED" },
	{ id = "lv", head = "LOST", low = true }, { id = "kd", head = "TRADE" }, { id = "bc", head = "BUILT" },
}

--------------------------------------------------------------------------------
-- the unit types
--------------------------------------------------------------------------------
local KIND_COLOR = {
	com = { 1.00, 0.85, 0.30 }, con = { 0.60, 0.80, 1.00 }, scout = { 0.50, 1.00, 0.70 }, raider = { 1.00, 0.62, 0.30 },
	assault = { 1.00, 0.40, 0.40 }, art = { 0.80, 0.50, 1.00 }, heavy = { 1.00, 0.30, 0.70 }, support = { 0.40, 0.90, 0.90 },
	combat = { 0.90, 0.90, 0.50 }, fac = { 0.7, 0.7, 0.8 }, mex = { 0.62, 0.78, 1.0 }, solar = { 1.0, 0.88, 0.3 },
	heart = { 1.0, 0.75, 0.2 }, store = { 0.5, 0.6, 0.8 }, radar = { 0.5, 0.9, 0.6 }, def1 = { 0.35, 0.85, 1.0 }, def2 = { 0.2, 0.6, 1.0 },
}
local function UnitColor(defID)
	local ud = UnitDefs[defID]
	local kind = ud and ud.customParams and ud.customParams.kind
	local c = KIND_COLOR[kind] or { 0.7, 0.7, 0.75 }
	local shade = 0.78 + 0.22 * ((defID % 3) / 2)
	return { c[1] * shade, c[2] * shade, c[3] * shade }
end

local function CostOfDef(defID) local ud = UnitDefs[defID]; return ud and ud.metalCost or 0 end

local function TopDefs(tbl, n)
	local list = {}
	for defID, v in pairs(tbl) do if v > 0 then list[#list + 1] = { defID = defID, v = v } end end
	table.sort(list, function(a, b) return a.v > b.v end)
	local out = {}
	for i = 1, min(n, #list) do out[i] = list[i] end
	return out
end

--------------------------------------------------------------------------------
-- the tabs
--------------------------------------------------------------------------------
local function TabOverview(x1, y1, x2, y2, ctx)
	local n = #ctx.shown
	local tableH = min((y2 - y1) * 0.34, sc(24) + sc(26) + n * sc(34) + sc(6))
	local tx1, ty1, tx2, ty2 = D.Panel(x1, y2 - tableH, x2, y2, "SCOREBOARD", { right = ctx.cursor and ("at " .. Stats.Time(ctx.cursor)) or "live - click a heading to sort" })
	DrawTable(tx1, ty1, tx2, ty2, ctx, SCORE_COLS, { sortable = true })
	local by2 = y2 - tableH - sc(8)
	local gap = sc(8)
	local radarW = (x2 - x1 - gap) * 0.50
	local half = (radarW - gap) / 2
	RadarPanel({ x1, y1, x1 + half, by2 }, Stats.RADARS[1], { { "dd", "DAMAGE SHARE" }, { "kv", "KILL SHARE" } }, ctx)
	RadarPanel({ x1 + half + gap, y1, x1 + radarW, by2 }, Stats.RADARS[2], { { "mi", "METAL INCOME" }, { "ei", "ENERGY INCOME" } }, ctx)
	local cells = Grid(x1 + radarW + gap, y1, x2, by2, 2, 2, gap)
	local ids = { "av", "mi", "dd", "ei" }
	for k, id in ipairs(ids) do ChartPanel(cells[k], id, ctx) end
end

local function TabGraphs(x1, y1, x2, y2, ctx)
	local listW = sc(220)
	local lx1, ly1, lx2, ly2 = D.Panel(x1, y1, x1 + listW, y2, "STATISTICS")
	local rowH = min(sc(20), (ly2 - ly1) / (#Stats.METRICS + #Stats.GROUPS))
	local y = ly2
	for _, grp in ipairs(Stats.GROUPS) do
		y = y - rowH
		D.Text(grp[2], lx1 + sc(4), y + rowH * 0.5 - sc(4), sc(9), "o", C.accent)
		for _, m in ipairs(Stats.METRICS) do
			if m.group == grp[1] then
				y = y - rowH
				local sel = st.focus == m.id
				local hot = D.Inside(lx1, y, lx2, y + rowH)
				if sel then D.Rect(lx1, y, lx2, y + rowH, m.color, 0.20); D.Rect(lx1, y, lx1 + sc(3), y + rowH, m.color, 0.95)
				elseif hot then D.Rect(lx1, y, lx2, y + rowH, C.panel2, 0.9) end
				D.Text(m.label, lx1 + sc(10), y + rowH * 0.5 - sc(4), sc(10), "o", sel and C.text or (hot and C.text or C.dim))
				D.Region(lx1, y, lx2, y + rowH, { tip = m.desc, click = function() st.focus = m.id; Snd("ui_click") end })
			end
		end
	end
	local m = Stats.M[st.focus] or Stats.M.av
	local rx1 = x1 + listW + sc(8)
	local tableH = min((y2 - y1) * 0.26, sc(34) + #ctx.shown * sc(26))
	local cx1, cy1, cx2, cy2 = D.Panel(rx1, y1 + tableH + sc(8), x2, y2, m.label:upper(), { accent = m.color, right = "click or drag to pick a moment - triangles are events" })
	D.LineChart(cx1, cy1, cx2, cy2, {
		teams = ctx.shown, metric = m.id, f0 = ctx.f0, f1 = ctx.f1, cursor = ctx.cursor, fill = #ctx.shown <= 3, events = true,
		onClick = function(f, b) st.cursor = (b == 1) and max(0, min(f, ctx.last)) or nil end,
		onDrag = function(f) st.cursor = max(0, min(f, ctx.last)) end,
	})
	-- the values at the selected moment
	local tx1, ty1, tx2, ty2 = D.Panel(rx1, y1, x2, y1 + tableH, m.label:upper() .. (ctx.cursor and (" AT " .. Stats.Time(ctx.cursor)) or " NOW"), { accent = m.color })
	local rows = {}
	for _, t in ipairs(ctx.shown) do rows[#rows + 1] = { t = t, v = ValueOf(ctx, t, m.id) } end
	table.sort(rows, function(a, b) return a.v > b.v end)
	local items = {}
	for _, r in ipairs(rows) do
		items[#items + 1] = { label = r.t.name, value = max(0, r.v), color = Stats.ViewColor(r.t), text = Stats.Format(m, r.v),
			tip = { { r.t.name, Stats.ViewColor(r.t), Stats.Format(m, r.v) }, { "peak " .. Stats.Format(m, Stats.Peak(r.t, m.id)), C.dim } } }
	end
	D.HBars(tx1, ty1, tx2, ty2, items, { labelW = sc(150), valueW = sc(80) })
end

local function Ledger(x1, y1, x2, y2, ctx)
	local cols = {
		{ id = "mp", head = "METAL IN" }, { id = "mu", head = "SPENT" }, { id = "mw", head = "WASTED", low = true }, { id = "mf", head = "EFFIC." },
		{ id = "ep", head = "ENERGY IN" }, { id = "eu", head = "SPENT" }, { id = "ew", head = "WASTED", low = true }, { id = "ef", head = "EFFIC." },
	}
	DrawTable(x1, y1, x2, y2, ctx, cols, { nameW = 170 })
end

local function TabEconomy(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local chartsH = (y2 - y1) * 0.70
	local cells = Grid(x1, y2 - chartsH, x2, y2, 3, 2, gap)
	local ids = { "mi", "ei", "bp", "ms", "es", "mw" }
	for k, id in ipairs(ids) do ChartPanel(cells[k], id, ctx) end
	local by2 = y2 - chartsH - gap
	local ledgerW = (x2 - x1) * 0.70
	local lx1, ly1, lx2, ly2 = D.Panel(x1, y1, x1 + ledgerW, by2, "RESOURCE LEDGER", { right = ctx.cursor and ("at " .. Stats.Time(ctx.cursor)) or "totals so far" })
	Ledger(lx1, ly1, lx2, ly2, ctx)
	local dx1, dy1, dx2, dy2 = D.Panel(x1 + ledgerW + gap, y1, x2, by2, "SHARE OF THE METAL AND ENERGY MADE")
	local r = min((dx2 - dx1) / 4 - sc(8), (dy2 - dy1) / 2 - sc(14))
	if r > sc(24) then
		ShareDonut(dx1 + (dx2 - dx1) * 0.25, (dy1 + dy2) / 2 + sc(4), r, ctx, "mp", "METAL")
		ShareDonut(dx1 + (dx2 - dx1) * 0.75, (dy1 + dy2) / 2 + sc(4), r, ctx, "ep", "ENERGY")
	end
end

local function TabCombat(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local chartsH = (y2 - y1) * 0.56
	local cells = Grid(x1, y2 - chartsH, x2, y2, 3, 2, gap)
	local ids = { "dd", "dt", "dps", "kv", "lv", "kd" }
	for k, id in ipairs(ids) do ChartPanel(cells[k], id, ctx, { events = k == 1 }) end
	local by2 = y2 - chartsH - gap
	-- the best unit types of one team
	local team = Stats.teams[st.focusTeam]
	if not team or not Stats.Visible(team.id) then team = ctx.shown[1] end
	local px1, py1, px2, py2 = D.Panel(x1, y1, x2, by2, "BEST UNIT TYPES OF " .. (team and team.name:upper() or "-"), { right = "click a team name to switch" })
	-- team switch buttons
	local bx = px2
	for k = #ctx.all, 1, -1 do
		local t = ctx.all[k]
		local w = D.W(t.name, sc(9)) + sc(16)
		bx = bx - w - sc(4)
		D.Button(bx, py2 - sc(20), bx + w, py2, t.name, { size = sc(9), active = t == team, color = Stats.ViewColor(t), click = function() st.focusTeam = t.id; Snd("ui_click") end })
	end
	if team then
		local i = ctx.idx[team.id]
		local cols = { { "dd", "DAMAGE DEALT", Stats.M.dd.color, false }, { "kl", "ENEMY VALUE KILLED", Stats.M.kv.color, false }, { "ls", "VALUE LOST", Stats.M.lv.color, true } }
		local cw = (px2 - px1 - gap * 2) / 3
		for k, c in ipairs(cols) do
			local cx1 = px1 + (k - 1) * (cw + gap)
			D.Text(c[2], cx1 + sc(4), py2 - sc(34), sc(9), "o", c[3])
			local items = {}
			for _, e in ipairs(TopDefs(Stats.DefsAt(team, c[1], i), 8)) do
				items[#items + 1] = { label = Stats.UnitName(e.defID), value = e.v, color = UnitColor(e.defID), text = Stats.Num(e.v) }
			end
			D.HBars(cx1, py1, cx1 + cw, py2 - sc(40), items, { labelW = sc(96), valueW = sc(50), empty = "nothing yet" })
		end
	end
end

local function TabArmy(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local chartsH = (y2 - y1) * 0.46
	local cells = Grid(x1, y2 - chartsH, x2, y2, 3, 1, gap)
	local ids = { "av", "dv", "uc" }
	for k, id in ipairs(ids) do ChartPanel(cells[k], id, ctx) end
	local by2 = y2 - chartsH - gap
	local px1, py1, px2, py2 = D.Panel(x1, y1, x2, by2, "UNIT MIX", { right = ctx.cursor and ("at " .. Stats.Time(ctx.cursor)) or "now - bar = army value by unit type" })
	local n = #ctx.shown
	local rowH = (py2 - py1) / max(n, 1)
	for k, t in ipairs(ctx.shown) do
		local ry2 = py2 - (k - 1) * rowH
		local ry1 = ry2 - rowH
		local c = Stats.ViewColor(t)
		D.Rect(px1, ry1 + sc(2), px1 + sc(4), ry2 - sc(2), c, 0.95)
		D.Text(D.Fit(t.name, sc(11), sc(150)), px1 + sc(12), ry2 - sc(18), sc(11), "o", c)
		local units = Stats.UnitsAt(t, ctx.idx[t.id])
		local parts, total = {}, 0
		local list = {}
		for defID, count in pairs(units) do
			local role = UnitDefs[defID]
			local v = CostOfDef(defID) * count
			local kind = role and role.customParams and role.customParams.kind
			if v > 0 and kind ~= "com" and kind ~= "con" then list[#list + 1] = { defID = defID, count = count, v = v } end
		end
		table.sort(list, function(a, b) return a.v > b.v end)
		for _, e in ipairs(list) do
			parts[#parts + 1] = { value = e.v, color = UnitColor(e.defID), name = e.count .. " x " .. Stats.UnitName(e.defID), text = Stats.Num(e.v) }
			total = total + e.v
		end
		local bx1, bx2 = px1 + sc(170), px2 - sc(8)
		local barH = min(sc(22), rowH * 0.34)
		local by1 = ry2 - sc(10) - barH
		D.StackBar(bx1, by1, bx2, by1 + barH, parts)
		-- the five biggest types, as text
		local tx = bx1
		for q = 1, min(6, #list) do
			local e = list[q]
			local label = e.count .. " " .. Stats.UnitName(e.defID)
			local w = D.W(label, sc(9)) + sc(26)
			if tx + w > bx2 then break end
			D.Rect(tx, by1 - sc(13), tx + sc(8), by1 - sc(5), UnitColor(e.defID), 0.95)
			D.Text(label, tx + sc(12), by1 - sc(14), sc(9), "o", C.dim)
			tx = tx + w
		end
		if k < n then D.HLine(px1, px2, ry1, C.line, 0.7) end
	end
end

-- the awards
local function Awards(ctx)
	local list = {}
	local function Best(title, desc, id, fmt, low, mode)
		local bt, bv
		for _, t in ipairs(ctx.shown) do
			local v
			if mode == "peak" then v = Stats.Peak(t, id) else v = ValueOf(ctx, t, id) end
			if bv == nil or (low and v < bv) or (not low and v > bv) then bt, bv = t, v end
		end
		if bt and (bv ~= 0 or low) then list[#list + 1] = { title = title, desc = desc, team = bt, text = fmt(bv) } end
	end
	local num = function(v) return Stats.Num(v) end
	Best("WARLORD", "most damage dealt", "dd", num)
	Best("BUTCHER", "most enemy value destroyed", "kv", num)
	Best("IRON WALL", "tallest defence value at any time", "dv", num, false, "peak")
	Best("HORDE", "biggest army at any time", "av", num, false, "peak")
	Best("QUARTERMASTER", "most metal produced", "mp", num)
	Best("POWER BROKER", "most energy produced", "ep", num)
	Best("ARCHITECT", "most value built", "bv", num)
	Best("TACTICIAN", "best damage ratio (dealt / received)", "dr", function(v) return Stats.Ratio(v) end)
	Best("PUNCHING BAG", "most damage received", "dt", num)
	Best("OVERFLOW", "most metal wasted", "mw", num)
	return list
end

local function MostEffectiveUnit(ctx)
	local best, bt
	for _, t in ipairs(ctx.shown) do
		local d = Stats.DefsAt(t, "dd", ctx.idx[t.id])
		for defID, v in pairs(d) do if not best or v > best.v then best, bt = { defID = defID, v = v }, t end end
	end
	return best, bt
end

local function TabReport(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local over = Stats.over
	local bannerH = sc(96)
	local bx1, by1, bx2, by2 = D.Panel(x1, y2 - bannerH, x2, y2, nil, { accent = over and C.good or C.accent })
	local title, color, sub
	local winners = {}
	if over then
		for _, t in ipairs(ctx.all) do if over.winners[t.ally] then winners[#winners + 1] = t.name end end
		local spec = Spring.GetSpectatingState()
		local myAlly = Spring.GetMyAllyTeamID()
		if next(over.winners) == nil then title, color = "DRAW", C.warn
		elseif spec then title, color = "GAME OVER", C.accent
		elseif over.winners[myAlly] then title, color = "VICTORY", C.good
		else title, color = "DEFEAT", C.bad end
		sub = (#winners > 0 and ("Winner: " .. table.concat(winners, ", ") .. "     ") or "") .. "Duration " .. Stats.Time(over.frame)
	else
		title, color = "MATCH IN PROGRESS", C.accent
		sub = "Standings at " .. Stats.Time(ctx.frame) .. " - this page turns into the match report when the game ends"
	end
	D.Text(title, (bx1 + bx2) / 2, (by1 + by2) / 2 + sc(4), sc(34), "oc", color)
	D.Text(sub, (bx1 + bx2) / 2, (by1 + by2) / 2 - sc(24), sc(11), "oc", C.dim)

	local awards = Awards(ctx)
	local cardsH = (y2 - y1 - bannerH) * 0.42
	local cells = Grid(x1, y2 - bannerH - gap - cardsH, x2, y2 - bannerH - gap, 5, 2, gap)
	for k, a in ipairs(awards) do
		local r = cells[k]
		if not r then break end
		local ax1, ay1, ax2, ay2 = D.Panel(r[1], r[2], r[3], r[4], a.title, { accent = Stats.ViewColor(a.team) })
		local c = Stats.ViewColor(a.team)
		D.Text(D.Fit(a.team.name, sc(13), ax2 - ax1 - sc(8)), ax1 + sc(4), ay2 - sc(18), sc(13), "o", c)
		D.Mono(a.text, ax1 + sc(4), ay1 + sc(14), sc(18), "o", C.text)
		D.Text(a.desc, ax1 + sc(4), ay1 + sc(1), sc(8), "o", C.faint)
	end
	local best, bt = MostEffectiveUnit(ctx)
	local tableTop = y2 - bannerH - gap - cardsH - gap
	local tx1, ty1, tx2, ty2 = D.Panel(x1, y1, x2, tableTop, "FINAL FIGURES", { right = best and ("most damage by one unit type: " .. Stats.UnitName(best.defID) .. " (" .. bt.name .. ", " .. Stats.Num(best.v) .. ")") or nil })
	local cols = {}
	for _, c in ipairs(SCORE_COLS) do cols[#cols + 1] = c end
	cols[#cols + 1] = { id = "mf", head = "M.EFFIC." }
	DrawTable(tx1, ty1, tx2, ty2, ctx, cols, { sortable = true })
end

--------------------------------------------------------------------------------
-- the dashboard frame: title bar, team cards, events, timeline
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- the pages that are not statistics: settings, keys, about
--------------------------------------------------------------------------------
local function Wrap(text, size, width)
	local lines = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in para:gmatch("%S+") do
			local try = line == "" and word or (line .. " " .. word)
			if D.W(try, size) > width and line ~= "" then lines[#lines + 1] = line; line = word else line = try end
		end
		lines[#lines + 1] = line
	end
	return lines
end

-- a block of wrapped text; returns the y below it
local function TextBlock(x1, y2, width, text, size, color, lead)
	local lines = Wrap(text, size, width)
	lead = lead or size * 1.5
	for k, l in ipairs(lines) do D.Text(l, x1, y2 - k * lead + size * 0.2, size, "o", color or C.dim) end
	return y2 - #lines * lead
end

local function Toggle(x1, y, w, label, on, fn, tip)
	D.Text(label, x1, y + sc(5), sc(10), "o", C.text)
	D.Button(x1 + w - sc(60), y, x1 + w, y + sc(20), on and "ON" or "OFF", { active = on, color = on and C.good or C.faint, click = fn, tip = tip })
end

local function Command(cmd) return function() Spring.SendCommands(cmd); Close() end end

--------------------------------------------------------------------------------
-- SHARE: send metal, energy or the selected units to an ally
--------------------------------------------------------------------------------
local function AllyTeams()
	local out = {}
	local me, myAlly = Spring.GetMyTeamID(), Spring.GetMyAllyTeamID()
	for _, id in ipairs(Spring.GetTeamList(myAlly) or {}) do
		if id ~= me then
			local _, _, dead = Spring.GetTeamInfo(id, false)
			if not dead then out[#out + 1] = id end
		end
	end
	return out
end

local function TeamLabel(id)
	local t = Stats.teams and Stats.teams[id]
	if t and t.name then return t.name end
	local _, leader = Spring.GetTeamInfo(id, false)
	local pname = leader and leader >= 0 and Spring.GetPlayerInfo(leader, false)
	return (pname and pname ~= "") and pname or ("Team " .. id)
end

-- a draggable knob: the fraction of what you have in store
local function ShareKnob(x1, y, x2, key, color)
	local trackY = y + sc(8)
	D.Rect(x1, trackY - sc(2), x2, trackY + sc(2), C.line, 1)
	local f = st.share[key]
	D.Rect(x1, trackY - sc(2), x1 + (x2 - x1) * f, trackY + sc(2), color, 0.9)
	local kx = x1 + (x2 - x1) * f
	D.Disc(kx, trackY, sc(7), color, 1)
	local function Set(x) st.share[key] = max(0, min(1, (x - x1) / (x2 - x1))) end
	D.Region(x1 - sc(8), y - sc(4), x2 + sc(8), y + sc(20), { click = function(x) Set(x) end, drag = function(x) Set(x) end, tip = "Drag the knob, or click on the bar" })
end

local function ShareResourceRow(x1, y, x2, key, label, color)
	local me = Spring.GetMyTeamID()
	local cur = Spring.GetTeamResources(me, key) or 0
	local amount = floor(cur * st.share[key] + 0.5)
	D.Text(label, x1, y + sc(26), sc(11), "o", color)
	D.Mono(string.format("%d of %d", amount, floor(cur)), x2, y + sc(26), sc(11), "or", C.text)
	ShareKnob(x1 + sc(4), y + sc(2), x2 - sc(4), key, color)
	local bw = (x2 - x1 - sc(4) * 5 - sc(70)) / 4
	local bx = x1
	for _, p in ipairs({ 0.1, 0.25, 0.5, 1 }) do
		D.Button(bx, y - sc(26), bx + bw, y - sc(6), p == 1 and "ALL" or (floor(p * 100) .. "%"), { size = sc(8), active = abs(st.share[key] - p) < 0.005, color = color, click = function() st.share[key] = p; Snd("ui_click") end })
		bx = bx + bw + sc(4)
	end
	local target = st.shareTeam
	D.Button(x2 - sc(70), y - sc(26), x2, y - sc(6), "SEND", { color = C.good, size = sc(9), tip = target and ("Send " .. amount .. " " .. key .. " to " .. TeamLabel(target)) or "Pick a player first",
		click = function()
			if not target then Spring.Echo("[VB] share: pick a player first") return end
			if Spring.GetSpectatingState() then return end
			local have = Spring.GetTeamResources(me, key) or 0
			local give = min(floor(have * st.share[key] + 0.5), floor(have))
			if give <= 0 then Spring.Echo("[VB] share: nothing to send") return end
			Spring.ShareResources(target, key, give)
			Spring.Echo(string.format("[VB] Sent %d %s to %s", give, key, TeamLabel(target)))
			Snd("ui_click")
		end })
end

local function TabShare(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local w3 = (x2 - x1 - gap * 2) / 3
	local allies = AllyTeams()
	if st.shareTeam then
		local ok = false
		for _, id in ipairs(allies) do if id == st.shareTeam then ok = true end end
		if not ok then st.shareTeam = nil end
	end
	if not st.shareTeam and #allies > 0 then st.shareTeam = allies[1] end

	-- who gets it
	local px1, py1, px2, py2 = D.Panel(x1, y1, x1 + w3, y2, "SEND TO")
	local y = py2 - sc(28)
	if Spring.GetSpectatingState() then
		TextBlock(px1 + sc(6), py2, px2 - px1 - sc(12), "Spectators have nothing to share.", sc(10), C.dim)
	elseif #allies == 0 then
		TextBlock(px1 + sc(6), py2, px2 - px1 - sc(12), "You have no living allies. Resources and units can only be shared inside your alliance.", sc(10), C.dim)
	end
	for _, id in ipairs(allies) do
		if y < py1 then break end
		local r, g, b = Spring.GetTeamColor(id)
		D.Rect(px1 + sc(6), y + sc(4), px1 + sc(12), y + sc(18), { r or 1, g or 1, b or 1 }, 1)
		D.Button(px1 + sc(16), y, px2 - sc(6), y + sc(22), TeamLabel(id), { active = st.shareTeam == id, click = function() st.shareTeam = id; Snd("ui_click") end })
		y = y - sc(28)
	end

	-- metal and energy
	local rx1, ry1, rx2, ry2 = D.Panel(x1 + w3 + gap, y1, x1 + 2 * w3 + gap, y2, "METAL AND ENERGY")
	local target = st.shareTeam
	D.Text(target and ("to  " .. TeamLabel(target)) or "to  nobody yet", rx1 + sc(6), ry2 - sc(18), sc(10), "o", C.dim)
	ShareResourceRow(rx1 + sc(6), ry2 - sc(86), rx2 - sc(6), "metal", "METAL", C.good)
	ShareResourceRow(rx1 + sc(6), ry2 - sc(176), rx2 - sc(6), "energy", "ENERGY", C.warn)

	-- units
	local ux1, uy1, ux2, uy2 = D.Panel(x1 + 2 * w3 + 2 * gap, y1, x2, y2, "UNITS")
	local sel = Spring.GetSelectedUnits() or {}
	D.Text("to  " .. (target and TeamLabel(target) or "nobody yet"), ux1 + sc(6), uy2 - sc(18), sc(10), "o", C.dim)
	D.Mono(#sel .. " selected", ux1 + sc(6), uy2 - sc(44), sc(14), "o", C.text)
	D.Button(ux1 + sc(6), uy2 - sc(86), ux2 - sc(6), uy2 - sc(58), "SEND SELECTED UNITS", { color = C.good, tip = "Gives the units you have selected to the chosen player",
		click = function()
			if not target then Spring.Echo("[VB] share: pick a player first") return end
			if #sel == 0 then Spring.Echo("[VB] share: select some units first, then open this page") return end
			if Spring.GetSpectatingState() then return end
			Spring.ShareResources(target, "units")
			Spring.Echo(string.format("[VB] Sent %d units to %s", #sel, TeamLabel(target)))
			Snd("ui_click")
		end })
	TextBlock(ux1 + sc(6), uy2 - sc(96), ux2 - ux1 - sc(12), "Select the units in the game first, then click SHARE in the top menu bar. Your commander can be given away too, so be careful.", sc(9), C.faint)
end

-- GRAPHICS: resolution and quality (the logic is in vb_graphics.lua, the quality is an FPS-OPS preset)
local function GraphicsPanel(x1, y1, x2, y2)
	local ax1, ay1, ax2, ay2 = D.Panel(x1, y1, x2, y2, "GRAPHICS")
	local G = WG and WG.VBGraphics
	if not G then
		TextBlock(ax1 + sc(6), ay2 - sc(4), ax2 - ax1 - sc(12), "The graphics widget (vb_graphics.lua) is not running.", sc(9), C.faint)
		return
	end
	local bw = min(sc(200), (ax2 - ax1) * 0.5)
	local y = ay2 - sc(30)

	local labels = {}
	for i, r in ipairs(G.Resolutions()) do labels[i] = r.label end
	D.Text("Resolution", ax1 + sc(6), y + sc(6), sc(10), "o", C.text)
	D.Dropdown(ax2 - bw, y, ax2, y + sc(22), { id = "resolution", options = labels, selected = G.Resolution(),
		text = "CUSTOM", onSelect = function(i) G.SetResolution(i); Snd("ui_click") end,
		tip = { "Resizes the window; the HUD is stacked again", "in one column at the new size" } })
	y = y - sc(34)

	local names, tips = {}, {}
	for i, q in ipairs(G.Qualities()) do names[i] = q.label; tips[i] = q.tip end
	D.Text("Graphics quality", ax1 + sc(6), y + sc(6), sc(10), "o", C.text)
	D.Dropdown(ax2 - bw, y, ax2, y + sc(22), { id = "quality", options = names, tips = tips, selected = G.Quality(),
		text = "CUSTOM (FPS-OPS)", onSelect = function(i) G.SetQuality(i); Snd("ui_click") end,
		tip = { "Lowest to ultra: turns settings down through FPS-OPS" } })
	y = y - sc(36)

	TextBlock(ax1 + sc(6), y + sc(14), ax2 - ax1 - sc(12), "Quality is the FPS-OPS optimiser: the lower, the more it turns down (icons, draw distances, particles, shadows, water, effects). Ultra leaves your engine settings as they are. /fpsops shows its panel and benchmark.", sc(9), C.faint)
end

local function TabSettings(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local w3 = (x2 - x1 - gap * 2) / 3
	-- the dashboard
	local ax1, ay1, ax2, ay2 = D.Panel(x1, y1, x1 + w3, y2, "THE DASHBOARD")
	local y = ay2 - sc(34)
	Toggle(ax1 + sc(6), y, ax2 - ax1 - sc(12), "Menu bar (top of the screen)", st.menu, function() st.menu = not st.menu; Snd("ui_click") end, "/vbdash menu"); y = y - sc(32)
	Toggle(ax1 + sc(6), y, ax2 - ax1 - sc(12), "HUD with the leaderboard", st.hud, function() st.hud = not st.hud; Snd("ui_click") end, "/vbdash hud"); y = y - sc(32)
	D.Text("Interface size", ax1 + sc(6), y + sc(5), sc(10), "o", C.text)
	D.Button(ax2 - sc(110), y, ax2 - sc(80), y + sc(20), "-", { click = function() st.scale = max(0.6, st.scale - 0.1); Snd("ui_click") end })
	D.Mono(string.format("%d%%", st.scale * 100 + 0.5), ax2 - sc(45), y + sc(5), sc(11), "oc", C.text)
	D.Button(ax2 - sc(30), y, ax2, y + sc(20), "+", { click = function() st.scale = min(2.0, st.scale + 0.1); Snd("ui_click") end }); y = y - sc(32)
	D.Text("Radar in the HUD", ax1 + sc(6), y + sc(5), sc(10), "o", C.text)
	D.Button(ax2 - sc(150), y, ax2 - sc(76), y + sc(20), "COMBAT", { size = sc(8), active = st.hudRadar == 1, click = function() st.hudRadar = 1 end })
	D.Button(ax2 - sc(72), y, ax2, y + sc(20), "ECONOMY", { size = sc(8), active = st.hudRadar == 2, click = function() st.hudRadar = 2 end }); y = y - sc(40)
	y = TextBlock(ax1 + sc(6), y + sc(14), ax2 - ax1 - sc(12), "Everything is saved with your other widget settings. /vbdash [open|close|hud|menu|tab <name>|scale <n>] does the same from the chat.", sc(9), C.faint)

	-- graphics (top of the middle column) and the game (below it)
	local gh = sc(178)
	GraphicsPanel(x1 + w3 + gap, y2 - gh, x1 + 2 * w3 + gap, y2)
	local bx1, by1, bx2, by2 = D.Panel(x1 + w3 + gap, y1, x1 + 2 * w3 + gap, y2 - gh - gap, "THE GAME")
	y = by2 - sc(34)
	local function Row(label, cmd, tip)
		D.Button(bx1 + sc(6), y, bx2 - sc(6), y + sc(24), label, { click = Command(cmd), tip = tip }); y = y - sc(32)
	end
	Row("UNIT GROWTH AND SPLITTING", "vbsettings", "/vbsettings: the experience at which units split, and how much they grow first")
	Row("UNIT FORGE", "vbforge", "/vbforge: design your own units")
	Row("UNIT CENSUS OF THE SELECTION", "vbstats", "/vbstats")
	Row("SENSOR RANGES", "vbranges", "/vbranges")
	Row("DEV CONSOLE", "vbconsole", "/vbconsole")
	D.Text("Sound", bx1 + sc(6), y + sc(5), sc(10), "o", C.text)
	local hw = (bx2 - bx1 - sc(12) - sc(60)) / 2
	D.Button(bx2 - sc(6) - hw * 2 - sc(4), y, bx2 - sc(10) - hw, y + sc(20), "ON", { size = sc(8), click = function() Spring.SendCommands("vbsound on") end })
	D.Button(bx2 - sc(6) - hw, y, bx2 - sc(6), y + sc(20), "OFF", { size = sc(8), click = function() Spring.SendCommands("vbsound off") end })

	-- this game
	local cx1, cy1, cx2, cy2 = D.Panel(x1 + 2 * w3 + 2 * gap, y1, x2, y2, "THIS MATCH")
	local mo = Spring.GetModOptions() or {}
	local total, humans, ais, alive = Stats.PlayerCounts()
	local rows = {
		{ "Players", total .. " (" .. humans .. " human, " .. ais .. " bot)" }, { "Still alive", tostring(alive) },
		{ "Commander ends the game", (mo.commander_ends == "0" or mo.commander_ends == false) and "no" or "yes" },
		{ "Starting metal / energy", (mo.startmetal or "1000") .. " / " .. (mo.startenergy or "1000") },
		{ "Units split at (xp)", tostring(mo.split_xp or "0.14") }, { "Growth before the split", tostring(mo.max_growth or "1.00") },
		{ "Bot skill", tostring(mo.bot_skill or "2") },
		{ "Statistics visibility", mo.stats_visibility == "all" and "all teams" or "fog of war" },
	}
	y = cy2 - sc(30)
	for _, r in ipairs(rows) do
		D.Text(r[1], cx1 + sc(6), y, sc(10), "o", C.dim)
		D.Mono(r[2], cx2 - sc(6), y, sc(10), "or", C.text)
		D.HLine(cx1 + sc(6), cx2 - sc(6), y - sc(6), C.line, 0.6)
		y = y - sc(24)
	end
	TextBlock(cx1 + sc(6), y, cx2 - cx1 - sc(12), "These are the lobby's mod options. The host sets them before the game starts; growth and splitting can also be changed in the game.", sc(9), C.faint)
end

local KIND_NAMES = {
	mex = "Metal extractor", solar = "Energy generator", fac = "Factory", radar = "Radar", store = "Storage", def1 = "Light defence",
	def2 = "Heavy defence", heart = "Advanced energy", con = "Builder", scout = "Scout", raider = "Raider", assault = "Assault unit",
	art = "Artillery", support = "Support unit", heavy = "Heavy unit",
}
local DEFAULT_KEYS = {
	orders = { a = "attack", s = "stop", m = "move", f = "fight", p = "patrol", g = "guard", r = "repair", e = "reclaim", t = "resurrect", d = "vbdgun", q = "vbdestab", k = "vbcloak", w = "wait", y = "capture" },
	build = { z = "mex", x = "solar", c = "fac", v = "radar", b = "store", n = "def1", j = "def2", u = "heart" },
	factory = { z = "con", x = "scout", c = "raider", v = "assault", b = "art", n = "support", j = "heavy" },
}

local function KeyList(x1, y1, x2, y2, title, map, names)
	local ix1, iy1, ix2, iy2 = D.Panel(x1, y1, x2, y2, title)
	local keys = {}
	for k in pairs(map) do keys[#keys + 1] = k end
	table.sort(keys)
	local rowH = min(sc(26), (iy2 - iy1) / max(#keys, 1))
	for i, k in ipairs(keys) do
		local ry = iy2 - i * rowH
		D.Rect(ix1 + sc(4), ry + rowH * 0.12, ix1 + sc(30), ry + rowH * 0.88, C.panel2, 1)
		D.Frame(ix1 + sc(4), ry + rowH * 0.12, ix1 + sc(30), ry + rowH * 0.88, C.accent, 0.6)
		D.Mono(k:upper(), ix1 + sc(17), ry + rowH * 0.5 - sc(5), sc(12), "oc", C.text)
		local v = map[k]
		local label = names and (names[v] or v) or (v:sub(1, 1):upper() .. v:sub(2))
		D.Text(label, ix1 + sc(40), ry + rowH * 0.5 - sc(4), sc(10), "o", C.dim)
	end
end

local function TabKeys(x1, y1, x2, y2, ctx)
	local K = (WG and WG.VBHotkeys) or DEFAULT_KEYS
	local gap = sc(8)
	local w4 = (x2 - x1 - gap * 3) / 4
	KeyList(x1, y1, x1 + w4, y2, "ORDERS (UNITS SELECTED)", K.orders or DEFAULT_KEYS.orders)
	KeyList(x1 + w4 + gap, y1, x1 + 2 * w4 + gap, y2, "BUILDER SELECTED: BUILD", K.build or DEFAULT_KEYS.build, KIND_NAMES)
	KeyList(x1 + 2 * (w4 + gap), y1, x1 + 3 * w4 + 2 * gap, y2, "FACTORY SELECTED: QUEUE", K.factory or DEFAULT_KEYS.factory, KIND_NAMES)
	local ix1, iy1, ix2, iy2 = D.Panel(x1 + 3 * (w4 + gap), y1, x2, y2, "EVERYTHING ELSE")
	local rows = {
		{ "Ctrl+D", "detonate the selected units" }, { "Tab", "select your commander" }, { "Ctrl+Shift+D", "statistics dashboard" }, { "Esc, 1-9", "close, switch page" },
		{ "Left / Right", "step through time" }, { "Home / End", "start / back to live" }, { "Mouse wheel", "zoom the time axis" },
		{ "Enter", "start (before the game)" }, { "/vbsettings", "unit growth and splitting" }, { "/vbforge", "unit forge" },
		{ "/vbconsole or ~", "dev console" }, { "/vbstats", "census of the selection" }, { "/vbranges", "sensor ranges" },
		{ "/vbsound", "on | off | vol 0-100" }, { "/vbkeys", "list the keys in the chat" }, { "/vbdash", "this dashboard" },
	}
	local rowH = min(sc(24), (iy2 - iy1) / #rows)
	for i, r in ipairs(rows) do
		local ry = iy2 - i * rowH
		D.Mono(r[1], ix1 + sc(6), ry + rowH * 0.5 - sc(4), sc(10), "o", C.text)
		D.Text(D.Fit(r[2], sc(9), ix2 - ix1 - sc(124)), ix1 + sc(118), ry + rowH * 0.5 - sc(4), sc(9), "o", C.dim)
	end
end

local ABOUT = {
	{ "VOIDBORN", "A 3D space RTS for the Spring / Recoil engine. Five factions of surreal alien monsters, one for each sense organ, fight over floating asteroids in deep space. Every mobile unit flies, each at its own altitude: a scout at 60 elmos and a heavy at 230 are in different places, and that decides fights.\n\nChoir of the Eye: pale, many-eyed cyclopes. Long-range lasers, fragile up close.\nMaw Swarm (the mouth): chitinous, toothed, many-legged. Short reach, tougher, regenerating and cheaper.\n\nTympan Conclave (the ear): floating ears, horns and drums. Waves of sound with wide splash; the more of them hit one target, the harder each hit lands. Radar on their units, short sight, and ears that blow a cloak.\n\nMiasma Bloom (the nose): drifting snouts and flowers. Slow and tough; every hit poisons and scents its target, so the Bloom sees what it has tasted. Their Censer sniffs out mushrooms faster.\n\nHaptic Grasp (the hand): hands and tentacles. The shortest sight and reach of all, but a Haptic weapon hits up to 75% harder the closer the enemy is. Its raiders are kamikazes: a Clutch that touches an enemy bursts and grips it, and a gripped enemy takes more from every Haptic weapon." },
	{ "HOW A MATCH GOES", "Start with your commander. Put metal extractors on the metal spots, add energy, build a factory and fill it with builders and fighters. Defences, radar and storage support them.\n\nLose your commander and you lose the game (the host can switch that off). Fire the commander's super weapon by hand.\n\nMobile units gain experience, grow and split in two at 0.14: a veteran army becomes two armies." },
	{ "BUILD YOUR OWN UNITS", "The unit forge creates a new unit while the game runs: pick a base unit, change its health, speed, range, damage, reload, sight and altitude, give it a new 3D body of boxes, spheres, cylinders and cones, and map a picture onto it.\n\nEvery custom unit is priced automatically: the stronger it is, the more metal and build time it costs. Open it with the [+] tile at the end of the build row or /vbforge." },
	{ "STATISTICS AND THE LEADERBOARD", "The SCORE sums up a team: the value of everything it has alive + 1.5 x the enemy value it destroyed + 0.05 x the damage it dealt + 0.2 x the metal it produced - 0.25 x the value it lost.\n\nFog of war applies: you see your own side's numbers in full. A hidden enemy is scored only from the units you have actually seen (marked ~), and ? means you have not met it yet. Spectators and the end of the game show everything." },
}

local function TabAbout(x1, y1, x2, y2, ctx)
	local gap = sc(8)
	local cells = Grid(x1, y1, x2, y2 - sc(40), 2, 2, gap)
	local ver = ""
	pcall(function()
		local v = Game and Game.gameVersion
		if v and v ~= "" then ver = "   -   version " .. tostring(v) end
	end)
	D.Text("VOIDBORN", x1 + sc(4), y2 - sc(24), sc(22), "o", C.accent)
	D.Text("a game by goddot   -   free and open source (GPL)" .. ver, x1 + sc(150), y2 - sc(22), sc(10), "o", C.faint)
	for k, a in ipairs(ABOUT) do
		local r = cells[k]
		local ix1, iy1, ix2, iy2 = D.Panel(r[1], r[2], r[3], r[4], a[1])
		TextBlock(ix1 + sc(6), iy2 - sc(4), ix2 - ix1 - sc(12), a[2], sc(11), C.dim, sc(17))
	end
end

--------------------------------------------------------------------------------
-- the menu bar and the leaderboard line
--------------------------------------------------------------------------------
local counts = { 0, 0, 0, 0 }
local menuRect = nil
local function DrawMenu(ctx)
	menuRect = nil
	if not st.menu then return end
	local h = sc(24)
	local items = { { "STATS", "overview" }, { "SHARE", "share" }, { "SETTINGS", "settings" }, { "KEYS", "keys" }, { "ABOUT", "about" }, { "RESIGN", "resign" } }
	local info = string.format("%d PLAYERS", counts[1]) .. (counts[1] ~= counts[4] and string.format("  -  %d ALIVE", counts[4]) or "")
	local w = sc(14) * 2
	for _, it in ipairs(items) do w = w + D.W(it[1], sc(10)) + sc(24) + sc(3) end
	local infoW = D.W(info, sc(9)) + sc(20)
	w = w + infoW
	local x1 = (vsx - w) / 2
	local y2 = vsy
	local y1 = y2 - h
	menuRect = { x1, y1, x1 + w, y2 }
	D.Rect(x1, y1, x1 + w, y2, C.bg, 0.88)
	D.Frame(x1, y1, x1 + w, y2, C.line, 1)
	D.Rect(x1, y1, x1 + w, y1 + 1, C.accent, 0.5)
	-- the backing region goes FIRST: D.Hit() walks the regions from the last to the first, so a region
	-- registered after the buttons would swallow every click on them
	D.Region(x1, y1, x1 + w, y2, {})
	local x = x1 + sc(14)
	for _, it in ipairs(items) do
		local bw = D.W(it[1], sc(10)) + sc(24)
		local tip
		if it[1] == "STATS" then
			tip = "Statistics dashboard (Ctrl+Shift+D)"
		elseif it[1] == "RESIGN" then
			tip = (st.resignArmed and os.clock() - st.resignArmed < 4) and "Click again to resign now" or "Resign from the match (asks for a second click)"
		else
			tip = nil
		end
		local click
		if it[1] == "RESIGN" then
			click = function()
				if Spring.GetSpectatingState() then Spring.Echo("[VB] you are already a spectator") return end
				if st.resignArmed and os.clock() - st.resignArmed < 4 then
					st.resignArmed = nil
					-- the engine has no "resign" command: becoming a spectator is how a player resigns
					Spring.SendCommands("spectator")
					Close()
				else
					st.resignArmed = os.clock()
					Spring.Echo("[VB] Click RESIGN again within 4 seconds to resign")
				end
			end
		else
			click = function() Open(it[2]) end
		end
		local armed = it[1] == "RESIGN" and st.resignArmed and os.clock() - st.resignArmed < 4
		D.Button(x, y1 + sc(3), x + bw, y2 - sc(3), armed and "SURE?" or it[1], { click = click, tip = tip, active = armed and true or false, color = armed and C.bad or nil })
		x = x + bw + sc(3)
	end
	local rank
	for _, r in ipairs(Stats.Leaderboard()) do if r.team.ally == Spring.GetMyAllyTeamID() then rank = rank or r.rank end end
	D.Text(info, x + sc(8), y1 + sc(8), sc(9), "o", C.dim)
end

local function TeamCards(x1, y1, x2, y2, ctx)
	local board = Stats.Leaderboard()
	local list = ctx.all
	local n = #board
	local h = min(sc(64), (y2 - y1) / max(n, 1))
	for k, row in ipairs(board) do
		local t = row.team
		local cy2 = y2 - (k - 1) * h
		local cy1 = cy2 - h + sc(3)
		local c = Stats.ViewColor(t)
		local hot = D.Inside(x1, cy1, x2, cy2)
		local seen = not row.est
		local shown = seen and not st.hidden[t.id]
		D.Rect(x1, cy1, x2, cy2, hot and seen and C.panel2 or C.bg, shown and 0.95 or 0.45)
		D.Rect(x1, cy1, x1 + sc(5), cy2, c, shown and 0.95 or 0.3)
		local a = shown and 1 or 0.55
		D.Mono("#" .. row.rank, x2 - sc(8), cy2 - sc(18), sc(11), "or", C.faint, a)
		D.Text(D.Fit(t.name, sc(12), x2 - x1 - sc(52)), x1 + sc(14), cy2 - sc(19), sc(12), "o", c, a)
		local status = t.side ~= "" and t.side or ("team " .. t.id)
		local sc2 = C.faint
		if Stats.over and Stats.over.winners[t.ally] then status = status .. "  WINNER"; sc2 = C.good
		elseif t.dead then status = status .. "  ELIMINATED"; sc2 = C.bad end
		D.Text(status, x1 + sc(14), cy2 - sc(32), sc(8), "o", sc2, a)
		if seen then
			local i = ctx.idx[t.id]
			D.Mono("SCORE " .. Stats.Num(Stats.Value(t, "sc", i)) .. "  ARMY " .. Stats.Num(Stats.Value(t, "av", i)), x1 + sc(14), cy1 + sc(15), sc(9), "o", C.dim, a)
			D.Mono("M " .. Stats.Rate(Stats.Value(t, "mi", i)) .. "/s   E " .. Stats.Rate(Stats.Value(t, "ei", i)) .. "/s", x1 + sc(14), cy1 + sc(4), sc(9), "o", C.dim, a)
			if st.hidden[t.id] then D.Text("HIDDEN", x2 - sc(8), cy2 - sc(32), sc(8), "or", C.faint) end
			D.Region(x1, cy1, x2, cy2, { tip = "Click: show / hide in the graphs.  Right click: only this team",
				click = function(_, _, b)
					if b == 3 then
						local only = true
						for _, o in ipairs(list) do if o ~= t and not st.hidden[o.id] then only = false end end
						if st.hidden[t.id] then only = false end
						for _, o in ipairs(list) do st.hidden[o.id] = (not only) and (o ~= t) or nil end
					else
						st.hidden[t.id] = (not st.hidden[t.id]) or nil
					end
					Snd("ui_click")
				end })
		else
			-- fog of war: only what has been seen
			local I = row.intel
			if I and I.lastSeen then
				D.Mono("SEEN ~" .. Stats.Num(I.value) .. " in " .. I.count .. " units", x1 + sc(14), cy1 + sc(15), sc(9), "o", C.dim, a)
				local ago = max(0, (ctx.last - I.lastSeen) / FPS)
				D.Mono(ago < 2 and "in sight now" or string.format("last seen %s ago", Stats.Time(ago * FPS)), x1 + sc(14), cy1 + sc(4), sc(9), "o", ago < 2 and C.good or C.faint, a)
			else
				D.Text("FOG OF WAR - not scouted yet", x1 + sc(14), cy1 + sc(9), sc(9), "o", C.faint, a)
			end
			D.Region(x1, cy1, x2, cy2, { tip = "Hidden by the fog of war: its statistics appear when the game ends. The score is estimated from the units you have seen." })
		end
	end
	return y2 - n * h
end

local function EventList(x1, y1, x2, y2, ctx)
	local ex1, ey1, ex2, ey2 = D.Panel(x1, y1, x2, y2, "EVENTS", { right = "click to jump" })
	local ev = {}
	for _, e in ipairs(Stats.events) do if Stats.Visible(e[2]) then ev[#ev + 1] = e end end
	table.sort(ev, function(a, b) return a[1] > b[1] end)
	local rowH = sc(26)
	if #ev == 0 then D.Text("nothing has happened yet", (ex1 + ex2) / 2, (ey1 + ey2) / 2, sc(9), "oc", C.faint) end
	for k, e in ipairs(ev) do
		local ry2 = ey2 - (k - 1) * rowH
		local ry1 = ry2 - rowH
		if ry1 < ey1 - 1 then break end
		local team = Stats.teams[e[2]]
		local c = team and Stats.ViewColor(team) or C.text
		local hot = D.Inside(ex1, ry1, ex2, ry2)
		if hot then D.Rect(ex1, ry1, ex2, ry2, C.panel2, 0.9) end
		D.Rect(ex1, ry1 + sc(3), ex1 + sc(3), ry2 - sc(3), c, 0.95)
		D.Mono(Stats.Time(e[1]), ex1 + sc(8), ry1 + rowH * 0.5 - sc(4), sc(9), "o", C.dim)
		D.Text(D.Fit(Stats.EventText(e), sc(9), ex2 - ex1 - sc(54)), ex1 + sc(50), ry1 + rowH * 0.5 - sc(3), sc(9), "o", hot and C.text or c)
		D.Region(ex1, ry1, ex2, ry2, { click = function() st.cursor = e[1]; Snd("ui_click") end })
	end
end

local function Timeline(x1, y1, x2, y2, ctx)
	local px1, py1, px2, py2 = D.Panel(x1, y1, x2, y2, nil)
	local px = D.LineChart(px1 + sc(4), py1, px2 - sc(4), py2, {
		teams = ctx.shown, metric = "av", f0 = 0, f1 = max(ctx.last, 900), cursor = ctx.cursor, fill = true, minimal = true,
		onClick = function(f, b) st.cursor = (b == 1) and max(0, min(f, ctx.last)) or nil end,
		onDrag = function(f) st.cursor = max(0, min(f, ctx.last)) end,
	})
	-- the events on the timeline
	for _, e in ipairs(Stats.events) do
		if Stats.Visible(e[2]) and ctx.last > 0 then
			local team = Stats.teams[e[2]]
			local x = px1 + sc(4) + (e[1] / max(ctx.last, 900)) * (px2 - px1 - sc(8))
			D.Rect(x - 1, py1, x + 1, py1 + sc(7), Stats.ViewColor(team), 0.95)
		end
	end
	D.Text("ARMY VALUE OVER THE WHOLE GAME - click or drag to pick a moment", px1 + sc(8), py2 - sc(11), sc(8), "o", C.faint)
end

local function DrawDashboard(ctx)
	local margin = sc(24)
	local P = { margin, margin, vsx - margin, vsy - margin }
	panelRect = P
	-- dim the game and swallow the clicks; a click outside the panel closes it
	D.Rect(0, 0, vsx, vsy, { 0, 0, 0 }, 0.62)
	D.Region(0, 0, vsx, vsy, { click = function(x, y) if not (x >= P[1] and x <= P[3] and y >= P[2] and y <= P[4]) then Close() end end })
	D.Rect(P[1], P[2], P[3], P[4], C.bg, 0.97)
	D.Frame(P[1], P[2], P[3], P[4], C.line, 1, 1)
	D.Region(P[1], P[2], P[3], P[4], {})

	-- the title bar
	local topH = sc(44)
	D.Rect(P[1], P[4] - topH, P[3], P[4], C.panel, 1)
	D.HLine(P[1], P[3], P[4] - topH, C.line, 1)
	D.Text("VOIDBORN", P[1] + sc(14), P[4] - sc(29), sc(17), "o", C.accent)
	D.Text("STATISTICS", P[1] + sc(14) + D.W("VOIDBORN ", sc(17)), P[4] - sc(28), sc(13), "o", C.dim)
	local tx = P[1] + sc(250)
	for k, tab in ipairs(TABS) do
		if k == FIRST_MENU_TAB then tx = tx + sc(14); D.VLine(tx - sc(9), P[4] - topH + sc(10), P[4] - sc(10), C.line, 1) end
		local w = D.W(tab[2], sc(10)) + sc(24)
		D.Button(tx, P[4] - topH + sc(8), tx + w, P[4] - sc(8), tab[2], { active = st.tab == tab[1], click = function() SetTab(tab[1]) end, tip = k <= 9 and ("Key " .. k) or nil })
		tx = tx + w + sc(3)
	end
	D.Button(P[3] - sc(40), P[4] - topH + sc(8), P[3] - sc(8), P[4] - sc(8), "X", { color = C.bad, click = Close, tip = "Close (Esc)" })

	-- the clock and unit count
	local clockText = (ctx.cursor and "VIEWING " or "LIVE ") .. Stats.Time(ctx.frame)
	-- compute total unit count across all visible teams
	local totalUnits = 0
	for _, t in ipairs(Stats.VisibleTeams()) do
		local v = Stats.Value(t, "uc", ctx.idx[t.id])
		if v then totalUnits = totalUnits + v end
	end
	D.Mono(clockText .. "  |  " .. totalUnits .. " units", P[3] - sc(60), P[4] - sc(30), sc(15), "or", ctx.cursor and C.warn or C.good)
	if Stats.over then D.Text("GAME OVER", P[3] - sc(60), P[4] - sc(43), sc(8), "or", C.bad) end

	-- the bottom bar: time and window
	local botH = sc(76)
	local sideW = sc(250)
	local gap = sc(8)
	local bx1 = P[1] + gap
	D.Button(bx1, P[2] + gap, bx1 + sideW - gap, P[2] + gap + sc(26), ctx.cursor and "BACK TO LIVE" or "LIVE", { active = not ctx.cursor, color = C.good, click = function() st.cursor = nil; Snd("ui_click") end, tip = "End" })
	D.Text("TIME AXIS", bx1, P[2] + gap + sc(36), sc(8), "o", C.faint)
	local wx = bx1
	for _, w in ipairs(WINDOWS) do
		local bw = (sideW - gap - sc(4) * 3) / 4
		D.Button(wx, P[2] + gap + sc(48), wx + bw, P[2] + gap + sc(66), w[2], { size = sc(8), active = st.window == w[1], click = function() st.window = w[1]; Snd("ui_click") end })
		wx = wx + bw + sc(4)
	end
	Timeline(P[1] + sideW + gap, P[2] + gap, P[3] - gap, P[2] + botH, ctx)

	-- the sidebar: team cards and events
	local sx1, sx2 = P[1] + gap, P[1] + sideW
	local sy2 = P[4] - topH - gap
	local sy1 = P[2] + botH + gap
	local cardsBottom = TeamCards(sx1, sy1 + (sy2 - sy1) * 0.40, sx2, sy2, ctx)
	EventList(sx1, sy1, sx2, min(cardsBottom - gap, sy1 + (sy2 - sy1) * 0.40 + sc(2)), ctx)

	-- the page
	local mx1, my1, mx2, my2 = P[1] + sideW + gap, P[2] + botH + gap, P[3] - gap, P[4] - topH - gap
	if #ctx.all == 0 then
		D.Text("Waiting for the first measurements ...", (mx1 + mx2) / 2, (my1 + my2) / 2, sc(14), "oc", C.dim)
		return
	end
	local tab = st.tab
	if tab == "overview" then TabOverview(mx1, my1, mx2, my2, ctx)
	elseif tab == "graphs" then TabGraphs(mx1, my1, mx2, my2, ctx)
	elseif tab == "economy" then TabEconomy(mx1, my1, mx2, my2, ctx)
	elseif tab == "combat" then TabCombat(mx1, my1, mx2, my2, ctx)
	elseif tab == "army" then TabArmy(mx1, my1, mx2, my2, ctx)
	elseif tab == "share" then TabShare(mx1, my1, mx2, my2, ctx)
	elseif tab == "settings" then TabSettings(mx1, my1, mx2, my2, ctx)
	elseif tab == "keys" then TabKeys(mx1, my1, mx2, my2, ctx)
	elseif tab == "about" then TabAbout(mx1, my1, mx2, my2, ctx)
	else TabReport(mx1, my1, mx2, my2, ctx) end
end

--------------------------------------------------------------------------------
-- the HUD
--------------------------------------------------------------------------------
local function DrawHud(ctx)
	local W = sc(HUD_W)
	local head = sc(24)
	local list = {}
	for _, t in ipairs(ctx.all) do list[#list + 1] = t end
	table.sort(list, function(a, b) return Stats.Value(a, "av", ctx.idx[a.id]) > Stats.Value(b, "av", ctx.idx[b.id]) end)
	local board = Stats.Leaderboard()
	local shownRows = min(#board, 6)
	local rowH = sc(16)
	local tableH = (shownRows + 1) * rowH + (#board > shownRows and rowH or 0) + sc(6)
	local bodyH = sc(132)
	local H = st.hudCollapsed and head or (head + tableH + bodyH + sc(8))
	if not st.hudX then st.hudX = vsx - W - sc(12) end
	if not st.hudTop then st.hudTop = vsy - sc(120) end
	st.hudX = max(0, min(vsx - W, st.hudX)); st.hudTop = max(H, min(vsy, st.hudTop))
	local x1, y2 = st.hudX, st.hudTop
	local x2, y1 = x1 + W, y2 - H
	hudRect = { x1, y1, x2, y2 }

	if not st.hud then
		-- only a small button is left
		local bw, bh = sc(62), sc(20)
		D.Rect(x2 - bw, y2 - bh, x2, y2, C.panel, 0.85)
		D.Frame(x2 - bw, y2 - bh, x2, y2, D.Inside(x2 - bw, y2 - bh, x2, y2) and C.accent or C.line, 0.9)
		D.Text("STATS", x2 - bw / 2, y2 - bh + sc(6), sc(9), "oc", C.dim)
		hudRect = { x2 - bw, y2 - bh, x2, y2 }
		D.Region(x2 - bw, y2 - bh, x2, y2, { tip = "Open the statistics dashboard", click = function() Open() end })
		return
	end

	D.Rect(x1, y1, x2, y2, C.bg, 0.86)
	D.Frame(x1, y1, x2, y2, C.line, 1)
	D.Rect(x1, y2 - head, x2, y2, C.panel, 0.95)
	D.Rect(x1, y2 - head, x1 + sc(4), y2, C.accent, 0.9)
	D.Text("STATS", x1 + sc(12), y2 - head + sc(8), sc(10), "o", C.dim)
	D.Mono(counts[1] .. " PLAYERS  " .. Stats.Time(ctx.last), x1 + sc(60), y2 - head + sc(7), sc(10), "o", C.faint)
	D.Region(x1, y2 - head, x2 - sc(100), y2, { tip = "Drag to move",
		click = function(x, y) UserTookOver(); dragging = { x - st.hudX, y - st.hudTop }; return true end,
		drag = function(x, y) if dragging then st.hudX, st.hudTop = x - dragging[1], y - dragging[2] end end })
	local bx = x2 - sc(4)
	local function HeadButton(label, w, fn, tip, color)
		bx = bx - w
		D.Button(bx, y2 - head + sc(3), bx + w, y2 - sc(3), label, { size = sc(8), color = color, click = fn, tip = tip })
		bx = bx - sc(3)
	end
	HeadButton("X", sc(18), function() st.hud = false; Snd("ui_close") end, "Hide the HUD (/vbdash hud brings it back)", C.bad)
	HeadButton(st.hudCollapsed and "+" or "-", sc(18), function() st.hudCollapsed = not st.hudCollapsed; Snd("ui_click") end, "Fold the HUD")
	HeadButton("OPEN", sc(44), function() Open() end, "Open the full dashboard (Ctrl+Shift+D)", C.good)
	if st.hudCollapsed then return end

	-- the leaderboard: ranked by SCORE; a team hidden by the fog of war is scored from what has been seen (~)
	local ty = y2 - head - sc(2)
	local colR = {}                                   -- right edge of every column, laid out from the right
	local edge = x2 - sc(6)
	for k = #HUD_COLS, 1, -1 do colR[k] = edge; edge = edge - sc(HUD_COLS[k].w) end
	local nameX = x1 + sc(48)
	local nameW = edge - nameX - sc(4)
	for k, c in ipairs(HUD_COLS) do D.Text(c.head, colR[k], ty - rowH + sc(4), sc(8), "or", C.faint) end
	for r = 1, shownRows do
		local row = board[r]
		local t = row.team
		local ry = ty - r * rowH - rowH + sc(4)
		local c = Stats.ViewColor(t)
		local mine = t.ally == Spring.GetMyAllyTeamID()
		if mine then D.Rect(x1 + sc(2), ry, x2 - sc(2), ry + rowH - sc(2), C.accent, 0.08) end
		D.Mono(tostring(row.rank), x1 + sc(16), ry + sc(3), sc(9), "or", C.faint)
		D.Rect(x1 + sc(21), ry + sc(1), x1 + sc(25), ry + rowH - sc(3), c, 0.95)
		local e = teamInfo[t.id]
		if e and e.ai then D.Mono("AI", x1 + sc(30), ry + sc(3), sc(7), "o", C.faint) else DrawFlag(e and e.cc, x1 + sc(30), ry + sc(3), sc(14), sc(10)) end
		D.Text(D.Fit(t.name, sc(9), nameW), nameX, ry + sc(3), sc(9), "o", t.dead and C.faint or c)
		for k, col in ipairs(HUD_COLS) do
			local id = col.id
			local txt, tc = "?", C.faint
			if id == "ping" then
				txt, tc = PingText(e)                 -- player data, not hidden by the fog of war
			elseif id == "fps" then
				txt, tc = FpsText(e)
			elseif id == "units" then
				if not row.est then
					local u = UnitsOf(t, e, ctx.idx[t.id])
					if u then
						local mx = e and e.maxUnits
						txt = mx and (u .. "/" .. mx) or tostring(u)
						tc = (mx and u >= mx * 0.95) and C.bad or ((mx and u >= mx * 0.8) and C.warn or C.text)
					end
				end
			elseif row.est then
				if id == "sc" and row.score then txt, tc = "~" .. Stats.Num(row.score), C.dim end
			else
				txt, tc = Stats.Format(Stats.M[id], Stats.Value(t, id, ctx.idx[t.id])), C.text
			end
			D.Mono(txt, colR[k], ry + sc(3), sc(9), "or", tc)
		end
	end
	if #board > shownRows then
		D.Text("+" .. (#board - shownRows) .. " more", x1 + sc(30), ty - (shownRows + 2) * rowH + sc(7), sc(8), "o", C.faint)
	end
	D.Region(x1, y2 - head - tableH, x2, y2 - head, { tip = "Open the dashboard", click = function() Open() end })

	-- the radar and the sparklines
	local by2 = y2 - head - tableH
	local by1 = y1 + sc(4)
	local radarW = sc(176)
	local def = Stats.RADARS[st.hudRadar]
	local R = min(radarW / 2 - sc(26), (by2 - by1) / 2 - sc(14))
	local rcx, rcy = x1 + radarW / 2 + sc(2), (by1 + by2) / 2 - sc(4)
	local short = {}
	for _, id in ipairs(def.axes) do local m = Stats.M[id]; short[#short + 1] = { label = def.hud[id] or m.label, fmt = function(v) return Stats.Format(m, v) end } end
	local shownTeams = {}
	for _, t in ipairs(list) do shownTeams[#shownTeams + 1] = t end
	local entries = {}
	for _, t in ipairs(shownTeams) do
		local vals = {}
		for k, id in ipairs(def.axes) do vals[k] = Stats.Value(t, id, ctx.idx[t.id]) end
		entries[#entries + 1] = { name = t.name, color = Stats.ViewColor(t), vals = vals }
	end
	D.Radar(rcx, rcy, R, short, entries, { small = true })
	D.Text(def.name, x1 + sc(6), by2 - sc(8), sc(8), "o", C.faint)
	D.Region(x1, by1, x1 + radarW, by2, { tip = "Click: switch between the combat and the economy radar",
		click = function() st.hudRadar = st.hudRadar % #Stats.RADARS + 1; Snd("ui_click") end })

	local sx1 = x1 + radarW + sc(4)
	local ids = { "av", "mi", "dd" }
	local sh = (by2 - by1) / #ids
	for k, id in ipairs(ids) do
		local sy2 = by2 - (k - 1) * sh
		local sy1 = sy2 - sh + sc(3)
		local m = Stats.M[id]
		D.Text(m.label:upper(), sx1 + sc(2), sy2 - sc(10), sc(8), "o", m.color)
		D.LineChart(sx1, sy1, x2 - sc(6), sy2 - sc(11), { teams = ctx.all, metric = id, f0 = 0, f1 = max(ctx.last, 900), fill = true, minimal = true })
		D.Region(sx1, sy1, x2, sy2, { tip = m.label .. ": open the graph", click = function() st.focus = id; Open("graphs") end })
	end
end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
function widget:Initialize()
	Stats.Reset()
	widgetHandler:RegisterGlobal("VBStats_Sample", function(...) Stats.OnSample(...) end)
	widgetHandler:RegisterGlobal("VBStats_Units", function(...) Stats.OnUnits(...) end)
	widgetHandler:RegisterGlobal("VBStats_Defs", function(...) Stats.OnDefs(...) end)
	widgetHandler:RegisterGlobal("VBStats_Event", function(...) Stats.OnEvent(...) end)
	widgetHandler:RegisterGlobal("VBStats_Over", function(...)
		Stats.OnOver(...)
		if not st.autoOpened then st.autoOpened = true; st.open = true; st.tab = "report"; st.cursor = nil end
	end)
	-- the gadget keeps everything it sent: a reloaded widget asks for it again
	Spring.SendLuaRulesMsg("vbstats:replay")
	-- this dashboard takes the place of the engine's end-of-game graph
	pcall(Spring.SendCommands, "endgraph 0")
	Spring.Echo("[VB] Dashboard loaded: Ctrl+Shift+D or /vbdash opens it")
end

function widget:Shutdown()
	for _, n in ipairs({ "VBStats_Sample", "VBStats_Units", "VBStats_Defs", "VBStats_Event", "VBStats_Over" }) do
		widgetHandler:DeregisterGlobal(n)
	end
end

function widget:ViewResize(w, h) vsx, vsy = w, h end

-- Default layout (vb_layout.lua): it places the HUD (bottom left corner) and picks the scale that gives it the
-- column width. Dragging the HUD by hand hands the layout back to the player.
WG.VBDashboardHud = {
	Box = function()
		if st.open or not hudRect then return nil end
		return hudRect[1], hudRect[2], hudRect[3] - hudRect[1], hudRect[4] - hudRect[2]
	end,
	Place = function(x, y, w)
		local base = max(0.7, min(1.6, vsy / 1080))                  -- D.S without the player's scale; the HUD is HUD_W wide
		st.scale = max(0.6, min(2.0, w / (HUD_W * base)))
		local h = hudRect and (hudRect[4] - hudRect[2]) or 0
		st.hudX, st.hudTop = x, y + h
	end,
}

function widget:Update(dt)
	refreshTimer = refreshTimer + dt
	if refreshTimer > 4 then refreshTimer = 0; Stats.Refresh() end
	intelTimer = intelTimer + dt
	if intelTimer > 1 then
		intelTimer = 0
		Stats.UpdateIntel(Spring.GetGameFrame())
		counts = { Stats.PlayerCounts() }
		RefreshTeamInfo()
	end
	-- tell the other clients our fps (the engine does not share it); they pick it up in RecvLuaMsg
	fpsTimer = fpsTimer + dt
	if fpsTimer > 3 then
		fpsTimer = 0
		if Spring.SendLuaUIMsg and Spring.GetFPS and not (Spring.IsReplay and Spring.IsReplay()) then
			Spring.SendLuaUIMsg("vbfps:" .. floor(Spring.GetFPS() + 0.5), "all")
		end
	end
end

function widget:RecvLuaMsg(msg, playerID)
	if type(msg) == "string" and msg:sub(1, 6) == "vbfps:" then
		local f = tonumber(msg:sub(7))
		if f and playerID then fpsOf[playerID] = { f, os.clock() } end
	end
end

-- a hidden unit seen dying is forgotten
function widget:UnitDestroyed(unitID) Stats.IntelForget(unitID) end

function widget:GameOver()
	if not st.autoOpened then st.autoOpened = true; st.open = true; st.tab = "report"; st.cursor = nil end
end

function widget:DrawScreen()
	local now = os.clock()
	local dt = min(0.1, now - lastClock)
	lastClock = now
	vsx, vsy = Spring.GetViewGeometry()
	D.S = max(0.7, min(1.6, vsy / 1080)) * st.scale
	local mx, my = Spring.GetMouseState()
	D.BeginFrame(mx, my, vsx, vsy, dt)
	local ctx = BuildCtx()
	if st.open then
		hudRect, menuRect = nil, nil
		DrawDashboard(ctx)
	else
		panelRect = nil
		DrawMenu(ctx)
		if #ctx.all > 0 or not st.hud then DrawHud(ctx) end
	end
	D.EndFrame()
end

function widget:IsAbove(x, y)
	if st.open then return true end
	local function In(r) return r ~= nil and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
	return In(hudRect) or In(menuRect)
end

function widget:GetTooltip(x, y)
	local r = D.Hit(x, y)
	return nil
end

function widget:MousePress(x, y, button)
	if not st.open and not widget:IsAbove(x, y) then return false end
	local r = D.Hit(x, y)
	if not r then return st.open end
	if r.click then r.click(x, y, button) end
	if r.drag then dragging = dragging or {}; dragging.region = r end
	return true
end

function widget:MouseMove(x, y)
	if dragging and dragging.region and dragging.region.drag then dragging.region.drag(x, y)
	elseif dragging and dragging[1] then
		st.hudX, st.hudTop = x - dragging[1], y - dragging[2]
	end
end

function widget:MouseRelease() dragging = nil; return false end

function widget:MouseWheel(up, value)
	if not st.open then return false end
	local order = { 0, 20, 10, 5 }
	local cur = 1
	for k, v in ipairs(order) do if v == st.window then cur = k end end
	cur = up and min(#order, cur + 1) or max(1, cur - 1)
	st.window = order[cur]
	return true
end

local function StepCursor(dir)
	local ref
	for _, t in ipairs(Stats.VisibleTeams()) do ref = ref or t end
	if not ref or ref.n == 0 then return end
	local i = Stats.NearestIndex(ref, st.cursor or Stats.lastFrame)
	i = max(1, min(ref.n, i + dir))
	st.cursor = ref.f[i]
	if i >= ref.n then st.cursor = nil end
end

function widget:KeyPress(key, mods, isRepeat)
	if key == 100 and mods and mods.ctrl and mods.shift and not isRepeat then      -- Ctrl+Shift+D
		if st.open then Close() else Open() end
		return true
	end
	if not st.open then return false end
	if key == 27 then if D.dd then D.dd = nil else Close() end; return true end      -- Esc (an open dropdown first)
	if key >= 49 and key <= 48 + math.min(9, #TABS) then SetTab(TABS[key - 48][1]); return true end
	if key == 276 or key == 1073741904 then StepCursor(-1); return true end          -- left
	if key == 275 or key == 1073741903 then StepCursor(1); return true end           -- right
	if key == 278 or key == 1073741898 then st.cursor = 0; return true end           -- home
	if key == 279 or key == 1073741901 then st.cursor = nil; return true end         -- end
	return false
end

function widget:TextCommand(cmd)
	local word, rest = cmd:match("^(%S+)%s*(.*)$")
	if word ~= "vbdash" then return false end
	local arg, val = rest:match("^(%S*)%s*(.*)$")
	if arg == "" or arg == "toggle" then if st.open then Close() else Open() end
	elseif arg == "open" then Open()
	elseif arg == "close" then Close()
	elseif arg == "hud" then st.hud = not st.hud
	elseif arg == "menu" then st.menu = not st.menu
	elseif arg == "tab" then for _, t in ipairs(TABS) do if t[1] == val:lower() then Open(t[1]) end end
	elseif arg == "scale" then st.scale = max(0.6, min(2.0, tonumber(val) or 1))
	else Spring.Echo("[VB] /vbdash [open|close|hud|tab overview|graphs|economy|combat|army|report|share|settings|scale 1.2]") end
	return true
end

function widget:GetConfigData()
	return { menu = st.menu, hud = st.hud, hudCollapsed = st.hudCollapsed, hudX = st.hudX, hudTop = st.hudTop, scale = st.scale, hudRadar = st.hudRadar, window = st.window }
end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.hud ~= nil then st.hud = d.hud end
	if d.menu ~= nil then st.menu = d.menu end
	if d.hudCollapsed ~= nil then st.hudCollapsed = d.hudCollapsed end
	st.hudX, st.hudTop = d.hudX, d.hudTop
	if d.scale then st.scale = max(0.6, min(2.0, d.scale)) end
	if d.hudRadar then st.hudRadar = d.hudRadar end
	if d.window then st.window = d.window end
end

--------------------------------------------------------------------------------
-- Panel Snap: lets gui_panel_snap.lua dock this panel (drag it near an edge and let go)
--------------------------------------------------------------------------------
local panelSnapSeen
local function PanelSnapRegister()
	local PL = WG.PanelLayout
	if not PL or PL == panelSnapSeen then return end
	panelSnapSeen = PL
	PL.Register("vb_dashboard_hud", {
		dock = "right", order = 10, fixedSize = true,
		getRect = function()
			if not hudRect then return nil end
			return hudRect[1], hudRect[2], hudRect[3] - hudRect[1], hudRect[4] - hudRect[2]
		end,
		setRect = function(x, y, w, h) st.hudX, st.hudTop = x, y + h end,   -- hudX = left, hudTop = top
		isVisible = function() return st.hud and not st.open and hudRect ~= nil end,
	})
end
do
	local prevUpdate = widget.Update
	function widget:Update(...)
		PanelSnapRegister()
		if prevUpdate then return prevUpdate(self, ...) end
	end
	local prevShutdown = widget.Shutdown
	function widget:Shutdown(...)
		if WG.PanelLayout then WG.PanelLayout.Unregister("vb_dashboard_hud") end
		WG.VBDashboardHud = nil
		if prevShutdown then return prevShutdown(self, ...) end
	end
end
