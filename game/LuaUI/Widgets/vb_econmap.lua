function widget:GetInfo()
	return { name = "Voidborn Econ Map", desc = "Where the metal and the energy are: free / taken metal spots and heat + totals of reclaimable metal and energy (wrecks, rocks, trees, mushrooms) on the ground and on the minimap. Alt+E or /vbeconmap cycles off / metal / energy / both",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 7, enabled = true }
end

-- WHAT IT SHOWS
--   metal spots   a ring on every metal spot of the map:  cyan, pulsing = free ("x1.5" = how rich it is compared
--                 with the typical spot of this map),  green = one of your side's extractors,  red = an enemy extractor.
--                 An enemy extractor you have seen stays marked until you look at the spot again and it is gone.
--   reclaim heat  the map is divided into cells; every cell is tinted by the metal (blue) and energy (amber) that can
--                 still be reclaimed in it, and the richest cells carry a label such as "1.4k M  600 E".
--                 Mushroom patches count by their energy, like everything else that the engine lets you reclaim.
--   The scoreboard at the right edge adds up what is on the map.
--
-- MODES   off | metal (spots + metal) | energy | both        /vbeconmap [off | metal | energy | both | auto]
--   AUTO (on by default): with the overlay off, picking a metal extractor to build shows the spots for as long as the build
--   command is active (next to the engine's metal map from vb_autoshowmetal.lua), and the reclaim command shows
--   everything.  "/vbeconmap auto" turns that on or off.
--
--   Alt+E is bound in vb_hotkeys.lua.   WG.VBEconMap = { Mode(), SetMode(m), Cycle(), Toggle(), FreeSpots(), Spots(), Reclaim() }

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
local okV, V = pcall(VFS.Include, "LuaUI/Headers/vb_values.h.lua")
local broken = not okV or type(V) ~= "table"
if broken then Spring.Echo("[VB] econ map: could not load LuaUI/Headers/vb_values.h.lua: " .. tostring(V)) end

local floor, max, min, sqrt, sin = math.floor, math.max, math.min, math.sqrt, math.sin

local MODES = { "off", "metal", "energy", "both" }
local MODE_TITLE = { metal = "METAL", energy = "ENERGY", both = "METAL + ENERGY" }
local mode, lastOn, auto, tempMode = "off", "both", true, nil

local MC, EC = { 0.55, 0.85, 1.00 }, { 1.00, 0.80, 0.30 }                 -- the colours of the resource bar
local UP, ENEMY = { 0.45, 1.00, 0.55 }, { 1.00, 0.40, 0.35 }
local EPM = 10          -- when weighing heat: 10 energy count as much as 1 metal
local MIN_HEAT = 15     -- cells below this (in metal-equivalent) are not painted
local RCELL = 192       -- elmos: size of a reclaim heat cell
local MCELL = 16        -- elmos: size of a metal-map cell

local mapX, mapZ = Game.mapSizeX or 1, Game.mapSizeZ or 1
local RNX, RNZ = math.ceil(mapX / RCELL), math.ceil(mapZ / RCELL)
local MW, MH = floor(mapX / MCELL), floor(mapZ / MCELL)
local vsx, vsy = Spring.GetViewGeometry()
local clock = 0

local function Sc() return max(0.75, min(1.6, vsy / 1080)) end
local function Eff() if mode ~= "off" then return mode end return auto and tempMode or "off" end

--------------------------------------------------------------------------------
-- metal spots: the metal map is read in slices over several frames at the start, then clustered
--------------------------------------------------------------------------------
local mcells, scanPos, scanDone, spotsOK = {}, 0, false, true
local spots = {}           -- { x, z, sum, rel, r, owner }

local function Cluster()
	local nCells = 0
	for _ in pairs(mcells) do nCells = nCells + 1 end
	if nCells == 0 or nCells > 0.30 * MW * MH then
		spotsOK = false
		Spring.Echo("[VB] econ map: " .. (nCells == 0 and "no metal spots on this map" or "metal is everywhere on this map") .. ", spot rings are off")
		return
	end
	local seen = {}
	for key, v in pairs(mcells) do
		if not seen[key] then
			seen[key] = true
			local stack, sx, sz, sw, cells = { key }, 0, 0, 0, {}
			while #stack > 0 do
				local k = table.remove(stack)
				local cx, cz = (k - 1) % MW, floor((k - 1) / MW)
				local w = mcells[k]
				sx, sz, sw = sx + (cx + 0.5) * MCELL * w, sz + (cz + 0.5) * MCELL * w, sw + w
				cells[#cells + 1] = { cx, cz }
				for dz = -2, 2 do
					for dx = -2, 2 do
						local x, z = cx + dx, cz + dz
						if x >= 0 and z >= 0 and x < MW and z < MH then
							local k2 = z * MW + x + 1
							if mcells[k2] and not seen[k2] then seen[k2] = true; stack[#stack + 1] = k2 end
						end
					end
				end
			end
			local px, pz = sx / sw, sz / sw
			local r = MCELL
			for _, c in ipairs(cells) do
				local d = sqrt(((c[1] + 0.5) * MCELL - px) ^ 2 + ((c[2] + 0.5) * MCELL - pz) ^ 2)
				if d > r then r = d end
			end
			spots[#spots + 1] = { x = px, z = pz, sum = sw, r = r + MCELL * 0.5 }
		end
	end
	local sums = {}
	for i, s in ipairs(spots) do sums[i] = s.sum end
	table.sort(sums)
	local med = sums[floor((#sums + 1) / 2)] or 1
	for _, s in ipairs(spots) do s.rel = s.sum / max(med, 1e-6) end
	Spring.Echo("[VB] econ map: " .. #spots .. " metal spots found")
end

local function ScanMetal()
	local total = MW * MH
	local n = 0
	local get = Spring.GetMetalAmount
	while scanPos < total and n < 6000 do
		local v = get(scanPos % MW, floor(scanPos / MW))
		if v and v > 0 then mcells[scanPos + 1] = v end
		scanPos, n = scanPos + 1, n + 1
	end
	if scanPos >= total then
		scanDone = true
		Cluster()
		mcells = {}
	end
end

-- who holds the spots: checked once a second
local function ScanOwners()
	if not spotsOK or not scanDone or #spots == 0 then return end
	local mexSet = V.IsMex()
	local myA = Spring.GetMyAllyTeamID()
	local _, full = Spring.GetSpectatingState()
	local cur = {}
	local units = Spring.GetAllUnits() or {}
	for i = 1, #units do
		local uid = units[i]
		if mexSet[Spring.GetUnitDefID(uid)] then
			local x, _, z = Spring.GetUnitPosition(uid)
			if x then
				local best, bestD
				for si, s in ipairs(spots) do
					local d = sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
					if d <= s.r + 48 and (not bestD or d < bestD) then best, bestD = si, d end
				end
				if best then
					local mine = Spring.GetUnitAllyTeam(uid) == myA
					if mine or cur[best] ~= "mine" then cur[best] = mine and "mine" or "enemy" end
				end
			end
		end
	end
	for si, s in ipairs(spots) do
		if cur[si] then s.owner = cur[si]
		elseif s.owner == "enemy" and not full and not Spring.IsPosInLos(s.x, Spring.GetGroundHeight(s.x, s.z) or 0, s.z, myA) then
			-- an enemy extractor seen earlier: stays until we look at the spot and it is not there
		else s.owner = nil end
	end
end

--------------------------------------------------------------------------------
-- reclaim heat: features summed per cell, every two seconds
--------------------------------------------------------------------------------
local cells = {}          -- cell -> { m, e, sx, sz, w }
local totM, totE = 0, 0
local heat, labels = {}, {}       -- painted cells { cell, r, g, b, a }, and the richest ones { x, z, m, e }

local function Rebuild()
	heat, labels = {}, {}
	local m = Eff()
	if m == "off" or m == nil then return end
	local list, maxV = {}, 1
	for i, c in pairs(cells) do
		local wm = (m == "energy") and 0 or c.m
		local we = (m == "metal") and 0 or c.e / EPM
		local val = wm + we
		if val >= MIN_HEAT then
			list[#list + 1] = { i = i, c = c, val = val, wm = wm, we = we }
			if val > maxV then maxV = val end
		end
	end
	for _, it in ipairs(list) do
		local mix = it.wm / max(1e-6, it.wm + it.we)
		local r = EC[1] + (MC[1] - EC[1]) * mix
		local g = EC[2] + (MC[2] - EC[2]) * mix
		local b = EC[3] + (MC[3] - EC[3]) * mix
		heat[#heat + 1] = { it.i, r, g, b, 0.10 + 0.50 * sqrt(it.val / maxV) }
	end
	table.sort(list, function(p, q) return p.val > q.val end)
	for k = 1, min(#list, 25) do
		local it = list[k]
		labels[k] = { x = it.c.sx / it.c.w, z = it.c.sz / it.c.w, m = (m ~= "energy") and it.c.m or 0, e = (m ~= "metal") and it.c.e or 0 }
	end
end

local nextReclaim = 0
local function ScanReclaim()
	local fs = Spring.GetAllFeatures() or {}
	local map, tm, te = {}, 0, 0
	local getRes, getPos = Spring.GetFeatureResources, Spring.GetFeaturePosition
	for i = 1, #fs do
		local m, _, e = getRes(fs[i])
		m, e = m or 0, e or 0
		if m + e >= 1 then
			local x, _, z = getPos(fs[i])
			if x then
				local cx, cz = max(0, min(RNX - 1, floor(x / RCELL))), max(0, min(RNZ - 1, floor(z / RCELL)))
				local k = cz * RNX + cx + 1
				local c = map[k]
				if not c then c = { m = 0, e = 0, sx = 0, sz = 0, w = 0 }; map[k] = c end
				local w = m + e / EPM
				c.m, c.e, c.sx, c.sz, c.w = c.m + m, c.e + e, c.sx + x * w, c.sz + z * w, c.w + w
				tm, te = tm + m, te + e
			end
		end
	end
	cells, totM, totE = map, tm, te
	nextReclaim = clock + (#fs > 8000 and 4 or 2)
	Rebuild()
end

--------------------------------------------------------------------------------
-- modes
--------------------------------------------------------------------------------
local function SetMode(m)
	for _, x in ipairs(MODES) do if x == m then mode = m end end
	if mode ~= "off" then lastOn = mode end
	if not broken then Rebuild() end
	Spring.Echo("[VB] econ map: " .. mode)
end
local function Cycle()
	for i, m in ipairs(MODES) do
		if m == mode then SetMode(MODES[i % #MODES + 1]) return end
	end
end
local function Toggle() SetMode(mode == "off" and lastOn or "off") end

function widget:ActiveCommandChanged(cmdID)
	if broken then return end
	local new
	if cmdID and cmdID < 0 and V.IsMex()[-cmdID] then new = "metal"
	elseif cmdID == CMD.RECLAIM then new = "both" end
	if new ~= tempMode then tempMode = new; if mode == "off" then nextReclaim = 0 end end
end

--------------------------------------------------------------------------------
-- callins
--------------------------------------------------------------------------------
local nextOwners = 0

function widget:Initialize()
	if broken then widgetHandler:RemoveWidget(widget) return end
	if not pcall(Spring.GetMetalAmount, 0, 0) then spotsOK, scanDone = false, true end
	WG.VBEconMap = {
		Mode = Eff, SetMode = SetMode, Cycle = Cycle, Toggle = Toggle,
		FreeSpots = function()
			local n = 0
			for _, s in ipairs(spots) do if not s.owner then n = n + 1 end end
			return n, #spots
		end,
		Spots = function() return spots end,
		Reclaim = function() return totM, totE end,
	}
	Spring.Echo("[VB] econ map ready: Alt+E or /vbeconmap cycles off / metal / energy / both")
end

function widget:Shutdown() WG.VBEconMap = nil end
function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:Update(dt)
	if broken then return end
	clock = clock + dt
	if not scanDone and spotsOK then ScanMetal() end
	local m = Eff()
	if m == "off" then return end
	if clock >= nextReclaim then ScanReclaim() end
	if clock >= nextOwners then nextOwners = clock + 1; ScanOwners() end
end

function widget:TextCommand(cmd)
	local word, arg = cmd:match("^(%S+)%s*(%S*)")
	if word ~= "vbeconmap" then return false end
	arg = arg:lower()
	if arg == "" then Cycle()
	elseif arg == "auto" then auto = not auto; Spring.Echo("[VB] econ map: auto " .. (auto and "on" or "off"))
	else SetMode(arg) end
	return true
end

function widget:GetConfigData() return { mode = mode, auto = auto } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.mode then for _, m in ipairs(MODES) do if m == d.mode then mode = m end end end
	if mode ~= "off" then lastOn = mode end
	if d.auto ~= nil then auto = d.auto and true or false end
end

--------------------------------------------------------------------------------
-- drawing: ground
--------------------------------------------------------------------------------
local function SpotColour(s)
	if s.owner == "mine" then return UP[1], UP[2], UP[3], 0.55 end
	if s.owner == "enemy" then return ENEMY[1], ENEMY[2], ENEMY[3], 0.80 end
	return MC[1], MC[2], MC[3], 0.55 + 0.40 * sin(clock * 4)
end

function widget:DrawWorldPreUnit()
	if broken then return end
	local m = Eff()
	if m == "off" then return end
	gl.DepthTest(true)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	if #heat > 0 then
		gl.PolygonOffset(-25, -2)
		for i = 1, #heat do
			local q = heat[i]
			local c = q[1] - 1
			local cx, cz = c % RNX, floor(c / RNX)
			gl.Color(q[2], q[3], q[4], q[5])
			gl.DrawGroundQuad(cx * RCELL, cz * RCELL, min(mapX, (cx + 1) * RCELL), min(mapZ, (cz + 1) * RCELL))
		end
		gl.PolygonOffset(false)
	end
	if (m == "metal" or m == "both") and spotsOK then
		gl.LineWidth(2.5)
		for _, s in ipairs(spots) do
			local r, g, b, a = SpotColour(s)
			gl.Color(r, g, b, a)
			gl.DrawGroundCircle(s.x, Spring.GetGroundHeight(s.x, s.z) or 0, s.z, s.r + 12, 28)
		end
		gl.LineWidth(1)
	end
	gl.DepthTest(false)
	gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- drawing: minimap
--------------------------------------------------------------------------------
function widget:DrawInMiniMap(sx, sy)
	if broken then return end
	local m = Eff()
	if m == "off" then return end
	gl.PushMatrix()
	gl.Translate(0, 1, 0)
	gl.Scale(1 / mapX, -1 / mapZ, 1)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	for i = 1, #heat do
		local q = heat[i]
		local c = q[1] - 1
		local cx, cz = c % RNX, floor(c / RNX)
		gl.Color(q[2], q[3], q[4], min(0.8, q[5] * 1.4))
		gl.Rect(cx * RCELL, cz * RCELL, (cx + 1) * RCELL, (cz + 1) * RCELL)
	end
	if (m == "metal" or m == "both") and spotsOK then
		for _, s in ipairs(spots) do
			local r, g, b, a = SpotColour(s)
			local h = s.owner and 70 or 100
			gl.Color(0, 0, 0, 0.85); gl.Rect(s.x - h - 20, s.z - h - 20, s.x + h + 20, s.z + h + 20)
			gl.Color(r, g, b, 1); gl.Rect(s.x - h, s.z - h, s.x + h, s.z + h)
		end
	end
	gl.PopMatrix()
	gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- drawing: labels and scoreboard
--------------------------------------------------------------------------------
local function Plate(x1, y1, x2, y2)
	gl.Color(0.06, 0.06, 0.09, 0.82); gl.Rect(x1, y1, x2, y2)
	gl.Color(0.85, 0.65, 0.2, 0.9)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end

local function OnScreen(x, z, lift)
	local y = Spring.GetGroundHeight(x, z) or 0
	local px, py, pz = Spring.WorldToScreenCoords(x, y + (lift or 0), z)
	if px and (not pz or pz <= 1) and px > 0 and px < vsx and py > 0 and py < vsy then return px, py end
end

function widget:DrawScreen()
	if broken then return end
	local m = Eff()
	if m == "off" then return end
	local s = Sc()

	-- labels of the richest reclaim cells
	for _, l in ipairs(labels) do
		local px, py = OnScreen(l.x, l.z, 30)
		if px then
			local size = 12 * s
			local parts = {}
			if l.m >= 1 then parts[#parts + 1] = { V.Num(l.m) .. " M", MC } end
			if l.e >= 1 then parts[#parts + 1] = { V.Num(l.e) .. " E", EC } end
			local w = 0
			for _, p in ipairs(parts) do w = w + VBFont.Width(p[1], size) + 6 * s end
			local x = px - w / 2
			for _, p in ipairs(parts) do
				VBFont.Text(p[1], x, py, size, "o", p[2][1], p[2][2], p[2][3], 1)
				x = x + VBFont.Width(p[1], size) + 6 * s
			end
		end
	end
	-- richness of the free spots
	if (m == "metal" or m == "both") and spotsOK then
		for _, sp in ipairs(spots) do
			if not sp.owner then
				local px, py = OnScreen(sp.x, sp.z, 20)
				if px then
					local txt = string.format("x%.1f", sp.rel or 1)
					VBFont.Text(txt, px - VBFont.Width(txt, 11 * s) / 2, py, 11 * s, "o", MC[1], MC[2], MC[3], 1)
				end
			end
		end
	end

	-- scoreboard
	local lines = {}
	local title = (MODE_TITLE[m] or "") .. ((mode == "off") and "  (auto)" or "")
	if (m == "metal" or m == "both") and spotsOK then
		local free, all, mine, enemy = 0, #spots, 0, 0
		for _, sp in ipairs(spots) do
			if not sp.owner then free = free + 1 elseif sp.owner == "mine" then mine = mine + 1 else enemy = enemy + 1 end
		end
		lines[#lines + 1] = { "Metal spots", string.format("%d free of %d", free, all), MC }
		lines[#lines + 1] = { "", string.format("%d yours   %d enemy", mine, enemy), { 0.7, 0.75, 0.85 } }
	end
	if m ~= "energy" then lines[#lines + 1] = { "Reclaim metal", V.Num(totM), MC } end
	if m ~= "metal" then lines[#lines + 1] = { "Reclaim energy", V.Num(totE), EC } end
	local w, rowH, pad = 210 * s, 17 * s, 7 * s
	local h = pad * 2 + rowH * (#lines + 1)
	local x2 = vsx - 8 * s
	local x1 = x2 - w
	local y2 = vsy * 0.64
	Plate(x1, y2 - h, x2, y2)
	local ty = y2 - pad - rowH * 0.8
	VBFont.Text(title, x1 + pad, ty, 12 * s, "o", 1, 0.9, 0.5, 1)
	for _, l in ipairs(lines) do
		ty = ty - rowH
		VBFont.Text(l[1], x1 + pad, ty, 11 * s, "o", 0.8, 0.84, 0.92, 1)
		VBFont.Text(l[2], x2 - pad - VBFont.Width(l[2], 11 * s), ty, 11 * s, "o", l[3][1], l[3][2], l[3][3], 1)
	end
	gl.Color(1, 1, 1, 1)
end
