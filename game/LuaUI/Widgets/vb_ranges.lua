function widget:GetInfo()
	return { name = "Voidborn Sensor Ranges", desc = "Draws the line-of-sight (green) and radar (blue) range circles of selected units, and of the structure you are about to place. /vbranges cycles selected / all / off",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetTeamUnits     = Spring.GetTeamUnits
local spGetMyTeamID      = Spring.GetMyTeamID
local spGetUnitDefID     = Spring.GetUnitDefID
local spGetUnitPosition  = Spring.GetUnitPosition
local spGetSensorRadius  = Spring.GetUnitSensorRadius
local spGetIsBeingBuilt  = Spring.GetUnitIsBeingBuilt
local spGetActiveCommand = Spring.GetActiveCommand
local spGetMouseState    = Spring.GetMouseState
local spTraceScreenRay   = Spring.TraceScreenRay

local MODES = { "selected", "all", "off" }
local mode = "selected"
local MAX_UNITS = 300            -- never draw circles for more units than this in one frame
local RES = 72                   -- segments per circle

-- colours: line of sight green, radar blue
local LOS_COLOR   = { 0.30, 1.00, 0.45, 0.70 }
local RADAR_COLOR = { 0.35, 0.65, 1.00, 0.80 }

function widget:GetConfigData() return { mode = mode } end
function widget:SetConfigData(d) if d and d.mode then for _, m in ipairs(MODES) do if m == d.mode then mode = m end end end end

local function Cycle()
	for i, m in ipairs(MODES) do
		if m == mode then mode = MODES[i % #MODES + 1]; break end
	end
	Spring.Echo("[VB] sensor ranges: " .. mode .. "   (green = line of sight, blue = radar; /vbranges changes it)")
	return true
end
function widget:Initialize()
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbranges", Cycle, nil, "t") end
end
function widget:Shutdown() if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbranges") end end
function widget:TextCommand(cmd) if cmd == "vbranges" then return Cycle() end end

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

local FADE_SELECTED = 0.5      -- circles are half as opaque while any unit is selected
local fade = 1

local function Circle(x, y, z, r, col, width)
	if not r or r <= 1 then return end
	gl.LineWidth(width); gl.Color(col[1], col[2], col[3], col[4] * fade)
	gl.DrawGroundCircle(x, y, z, r, RES)
end

local drawn = {}
local function DrawUnit(unitID)
	local x, y, z = spGetUnitPosition(unitID)
	if not x then return end
	local ud = UnitDefs[spGetUnitDefID(unitID) or -1]
	if not ud then return end
	local los = Radius(unitID, ud, "los")
	local radar = 0
	if not (spGetIsBeingBuilt and spGetIsBeingBuilt(unitID)) then radar = Radius(unitID, ud, "radar") end
	if los <= 1 and radar <= 1 then return end
	-- units standing on the same spot with the same ranges (a stack of builders) would draw the same circle again
	local key = math.floor(x / 8) .. ":" .. math.floor(z / 8) .. ":" .. math.floor(los) .. ":" .. math.floor(radar)
	if drawn[key] then return end
	drawn[key] = true
	Circle(x, y, z, los, LOS_COLOR, 2)
	Circle(x, y, z, radar, RADAR_COLOR, 3)
end

function widget:DrawWorld()
	if mode == "off" then return end
	gl.DepthTest(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	drawn = {}
	local sel = spGetSelectedUnits()
	fade = (sel and #sel > 0) and FADE_SELECTED or 1
	local list
	if mode == "all" then list = spGetTeamUnits(spGetMyTeamID()) else list = sel end
	if list then
		for i = 1, math.min(#list, MAX_UNITS) do DrawUnit(list[i]) end
	end
	-- the structure being placed: its ranges at the mouse position
	local _, cmdID = spGetActiveCommand()
	if cmdID and cmdID < 0 and mode ~= "off" then
		local ud = UnitDefs[-cmdID]
		if ud then
			local mx, my = spGetMouseState()
			local what, pos = spTraceScreenRay(mx, my, true)
			if what == "ground" and pos then
				Circle(pos[1], pos[2], pos[3], ud.losRadius or 0, LOS_COLOR, 2)
				Circle(pos[1], pos[2], pos[3], ud.radarRadius or 0, RADAR_COLOR, 3)
			end
		end
	end
	gl.LineWidth(1); gl.Color(1, 1, 1, 1)
end
