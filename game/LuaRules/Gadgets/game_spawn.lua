--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    game_spawn.lua
--  brief:   spawns start unit and sets storage levels
--  author:  goddot info@bitopsy.com
--
--  Copyright (C) 2010.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name      = "Spawn",
		desc      = "spawns start unit and sets storage levels",
		author    = "goddot info@bitopsy.com",
		date      = "January, 2010",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- synced only
if (not gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions()

-- 0.16: a human whose side was not set by the lobby or the start script picks a faction in the menu of the widget
-- vb_faction_menu.lua before the game starts.  The widget sends  "vbfaction:<Side>"  (Choir, Maw, Tympan, Miasma, Haptic);
-- the start unit of that side is spawned when the game starts.  A team that did not choose keeps the old default
-- (the sides in turn, by team number); a team whose side IS set cannot change it; nothing is accepted after the start.
local SIDES = VFS.Include("gamedata/sidedata.lua") or {}
local chosen = {}        -- teamID -> startUnit
local started = false

local function FindSide(name)
	name = string.lower(name or "")
	for _, sd in ipairs(SIDES) do
		if string.lower(sd.name or "") == name then return sd end
	end
end

function gadget:RecvLuaMsg(msg, playerID)
	if string.sub(msg, 1, 10) ~= "vbfaction:" then return end
	if started then return true end
	local sd = FindSide(string.sub(msg, 11))
	if not sd then return true end
	local _, _, spec, teamID = Spring.GetPlayerInfo(playerID)
	if spec or not teamID then return true end
	if select(5, Spring.GetTeamInfo(teamID)) ~= "" then return true end     -- the side is already set: not up to the player
	chosen[teamID] = sd.startunit
	return true
end


local function GetStartUnit(teamID)
	-- get the team startup info
	local side = select(5, Spring.GetTeamInfo(teamID))
	local startUnit
	if (side == "") then
		-- startscript didn't specify a side for this team: the menu's choice, else the sides in turn
		if chosen[teamID] then return chosen[teamID] end
		local sidedata = Spring.GetSideData()
		if (sidedata and #sidedata > 0) then
			startUnit = sidedata[1 + teamID % #sidedata].startUnit
		end
	else
		startUnit = Spring.GetSideData(side)
	end
	return startUnit
end

local function SpawnStartUnit(teamID)
	local startUnit = GetStartUnit(teamID)
	if (startUnit and startUnit ~= "") then
		-- spawn the specified start unit
		local x,y,z = Spring.GetTeamStartPosition(teamID)
		-- snap to 16x16 grid
		x, z = 16*math.floor((x+8)/16), 16*math.floor((z+8)/16)
		y = Spring.GetGroundHeight(x, z)
		-- facing toward map center
		local facing=math.abs(Game.mapSizeX/2 - x) > math.abs(Game.mapSizeZ/2 - z)
			and ((x>Game.mapSizeX/2) and "west" or "east")
			or ((z>Game.mapSizeZ/2) and "north" or "south")
		local unitID = Spring.CreateUnit(startUnit, x, y, z, facing, teamID)
	end

	-- set start resources, either from mod options or custom team keys
	local teamOptions = select(8, Spring.GetTeamInfo(teamID))
	local m = teamOptions.startmetal  or modOptions.startmetal  or 1000
	local e = teamOptions.startenergy or modOptions.startenergy or 1000

	-- using SetTeamResource to get rid of any existing resource without affecting stats
	-- using AddTeamResource to add starting resource and counting it as income
	if (m and tonumber(m) ~= 0) then
		-- remove the pre-existing storage
		--   must be done after the start unit is spawned,
		--   otherwise the starting resources are lost!
		Spring.SetTeamResource(teamID, "ms", tonumber(m))
		Spring.SetTeamResource(teamID, "m", 0)
		Spring.AddTeamResource(teamID, "m", tonumber(m))
	end
	if (e and tonumber(e) ~= 0) then
		-- remove the pre-existing storage
		--   must be done after the start unit is spawned,
		--   otherwise the starting resources are lost!
		Spring.SetTeamResource(teamID, "es", tonumber(e))
		Spring.SetTeamResource(teamID, "e", 0)
		Spring.AddTeamResource(teamID, "e", tonumber(e))
	end
end


function gadget:GameStart()
	started = true
	-- only activate if engine didn't already spawn units (compatibility)
	if (#Spring.GetAllUnits() > 0) then
		return
	end

	-- spawn start units
	local gaiaTeamID = Spring.GetGaiaTeamID()
	local teams = Spring.GetTeamList()
	for i = 1,#teams do
		local teamID = teams[i]
		-- don't spawn a start unit for the Gaia team
		if (teamID ~= gaiaTeamID) then
			SpawnStartUnit(teamID)
		end
	end
end
