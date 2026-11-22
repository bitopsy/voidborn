function widget:GetInfo()
	return { name = "Voidborn Sensor Ranges", desc = "Draws the line-of-sight (green), radar (blue) and weapon (red) range circles of selected units and of the structure you are about to place, and keeps a faint radar ring on every radar of your side at all times. /vbranges cycles selected / all / off",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

-- WHAT IS DRAWN
--   line of sight  green, of the selected units (mode "all": of all your units)
--   radar          blue, same rule as the line of sight
--   weapons        red: the range of every weapon of the selected units (equal ranges are drawn once, at most three
--                  circles per unit); a weapon that is fired by hand (D-gun and the like) is purple.  Mode "all" draws the
--                  weapons of your static defences only: the circles of a whole army would hide the map.
--   radar, always  a thin, faint blue ring around every finished radar of your ally team, selected or not, in every mode
--                  (also when the mode is "off").  A radar that is switched off has no radius and no ring.
--   placing        the ranges of the structure you are about to place, at the mouse
--
-- COMMANDS
--   /vbranges                     cycle selected / all / off   (line of sight, radar and weapons of the circles above)
--   /vbranges weapons [on|off]    the red weapon circles
--   /vbranges los [on|off]        the green line-of-sight circles
--   /vbranges radar [on|off]      the always-on radar rings
--   With on/off left out a layer is switched the other way.

local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetTeamUnits     = Spring.GetTeamUnits
local spGetMyTeamID      = Spring.GetMyTeamID
local spGetMyAllyTeamID  = Spring.GetMyAllyTeamID
local spGetUnitDefID     = Spring.GetUnitDefID
local spGetUnitPosition  = Spring.GetUnitPosition
local spGetUnitAllyTeam  = Spring.GetUnitAllyTeam
local spGetSensorRadius  = Spring.GetUnitSensorRadius
local spGetWeaponState   = Spring.GetUnitWeaponState
local spGetIsBeingBuilt  = Spring.GetUnitIsBeingBuilt
local spGetActiveCommand = Spring.GetActiveCommand
local spGetMouseState    = Spring.GetMouseState
local spTraceScreenRay   = Spring.TraceScreenRay

local MODES = { "selected", "all", "off" }
local mode = "selected"
local showLos, showWeapons, showRadar = true, true, true
local MAX_UNITS = 300            -- never draw circles for more units than this in one frame
local MAX_WEAPON_UNITS = 120     -- ... and weapon circles for no more than this many
local MAX_RADARS = 80
local MAX_WEAPON_CIRCLES = 3     -- per unit
local RES = 72                   -- segments per circle

-- colours: line of sight green, radar blue, weapons red, hand-fired weapons purple
local LOS_COLOR    = { 0.30, 1.00, 0.45, 0.70 }
local RADAR_COLOR  = { 0.35, 0.65, 1.00, 0.80 }
local WEAPON_COLOR = { 1.00, 0.40, 0.30, 0.75 }
local MANUAL_COLOR = { 0.85, 0.40, 1.00, 0.70 }
local RADAR_ALWAYS = { 0.35, 0.65, 1.00, 0.30 }

function widget:GetConfigData() return { mode = mode, los = showLos, weapons = showWeapons, radar = showRadar } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if d.mode then for _, m in ipairs(MODES) do if m == d.mode then mode = m end end end
	if d.los ~= nil then showLos = d.los and true or false end
	if d.weapons ~= nil then showWeapons = d.weapons and true or false end
	if d.radar ~= nil then showRadar = d.radar and true or false end
end

local function Flip(cur, arg)
	if arg == "on" then return true elseif arg == "off" then return false end
	return not cur
end

local function Onoff(b) return b and "on" or "off" end

local function Status()
	Spring.Echo(string.format("[VB] sensor ranges: %s   line of sight %s, weapons %s, radar rings %s   (green = line of sight, blue = radar, red = weapons, purple = hand-fired; /vbranges [weapons|los|radar] [on|off])",
		mode, Onoff(showLos), Onoff(showWeapons), Onoff(showRadar)))
end

-- args = the words after the command
local function Handle(args)
	local a, b = args and args[1], args and args[2]
	if a == nil then
		for i, m in ipairs(MODES) do
			if m == mode then mode = MODES[i % #MODES + 1]; break end
		end
	elseif a == "weapons" or a == "weapon" then showWeapons = Flip(showWeapons, b)
	elseif a == "los" or a == "sight" then showLos = Flip(showLos, b)
	elseif a == "radar" then showRadar = Flip(showRadar, b)
	elseif a == "selected" or a == "all" or a == "off" then mode = a
	end
	Status()
	return true
end

local function Cmd(_, _, args) return Handle(args) end

function widget:TextCommand(cmd)
	local name, rest = cmd:match("^(%S+)%s*(.*)$")
	if name == "vbranges" then
		local args = {}; for w in rest:gmatch("%S+") do args[#args + 1] = w end
		return Handle(args)
	end
end

-- ---------------------------------------------------------------------------------------------
-- always-on radar rings: the radars of my ally team are collected through the unit callins,
-- so the draw call does not have to look at every unit of the game.
local radars = {}                -- unitID -> true
local function Spectating() return select(1, Spring.GetSpectatingState()) end

local function Consider(unitID, unitDefID)
	local ud = UnitDefs[unitDefID or -1]
	if not ud or not ((ud.radarRadius or 0) > 0) then return end
	if spGetIsBeingBuilt then
		local building = spGetIsBeingBuilt(unitID)
		if building then return end
	end
	if spGetUnitAllyTeam(unitID) == spGetMyAllyTeamID() then radars[unitID] = true end
end

local function Rescan()
	radars = {}
	if Spectating() then return end            -- a spectator sees no ally team: the rings are for players
	for _, teamID in ipairs(Spring.GetTeamList(spGetMyAllyTeamID()) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do Consider(unitID, spGetUnitDefID(unitID)) end
	end
end

function widget:UnitFinished(unitID, unitDefID) Consider(unitID, unitDefID) end
function widget:UnitDestroyed(unitID) radars[unitID] = nil end
function widget:UnitGiven(unitID, unitDefID) Consider(unitID, unitDefID) end
function widget:UnitTaken(unitID) radars[unitID] = nil; end
function widget:PlayerChanged() Rescan() end

function widget:Initialize()
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbranges", Cmd, nil, "t") end
	Rescan()
end
function widget:Shutdown() if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbranges") end end

-- ---------------------------------------------------------------------------------------------
-- radii
-- the LIVE radius of a unit (so forge designs with extra sight, and radars that are switched off, are right);
-- falls back to the unit def when the engine call is not there
local function Radius(unitID, ud, kind)
	if spGetSensorRadius then
		local ok, r = pcall(spGetSensorRadius, unitID, kind)
		if ok and r then return r end
	end
	if kind == "los" then return ud and ud.losRadius or 0 end
	return ud and ud.radarRadius or 0
end

-- the weapons of a unit def, read once: { { index, range, manual }, ... }  (shields and the like have no range to show)
local defWeapons = {}
local function DefWeapons(unitDefID)
	local list = defWeapons[unitDefID]
	if list then return list end
	list = {}
	local ud = UnitDefs[unitDefID]
	for i, w in ipairs(ud and ud.weapons or {}) do
		local wd = w.weaponDef and WeaponDefs[w.weaponDef]
		if wd and (wd.range or 0) > 10 and wd.type ~= "Shield" then
			list[#list + 1] = { i, wd.range, wd.manualFire and true or false }
		end
	end
	defWeapons[unitDefID] = list
	return list
end

-- up to MAX_WEAPON_CIRCLES distinct ranges, longest first; a live unit reports its own range (upgrades, veterancy)
local function WeaponRanges(unitDefID, unitID)
	local found, out = {}, {}
	for _, w in ipairs(DefWeapons(unitDefID)) do
		local r = w[2]
		if unitID and spGetWeaponState then
			local ok, live = pcall(spGetWeaponState, unitID, w[1], "range")
			if ok and live and live > 10 then r = live end
		end
		local key = math.floor(r + 0.5)
		local prev = found[key]
		if not prev then
			prev = { r = r, manual = w[3] }; found[key] = prev; out[#out + 1] = prev
		elseif prev.manual and not w[3] then
			prev.manual = false                -- an automatic weapon with the same range wins the colour
		end
	end
	table.sort(out, function(a, b) return a.r > b.r end)
	while #out > MAX_WEAPON_CIRCLES do out[#out] = nil end
	return out
end

local function IsStaticDefence(ud)
	return ud and (ud.isBuilding or not ud.canMove) and #(ud.weapons or {}) > 0
end

-- ---------------------------------------------------------------------------------------------
-- drawing
local FADE_SELECTED = 0.5      -- circles are half as opaque while any unit is selected
local fade = 1

local function Circle(x, y, z, r, col, width, alpha)
	if not r or r <= 1 then return end
	gl.LineWidth(width); gl.Color(col[1], col[2], col[3], col[4] * (alpha or fade))
	gl.DrawGroundCircle(x, y, z, r, RES)
end

local drawn = {}
local ringed = {}              -- radars that already got their full circle this frame
local function DrawUnit(unitID, weapons)
	local x, y, z = spGetUnitPosition(unitID)
	if not x then return end
	local unitDefID = spGetUnitDefID(unitID)
	local ud = UnitDefs[unitDefID or -1]
	if not ud then return end
	local building = spGetIsBeingBuilt and spGetIsBeingBuilt(unitID)
	local los = showLos and Radius(unitID, ud, "los") or 0
	local radar = 0
	if not building then radar = Radius(unitID, ud, "radar") end
	local wr = (weapons and showWeapons and not building) and WeaponRanges(unitDefID, unitID) or nil
	if wr and #wr == 0 then wr = nil end
	if los <= 1 and radar <= 1 and not wr then return end
	-- units standing on the same spot with the same ranges (a stack of builders) would draw the same circle again
	local key = math.floor(x / 8) .. ":" .. math.floor(z / 8) .. ":" .. math.floor(los) .. ":" .. math.floor(radar)
	if wr then for _, w in ipairs(wr) do key = key .. ":" .. math.floor(w.r) end end
	if drawn[key] then return end
	drawn[key] = true
	if radar > 1 then ringed[unitID] = true end
	Circle(x, y, z, los, LOS_COLOR, 2)
	Circle(x, y, z, radar, RADAR_COLOR, 3)
	if wr then
		for _, w in ipairs(wr) do Circle(x, y, z, w.r, w.manual and MANUAL_COLOR or WEAPON_COLOR, 2) end
	end
end

local function DrawRadarRings()
	local n = 0
	for unitID in pairs(radars) do
		n = n + 1
		if n > MAX_RADARS then break end
		if not ringed[unitID] then
			local x, y, z = spGetUnitPosition(unitID)
			if x then
				local r = Radius(unitID, UnitDefs[spGetUnitDefID(unitID) or -1], "radar")   -- 0 while switched off
				Circle(x, y, z, r, RADAR_ALWAYS, 1, 1)
			else
				radars[unitID] = nil
			end
		end
	end
end

function widget:DrawWorld()
	gl.DepthTest(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	drawn, ringed = {}, {}

	local sel = spGetSelectedUnits()
	if mode ~= "off" then
		fade = (sel and #sel > 0) and FADE_SELECTED or 1
		if mode == "all" then
			local list = spGetTeamUnits(spGetMyTeamID())
			if list then
				local weaponUnits = 0
				for i = 1, math.min(#list, MAX_UNITS) do
					local id = list[i]
					local ud = UnitDefs[spGetUnitDefID(id) or -1]
					local w = false
					if showWeapons and weaponUnits < MAX_WEAPON_UNITS and IsStaticDefence(ud) then w = true; weaponUnits = weaponUnits + 1 end
					DrawUnit(id, w)
				end
			end
		elseif sel then
			for i = 1, math.min(#sel, MAX_UNITS) do DrawUnit(sel[i], i <= MAX_WEAPON_UNITS) end
		end

		-- the structure being placed: its ranges at the mouse position
		local _, cmdID = spGetActiveCommand()
		if cmdID and cmdID < 0 then
			local ud = UnitDefs[-cmdID]
			if ud then
				local mx, my = spGetMouseState()
				local what, pos = spTraceScreenRay(mx, my, true)
				if what == "ground" and pos then
					fade = 1
					if showLos then Circle(pos[1], pos[2], pos[3], ud.losRadius or 0, LOS_COLOR, 2) end
					Circle(pos[1], pos[2], pos[3], ud.radarRadius or 0, RADAR_COLOR, 3)
					if showWeapons then
						for _, w in ipairs(WeaponRanges(-cmdID, nil)) do
							Circle(pos[1], pos[2], pos[3], w.r, w.manual and MANUAL_COLOR or WEAPON_COLOR, 2)
						end
					end
				end
			end
		end
	end

	-- the faint radar rings: every mode, selected or not
	if showRadar then DrawRadarRings() end

	gl.LineWidth(1); gl.Color(1, 1, 1, 1)
end
