function widget:GetInfo()
	return { name = "Voidborn Force Map", desc = "Army value (AV) and defence value (DV) of every side painted on the ground and on the minimap, with a small scoreboard. Alt+F or /vbforcemap cycles off / control / army / defence",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 7, enabled = true }
end

-- WHAT IT SHOWS
--   control  each map cell is tinted in the colour of the side that has the most AV + DV there; the stronger
--            and the more one-sided, the more solid the tint.  This is the "front line" view.
--   army     every side's AV, cell by cell (AV sits where the units stand)
--   defence  every side's DV, cell by cell (a static defence covers every cell inside its weapon range)
--   A square on the minimap and a label on the ground mark the centre of each side's army.
--   The scoreboard at the right edge lists AV and DV per side.  Hold ALT and point at the ground to read the
--   AV / DV of every side at that spot.
--
-- WHAT IT KNOWS (so it is no cheat)
--   A player sees their own side and every unit that is currently identified (line of sight / radar with identification).
--   Enemy static defences stay on the map after you have seen them, until you look at the spot again and they are gone.
--   Spectators and full-view see everything.
--
-- AV / DV follow LuaUI/Headers/vb_values.h.lua, the same rule as the histogram: metal cost x health fraction.
--
--   /vbforcemap [off | control | av | dv]     (no argument: cycle)         Alt+F is bound in vb_hotkeys.lua
--   WG.VBForceMap  = { Mode(), SetMode(m), Cycle(), Toggle(), Totals(), At(x, z) }  for other widgets

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
local okV, V = pcall(VFS.Include, "LuaUI/Headers/vb_values.h.lua")
local broken = not okV or type(V) ~= "table"
if broken then Spring.Echo("[VB] force map: could not load LuaUI/Headers/vb_values.h.lua: " .. tostring(V)) end

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local MODES = { "off", "control", "av", "dv" }
local MODE_TITLE = { control = "FORCE CONTROL", av = "ARMY VALUE", dv = "DEFENCE VALUE" }
local mode, lastOn = "off", "control"

local mapX, mapZ = Game.mapSizeX or 1, Game.mapSizeZ or 1
local CELL = 128 * max(1, math.ceil(max(mapX, mapZ) / (128 * 40)))      -- at most about 40 cells on the long side
local NX, NZ = math.ceil(mapX / CELL), math.ceil(mapZ / CELL)

local vsx, vsy = Spring.GetViewGeometry()
local allies = {}          -- allyTeamID -> { id, name, r, g, b, av = {cell->v}, dv = {cell->v}, avTot, dvTot, cx, cz, avN }
local quads = {}           -- what is painted: { cell, r, g, b, a }
local mem = {}             -- unitID -> remembered enemy static defence { a, x, z, val, range }
local timer, interval, nextScan = 0, 1, 0
local uiClock = 0

local function Sc() return max(0.75, min(1.6, vsy / 1080)) end

--------------------------------------------------------------------------------
-- grid helpers
--------------------------------------------------------------------------------
local function CellIndex(x, z)
	local cx = max(0, min(NX - 1, floor(x / CELL)))
	local cz = max(0, min(NZ - 1, floor(z / CELL)))
	return cz * NX + cx + 1
end

local function Ally(map, a)
	local E = map[a]
	if not E then
		local team = (Spring.GetTeamList(a) or {})[1] or 0
		local r, g, b = Spring.GetTeamColor(team)
		E = { id = a, team = team, r = r or 1, g = g or 1, b = b or 1, av = {}, dv = {}, avTot = 0, dvTot = 0, cx = 0, cz = 0, avN = 0 }
		map[a] = E
	end
	return E
end

local function AddAV(E, x, z, val)
	local i = CellIndex(x, z)
	E.av[i] = (E.av[i] or 0) + val
	E.avTot = E.avTot + val
	E.cx, E.cz, E.avN = E.cx + x * val, E.cz + z * val, E.avN + val
end

-- a static defence covers every cell inside its weapon range, strongest at the foot of the tower
local function AddDV(E, x, z, val, range)
	E.dvTot = E.dvTot + val
	local r = max(range or 0, CELL * 0.5) + CELL * 0.5
	local c0x, c1x = max(0, floor((x - r) / CELL)), min(NX - 1, floor((x + r) / CELL))
	local c0z, c1z = max(0, floor((z - r) / CELL)), min(NZ - 1, floor((z + r) / CELL))
	local dv = E.dv
	for cz = c0z, c1z do
		for cx = c0x, c1x do
			local dx, dz = (cx + 0.5) * CELL - x, (cz + 0.5) * CELL - z
			local d = sqrt(dx * dx + dz * dz)
			if d <= r then
				local i = cz * NX + cx + 1
				dv[i] = (dv[i] or 0) + val * (1 - 0.6 * d / r)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- names
--------------------------------------------------------------------------------
local function AllyName(a, myA)
	if a == myA then return "YOU" end
	for _, t in ipairs(Spring.GetTeamList(a) or {}) do
		local ok, _, leader = pcall(Spring.GetTeamInfo, t)
		if ok and leader and leader >= 0 then
			local ok2, name = pcall(Spring.GetPlayerInfo, leader, false)
			if ok2 and name and name ~= "" then return name end
		end
	end
	return "Side " .. a
end

--------------------------------------------------------------------------------
-- the scan
--------------------------------------------------------------------------------
local function Scan()
	local defs = V.Defs()
	local spGetDefID, spBeingBuilt = Spring.GetUnitDefID, Spring.GetUnitIsBeingBuilt
	local spAlly, spPos, spHealth = Spring.GetUnitAllyTeam, Spring.GetUnitPosition, Spring.GetUnitHealth
	local _, full = Spring.GetSpectatingState()
	local myA = Spring.GetMyAllyTeamID()
	local map, seen = {}, {}
	local units = Spring.GetAllUnits() or {}

	for i = 1, #units do
		local uid = units[i]
		local info = defs[spGetDefID(uid)]
		if info and (info.isArmy or info.isDef) and not spBeingBuilt(uid) then
			local a = spAlly(uid)
			local x, _, z = spPos(uid)
			if a and x then
				local hp, mhp = spHealth(uid)
				local val = info.cost * ((hp and mhp and mhp > 0) and hp / mhp or 1)
				local E = Ally(map, a)
				if info.isArmy then AddAV(E, x, z, val) end
				if info.isDef then
					AddDV(E, x, z, val, info.range)
					if a ~= myA and not full then
						mem[uid] = { a = a, x = x, z = z, val = val, range = info.range }
						seen[uid] = true
					end
				end
			end
		end
	end

	-- enemy defences seen earlier and not in view now stay on the map; one that is in view and not there is gone
	if full then
		mem = {}
	else
		for uid, m in pairs(mem) do
			if not seen[uid] then
				local y = Spring.GetGroundHeight(m.x, m.z) or 0
				if Spring.IsPosInLos(m.x, y, m.z, myA) then
					mem[uid] = nil
				else
					AddDV(Ally(map, m.a), m.x, m.z, m.val, m.range)
				end
			end
		end
	end

	for a, E in pairs(map) do
		E.name = AllyName(a, myA)
		if E.avN > 0 then E.cx, E.cz = E.cx / E.avN, E.cz / E.avN end
	end
	allies = map
	interval = max(0.6, min(2.5, 0.6 + #units / 3000))
end

--------------------------------------------------------------------------------
-- what to paint
--------------------------------------------------------------------------------
local function Rebuild()
	quads = {}
	if mode == "off" then return end
	if mode == "control" then
		local best, bestA, total = {}, {}, {}
		local maxBest = 1
		for a, E in pairs(allies) do
			for _, layer in ipairs({ E.av, E.dv }) do
				for i, v in pairs(layer) do
					total[i] = (total[i] or 0) + v
				end
			end
		end
		for a, E in pairs(allies) do
			local own = {}
			for i, v in pairs(E.av) do own[i] = (own[i] or 0) + v end
			for i, v in pairs(E.dv) do own[i] = (own[i] or 0) + v end
			for i, v in pairs(own) do
				if not best[i] or v > best[i] then best[i], bestA[i] = v, a end
			end
		end
		for _, v in pairs(best) do if v > maxBest then maxBest = v end end
		for i, v in pairs(best) do
			local E = allies[bestA[i]]
			local share = v / max(1, total[i])
			local a = (0.10 + 0.42 * sqrt(v / maxBest)) * (0.45 + 0.55 * share)
			if a > 0.05 then quads[#quads + 1] = { i, E.r, E.g, E.b, a } end
		end
	else
		local key, maxV = mode, 1
		for _, E in pairs(allies) do
			for _, v in pairs(E[key]) do if v > maxV then maxV = v end end
		end
		for _, E in pairs(allies) do
			for i, v in pairs(E[key]) do
				local a = 0.10 + 0.50 * sqrt(v / maxV)
				if a > 0.12 then quads[#quads + 1] = { i, E.r, E.g, E.b, a } end
			end
		end
	end
end

local function SetMode(m)
	for _, x in ipairs(MODES) do if x == m then mode = m end end
	if mode ~= "off" then lastOn = mode end
	if not broken then Rebuild() end
	Spring.Echo("[VB] force map: " .. mode)
end
local function Cycle()
	for i, m in ipairs(MODES) do
		if m == mode then SetMode(MODES[i % #MODES + 1]) return end
	end
end
local function Toggle() SetMode(mode == "off" and lastOn or "off") end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
function widget:Initialize()
	if broken then widgetHandler:RemoveWidget(widget) return end
	WG.VBForceMap = {
		Mode = function() return mode end,
		SetMode = SetMode, Cycle = Cycle, Toggle = Toggle,
		-- list of { ally, name, av, dv, r, g, b } sorted by AV + DV
		Totals = function()
			local t = {}
			for a, E in pairs(allies) do t[#t + 1] = { ally = a, name = E.name, av = E.avTot, dv = E.dvTot, r = E.r, g = E.g, b = E.b } end
			table.sort(t, function(p, q) return p.av + p.dv > q.av + q.dv end)
			return t
		end,
		-- { [allyTeamID] = { av = , dv = } } at a world position
		At = function(x, z)
			local i, t = CellIndex(x, z), {}
			for a, E in pairs(allies) do t[a] = { av = E.av[i] or 0, dv = E.dv[i] or 0 } end
			return t
		end,
	}
	Spring.Echo("[VB] force map ready: Alt+F or /vbforcemap cycles off / control / army / defence")
end

function widget:Shutdown() WG.VBForceMap = nil end
function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:UnitDestroyed(uid) mem[uid] = nil end

function widget:Update(dt)
	if broken then return end
	uiClock = uiClock + dt
	if mode == "off" then return end
	timer = timer + dt
	if timer >= nextScan then
		timer, nextScan = 0, interval
		Scan()
		Rebuild()
	end
end

function widget:TextCommand(cmd)
	local word, arg = cmd:match("^(%S+)%s*(%S*)")
	if word ~= "vbforcemap" then return false end
	if arg == "" then Cycle() else SetMode(arg:lower()) end
	return true
end

function widget:GetConfigData() return { mode = mode } end
function widget:SetConfigData(d)
	if type(d) == "table" and d.mode then for _, m in ipairs(MODES) do if m == d.mode then mode = m end end end
	if mode ~= "off" then lastOn = mode end
end

--------------------------------------------------------------------------------
-- drawing: ground
--------------------------------------------------------------------------------
function widget:DrawWorldPreUnit()
	if broken or mode == "off" or #quads == 0 then return end
	gl.DepthTest(true)
	gl.PolygonOffset(-25, -2)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	for i = 1, #quads do
		local q = quads[i]
		local c = q[1] - 1
		local cx, cz = c % NX, floor(c / NX)
		gl.Color(q[2], q[3], q[4], q[5])
		gl.DrawGroundQuad(cx * CELL, cz * CELL, min(mapX, (cx + 1) * CELL), min(mapZ, (cz + 1) * CELL))
	end
	gl.PolygonOffset(false)
	gl.DepthTest(false)
	gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- drawing: minimap
--------------------------------------------------------------------------------
function widget:DrawInMiniMap(sx, sy)
	if broken or mode == "off" then return end
	gl.PushMatrix()
	gl.Translate(0, 1, 0)
	gl.Scale(1 / mapX, -1 / mapZ, 1)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	for i = 1, #quads do
		local q = quads[i]
		local c = q[1] - 1
		local cx, cz = c % NX, floor(c / NX)
		gl.Color(q[2], q[3], q[4], min(0.8, q[5] * 1.5))
		gl.Rect(cx * CELL, cz * CELL, (cx + 1) * CELL, (cz + 1) * CELL)
	end
	-- the centre of every army
	for _, E in pairs(allies) do
		if E.avN > 0 then
			local r = 90 + 4 * sqrt(E.avTot)
			gl.Color(0, 0, 0, 0.9); gl.Rect(E.cx - r - 25, E.cz - r - 25, E.cx + r + 25, E.cz + r + 25)
			gl.Color(E.r, E.g, E.b, 1); gl.Rect(E.cx - r, E.cz - r, E.cx + r, E.cz + r)
		end
	end
	gl.PopMatrix()
	gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- drawing: army labels, scoreboard, local readout
--------------------------------------------------------------------------------
local function Plate(x1, y1, x2, y2)
	gl.Color(0.06, 0.06, 0.09, 0.82); gl.Rect(x1, y1, x2, y2)
	gl.Color(0.85, 0.65, 0.2, 0.9)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end

local function Trunc(str, size, w)
	while #str > 3 and VBFont.Width(str, size) > w do str = str:sub(1, -2) end
	return str
end

function widget:DrawScreen()
	if broken or mode == "off" then return end
	local s = Sc()

	-- label above the centre of each army
	for _, E in pairs(allies) do
		if E.avN > 0 then
			local y = Spring.GetGroundHeight(E.cx, E.cz) or 0
			local px, py, pz = Spring.WorldToScreenCoords(E.cx, y + 60, E.cz)
			if px and (not pz or pz <= 1) and px > 0 and px < vsx and py > 0 and py < vsy then
				local txt = "AV " .. V.Num(E.avTot)
				local size = 13 * s
				VBFont.Text(txt, px - VBFont.Width(txt, size) / 2, py, size, "o", E.r, E.g, E.b, 1)
			end
		end
	end

	-- scoreboard at the right edge
	local rows = {}
	for _, E in pairs(allies) do rows[#rows + 1] = E end
	table.sort(rows, function(p, q) return p.avTot + p.dvTot > q.avTot + q.dvTot end)
	local n = min(#rows, 8)
	local w, rowH, pad = 210 * s, 17 * s, 7 * s
	local h = pad * 2 + rowH * (n + 2)
	local x2 = vsx - 8 * s
	local x1 = x2 - w
	local y2 = vsy * 0.52
	local y1 = y2 - h
	Plate(x1, y1, x2, y2)
	local ty = y2 - pad - rowH * 0.8
	VBFont.Text(MODE_TITLE[mode] or "", x1 + pad, ty, 12 * s, "o", 1, 0.9, 0.5, 1)
	VBFont.Text("AV", x2 - pad - 62 * s - VBFont.Width("AV", 11 * s), ty, 11 * s, "o", 0.7, 0.75, 0.85, 1)
	VBFont.Text("DV", x2 - pad - VBFont.Width("DV", 11 * s), ty, 11 * s, "o", 0.7, 0.75, 0.85, 1)
	for i = 1, n do
		local E = rows[i]
		ty = ty - rowH
		gl.Color(E.r, E.g, E.b, 1); gl.Rect(x1 + pad, ty + 1 * s, x1 + pad + 9 * s, ty + 10 * s)
		VBFont.Text(Trunc(E.name or "?", 11 * s, 80 * s), x1 + pad + 14 * s, ty, 11 * s, "o", 0.92, 0.94, 1, 1)
		local av, dv = V.Num(E.avTot), V.Num(E.dvTot)
		VBFont.Text(av, x2 - pad - 62 * s - VBFont.Width(av, 11 * s), ty, 11 * s, "o", 1, 1, 1, 1)
		VBFont.Text(dv, x2 - pad - VBFont.Width(dv, 11 * s), ty, 11 * s, "o", 1, 1, 1, 1)
	end
	ty = ty - rowH
	VBFont.Text("hold ALT: values at the cursor", x1 + pad, ty, 9 * s, "o", 0.55, 0.6, 0.7, 1)

	-- local readout under the cursor
	local alt = Spring.GetModKeyState()
	if alt then
		local mx, my = Spring.GetMouseState()
		if not (Spring.IsAboveMiniMap and Spring.IsAboveMiniMap(mx, my)) then
			local kind, pos = Spring.TraceScreenRay(mx, my, true)
			if kind == "ground" and pos then
				local i = CellIndex(pos[1], pos[3])
				local lines = {}
				for _, E in ipairs(rows) do
					local av, dv = E.av[i] or 0, E.dv[i] or 0
					if av > 0 or dv > 0 then lines[#lines + 1] = { E = E, txt = string.format("%s   AV %s   DV %s", Trunc(E.name or "?", 11 * s, 80 * s), V.Num(av), V.Num(dv)) } end
				end
				if #lines > 0 then
					local size, lw = 11 * s, 0
					for _, l in ipairs(lines) do lw = max(lw, VBFont.Width(l.txt, size)) end
					local bx, by = min(mx + 18, vsx - lw - 24 * s), my + 18
					Plate(bx, by, bx + lw + 16 * s, by + #lines * 15 * s + 8 * s)
					for k, l in ipairs(lines) do
						VBFont.Text(l.txt, bx + 8 * s, by + 6 * s + (#lines - k) * 15 * s, size, "o", l.E.r, l.E.g, l.E.b, 1)
					end
				end
			end
		end
	end
	gl.Color(1, 1, 1, 1)
end
