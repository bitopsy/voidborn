function widget:GetInfo()
	return { name = "Voidborn Commander Names", desc = "Writes the player's name above every commander you can see (/vbnames toggles it)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true }
end

--[[
  A commander is any unit whose unitdef has customParams.iscommander == "true" (same test as vb_hotkeys / vb_sounds).
  The name is the name of the team's leader player; for an AI team it is the AI's name.
  A commander is labelled when it is in the camera's view and either in our line of sight / radar or we are a
  spectator with full view.  The label takes the team colour and scales a little with the camera distance.
]]

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then VBFont = nil end

local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitHeight     = Spring.GetUnitHeight
local spGetUnitTeam       = Spring.GetUnitTeam
local spGetUnitDefID      = Spring.GetUnitDefID
local spIsUnitVisible     = Spring.IsUnitVisible
local spGetUnitLosState   = Spring.GetUnitLosState
local spWorldToScreen     = Spring.WorldToScreenCoords
local spGetTeamColor      = Spring.GetTeamColor
local spGetCameraPosition = Spring.GetCameraPosition
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyAllyTeamID   = Spring.GetMyAllyTeamID
local spIsGUIHidden       = Spring.IsGUIHidden

local enabled = true
local commanders = {}              -- [unitID] = true
local nameOf = {}                  -- [teamID] = name
local nameTimer = 0
local vsx, vsy = Spring.GetViewGeometry()

local function IsCommanderDef(defID)
	local ud = defID and UnitDefs[defID]
	local cp = ud and ud.customParams
	return cp and cp.iscommander == "true" or false
end

local function TeamName(teamID)
	local _, leader, _, isAI = Spring.GetTeamInfo(teamID, false)
	if isAI then
		local ok, _, aiName, _, shortName = pcall(Spring.GetAIInfo, teamID)
		local n = ok and ((aiName and aiName ~= "" and aiName) or shortName)
		return (n and n ~= "") and n or "AI"
	end
	local pid = leader
	if not pid or pid < 0 then
		for _, p in ipairs(Spring.GetPlayerList(teamID, true) or {}) do pid = p; break end
	end
	if pid and pid >= 0 then
		local name = Spring.GetPlayerInfo(pid, false)
		if name and name ~= "" then return name end
	end
	return "team " .. teamID
end

local function RefreshNames()
	local out = {}
	for uid in pairs(commanders) do
		local t = spGetUnitTeam(uid)
		if t and not out[t] then out[t] = TeamName(t) end
	end
	nameOf = out
end

local function Track(uid, defID)
	if IsCommanderDef(defID or spGetUnitDefID(uid)) then commanders[uid] = true end
end

-- a commander we are allowed to see (own side, full-view spectator, or in our line of sight / radar)
local function Seen(uid)
	local _, fullView = spGetSpectatingState()
	if fullView then return true end
	local los = spGetUnitLosState(uid, spGetMyAllyTeamID(), false)
	return los and (los.los or los.radar) and true or false
end

-- the dashboard's click-to-jump asks for a team's commander through this
local function FindCommander(teamID)
	for uid in pairs(commanders) do
		if spGetUnitTeam(uid) == teamID and not Spring.GetUnitIsDead(uid) and Seen(uid) then return uid end
	end
end

function widget:Initialize()
	WG.VBCommanders = { Find = FindCommander }
	for _, uid in ipairs(Spring.GetAllUnits()) do Track(uid) end
	RefreshNames()
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbnames", function()
		enabled = not enabled
		Spring.Echo("[VB] commander names: " .. (enabled and "on" or "off"))
		return true
	end, nil, "t") end
end

function widget:TextCommand(cmd)
	if cmd == "vbnames" then
		enabled = not enabled
		Spring.Echo("[VB] commander names: " .. (enabled and "on" or "off"))
		return true
	end
end

function widget:Shutdown() WG.VBCommanders = nil end

function widget:GetConfigData() return { enabled = enabled } end
function widget:SetConfigData(d) if d and d.enabled ~= nil then enabled = d.enabled and true or false end end

function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:UnitCreated(uid, defID) Track(uid, defID) end
function widget:UnitFinished(uid, defID) Track(uid, defID) end
function widget:UnitGiven(uid, defID) Track(uid, defID); nameTimer = 99 end
function widget:UnitTaken(uid) nameTimer = 99 end
function widget:UnitEnteredLos(uid) Track(uid) end
function widget:UnitDestroyed(uid) commanders[uid] = nil end

function widget:Update(dt)
	nameTimer = nameTimer + dt
	if nameTimer > 2 then nameTimer = 0; RefreshNames() end
end

function widget:DrawScreen()
	if not enabled or spIsGUIHidden() or not next(commanders) then return end
	local _, fullView = spGetSpectatingState()
	local myAlly = spGetMyAllyTeamID()
	local cx, cy, cz = spGetCameraPosition()
	for uid in pairs(commanders) do
		local team = spGetUnitTeam(uid)
		if team and spIsUnitVisible(uid, nil, false) then
			local seen = fullView
			if not seen then
				local los = spGetUnitLosState(uid, myAlly, false)
				seen = los and (los.los or los.radar) or false
			end
			if seen then
				local x, y, z = spGetUnitPosition(uid)
				if x then
					local h = spGetUnitHeight(uid) or 30
					local sx, sy = spWorldToScreen(x, y + h + 24, z)
					if sx and sx > -200 and sx < vsx + 200 and sy and sy > -50 and sy < vsy + 50 then
						local dx, dy, dz = x - cx, y - cy, z - cz
						local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
						local size = math.max(11, math.min(22, 22 * (1400 / math.max(dist, 1))))
						local r, g, b = spGetTeamColor(team)
						local name = nameOf[team] or ("team " .. team)
						if VBFont then
							VBFont.Text(name, sx, sy, size, "oc", r or 1, g or 1, b or 1, 1)
						else
							gl.Color(r or 1, g or 1, b or 1, 1)
							gl.Text(name, sx, sy, size, "oc")
						end
					end
				end
			end
		end
	end
end
