function widget:GetInfo()
	return {
		name    = "Idle Bots & Commander",
		desc    = "Lists ONLY idle commanders, constructors and labs at the bottom center. Left click: select/jump to next. Right click: select all of that type.",
		author  = "goddot",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 0,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local LABEL_TEXT      = "Unemployed"  -- try "Idle" or "Re-employment queue"
local SHOW_COMMANDER  = true
local SHOW_CONSTRUCTORS = true
local SHOW_LABS       = true
local ONLY_BOTS       = false   -- true: only kbot-type constructors / labs
local UPDATE_INTERVAL = 0.25    -- seconds between scans
local ICON_SIZE       = 44      -- px at 1080p, scaled with resolution
local ICON_SPACING    = 6
local BOTTOM_OFFSET   = 8
local BG_ALPHA        = 0.55

--------------------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------------------
local spGetMyTeamID         = Spring.GetMyTeamID
local spGetTeamUnits        = Spring.GetTeamUnits
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitCommands     = Spring.GetUnitCommands
local spGetFactoryCommands  = Spring.GetFactoryCommands
local spGetUnitIsBuilding   = Spring.GetUnitIsBuilding
local spGetUnitIsDead       = Spring.GetUnitIsDead
local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetSpectatingState  = Spring.GetSpectatingState
local spGetViewGeometry     = Spring.GetViewGeometry
local spSelectUnitArray     = Spring.SelectUnitArray
local spSetCameraTarget     = Spring.SetCameraTarget

local glColor   = gl.Color
local glRect    = gl.Rect
local glTexture = gl.Texture
local glTexRect = gl.TexRect
local glText    = gl.Text

local vsx, vsy = spGetViewGeometry()
local scale = vsy / 1080

local timer = 0
local entries = {}
local panel = nil

-- unitDefID -> "com" | "con" | "lab"
local defKind = {}

local function isKbot(ud)
	return ud.moveDef and ud.moveDef.family == "kbot"
end

local DEBUG = true  -- prints the list of unit types the widget will track to the infolog

local function isMobile(ud)
	return (ud.moveDef ~= nil or ud.canFly) and (ud.speed or ud.maxVelocity or 0) > 0
end

-- ipairs on purpose: UnitDefs is indexed by both id and name, we only want ids
for defID, ud in ipairs(UnitDefs) do
	local cp = ud.customParams or {}
	local hasBuildOptions = ud.buildOptions ~= nil and #ud.buildOptions > 0
	local isExtractor = (ud.extractsMetal or 0) > 0 or cp.metal_extractor ~= nil

	if isExtractor then
		-- metal extractors, never tracked
	elseif cp.iscommander then
		if SHOW_COMMANDER and isMobile(ud) then defKind[defID] = "com" end
	elseif ud.isFactory and hasBuildOptions and (ud.buildSpeed or 0) > 0 and not isMobile(ud) then
		-- real labs: static factories only
		if SHOW_LABS and (not ONLY_BOTS or isKbot(ud) or (ud.name or ""):find("lab")) then
			defKind[defID] = "lab"
		end
	elseif isMobile(ud) and hasBuildOptions and (ud.buildSpeed or 0) > 0 and not ud.isFactory and not ud.isBuilding then
		-- mobile constructors only (no nano turrets, rez bots, mexes, etc.)
		if SHOW_CONSTRUCTORS and (not ONLY_BOTS or isKbot(ud)) then
			defKind[defID] = "con"
		end
	end
end

if DEBUG then
	local names = {}
	for defID, kind in pairs(defKind) do
		names[#names + 1] = kind .. ":" .. UnitDefs[defID].name
	end
	table.sort(names)
	Spring.Echo("[Idle Bots & Commander] tracking " .. #names .. " unit types: " .. table.concat(names, ", "))
end

local KIND_ORDER = { com = 1, con = 2, lab = 3 }
local KIND_COLOR = {
	com = { 1.0, 0.85, 0.2, 0.95 },   -- gold
	con = { 0.4, 0.9, 1.0, 0.80 },    -- cyan
	lab = { 1.0, 0.55, 0.2, 0.85 },   -- orange
}

--------------------------------------------------------------------------------
-- Idle detection
--------------------------------------------------------------------------------
local function count(c)
	if type(c) == "table" then return #c end
	return c or 0
end

local function isIdle(unitID, kind)
	if spGetUnitIsDead(unitID) then return false end
	if spGetUnitIsBeingBuilt(unitID) then return false end
	if spGetUnitIsBuilding(unitID) then return false end
	if kind == "lab" then
		return count(spGetFactoryCommands(unitID, 0)) == 0
	end
	return count(spGetUnitCommands(unitID, 0)) == 0
end

local function scan()
	local groups, order = {}, {}

	for _, unitID in ipairs(spGetTeamUnits(spGetMyTeamID())) do
		local defID = spGetUnitDefID(unitID)
		local kind = defID and defKind[defID]
		if kind and isIdle(unitID, kind) then
			if not groups[defID] then
				groups[defID] = {}
				order[#order + 1] = defID
			end
			local g = groups[defID]
			g[#g + 1] = unitID
		end
	end

	table.sort(order, function(a, b)
		local ka, kb = KIND_ORDER[defKind[a]], KIND_ORDER[defKind[b]]
		if ka ~= kb then return ka < kb end
		return a < b
	end)

	local oldCycle = {}
	for _, e in ipairs(entries) do oldCycle[e.defID] = e.cycle end

	local new = {}
	for _, defID in ipairs(order) do
		new[#new + 1] = {
			defID = defID, kind = defKind[defID],
			units = groups[defID], cycle = oldCycle[defID] or 0,
		}
	end
	entries = new
end

--------------------------------------------------------------------------------
-- Callins
--------------------------------------------------------------------------------
function widget:Initialize()
	if spGetSpectatingState() then
		widgetHandler:RemoveWidget()
		return
	end
	scan()
end

function widget:PlayerChanged()
	if spGetSpectatingState() then widgetHandler:RemoveWidget() end
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	scale = vsy / 1080
end

function widget:Update(dt)
	timer = timer + dt
	if timer >= UPDATE_INTERVAL then
		timer = 0
		scan()
	end
end

local function layout()
	panel = nil
	local n = #entries
	if n == 0 then return end
	local size = ICON_SIZE * scale
	local gap = ICON_SPACING * scale
	local pad = 5 * scale
	local total = n * size + (n - 1) * gap
	local x = vsx / 2 - total / 2
	local y = BOTTOM_OFFSET * scale + pad
	for _, e in ipairs(entries) do
		e.x1, e.y1, e.x2, e.y2 = x, y, x + size, y + size
		x = x + size + gap
	end
	panel = {
		x1 = entries[1].x1 - pad, y1 = y - pad,
		x2 = entries[n].x2 + pad, y2 = y + size + pad,
	}
end

local function frame(x1, y1, x2, y2, w)
	gl.LineWidth(w)
	gl.Shape(GL.LINE_LOOP, {
		{ v = { x1, y1 } }, { v = { x2, y1 } },
		{ v = { x2, y2 } }, { v = { x1, y2 } },
	})
end

function widget:DrawScreen()
	layout()
	if not panel then return end

	-- panel background + thin frame
	glColor(0, 0, 0, BG_ALPHA)
	glRect(panel.x1, panel.y1, panel.x2, panel.y2)
	glColor(1, 1, 1, 0.25)
	frame(panel.x1, panel.y1, panel.x2, panel.y2, 1)

	-- small label tab above the panel
	local fontSize = 12 * scale
	local labelH = fontSize + 6 * scale
	local labelW = gl.GetTextWidth(LABEL_TEXT) * fontSize + 14 * scale
	local lx1 = (panel.x1 + panel.x2) / 2 - labelW / 2
	local lx2 = lx1 + labelW
	local ly1 = panel.y2
	local ly2 = ly1 + labelH
	glColor(0, 0, 0, BG_ALPHA + 0.1)
	glRect(lx1, ly1, lx2, ly2)
	glColor(1, 1, 1, 0.25)
	frame(lx1, ly1, lx2, ly2, 1)
	glColor(1, 1, 1, 0.85)
	glText(LABEL_TEXT, (lx1 + lx2) / 2, ly1 + 4 * scale, fontSize, "co")

	-- icons
	for _, e in ipairs(entries) do
		glColor(1, 1, 1, 1)
		glTexture("#" .. e.defID)
		glTexRect(e.x1, e.y1, e.x2, e.y2)
		glTexture(false)

		local c = KIND_COLOR[e.kind]
		glColor(c[1], c[2], c[3], c[4])
		frame(e.x1, e.y1, e.x2, e.y2, 1.5)

		if #e.units > 1 then
			glColor(1, 1, 1, 1)
			glText(tostring(#e.units), e.x2 - 3 * scale, e.y1 + 3 * scale, 15 * scale, "ro")
		end
	end
	glColor(1, 1, 1, 1)
end

local function inRect(e, x, y)
	return e.x1 and x >= e.x1 and x <= e.x2 and y >= e.y1 and y <= e.y2
end

function widget:IsAbove(x, y)
	for _, e in ipairs(entries) do
		if inRect(e, x, y) then return true end
	end
	return false
end

function widget:MousePress(x, y, button)
	for _, e in ipairs(entries) do
		if inRect(e, x, y) then
			if button == 1 then
				e.cycle = (e.cycle % #e.units) + 1
				local unitID = e.units[e.cycle]
				spSelectUnitArray({ unitID })
				local ux, uy, uz = spGetUnitPosition(unitID)
				if ux then spSetCameraTarget(ux, uy, uz, 0.4) end
			elseif button == 3 then
				spSelectUnitArray(e.units)
				local ux, uy, uz = spGetUnitPosition(e.units[1])
				if ux then spSetCameraTarget(ux, uy, uz, 0.4) end
			else
				return false
			end
			return true
		end
	end
	return false
end
