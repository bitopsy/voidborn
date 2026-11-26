function widget:GetInfo()
	return { name = "Voidborn Build ETA", desc = "An ETA mm:ss label above every unit or structure of yours (and your allies') that is being built. /vbeta toggles it",
		author = "added for the Voidborn mod", date = "2026", license = "GPL", layer = 9, enabled = true }
end

-- How the time is worked out
--   Every 0.5 s of GAME time the widget looks at the build progress of each unfinished unit and turns the difference into a speed
--   (progress per second).  The speed is smoothed over the last few samples, so it follows what really happens: more builders
--   joining, builders leaving, a metal or energy stall.  ETA = (1 - progress) / speed.
--   While nothing is being added (stalled, paused builders, nobody building it) the label reads --:-- in red.
--   Right after a build starts it also reads --:-- for half a second, until the first sample exists.
--   The game being paused does not disturb it (the clock is the game frame, not the wall clock).

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
local okU, UI = pcall(VFS.Include, "LuaUI/Headers/vb_uiscale.h.lua")
if not okU or type(UI) ~= "table" then UI = { TextBoost = function() return 1 end } end

local FPS = 30
local SAMPLE_FRAMES = 15         -- 0.5 s between two progress samples
local SMOOTH = 0.35              -- weight of the newest speed sample in the running average
local FORGET_FRAMES = 60         -- a unit not seen for 2 s of game time loses its history
local MAX_LABELS = 150           -- never label more than this many units in one frame
local MIN_SPEED = 0.0004         -- progress per second below which a build counts as stalled (it would take 40 min)
local MAX_SECONDS = 99 * 60 + 59

local spGetVisibleUnits  = Spring.GetVisibleUnits
local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local spGetUnitPosition  = Spring.GetUnitPosition
local spGetUnitHeight    = Spring.GetUnitHeight
local spGetUnitTeam      = Spring.GetUnitTeam
local spAreTeamsAllied   = Spring.AreTeamsAllied
local spGetMyTeamID      = Spring.GetMyTeamID
local spGetGameFrame     = Spring.GetGameFrame
local spWorldToScreen    = Spring.WorldToScreenCoords
local spGetSpectatingState = Spring.GetSpectatingState
local floor, max, min = math.floor, math.max, math.min

local enabled = true
local track = {}            -- unitID -> { f = frame of the last sample, p = progress then, v = smoothed speed (progress/s) or nil, seen = frame }
local lastFrame = -1

function widget:GetConfigData() return { enabled = enabled } end
function widget:SetConfigData(d) if d and d.enabled ~= nil then enabled = d.enabled and true or false end end

local function Toggle()
	enabled = not enabled
	Spring.Echo("[VB] build ETA labels: " .. (enabled and "on" or "off") .. "   (/vbeta toggles)")
	return true
end
function widget:Initialize()
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbeta", Toggle, nil, "t") end
end
function widget:Shutdown()
	if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbeta") end
end
function widget:TextCommand(cmd) if cmd == "vbeta" then return Toggle() end end

local function Clock(sec)
	sec = min(MAX_SECONDS, max(0, floor(sec + 0.5)))
	return string.format("%02d:%02d", floor(sec / 60), sec % 60)
end

-- called every game frame the widget draws: updates the speed of one unit and returns its ETA in seconds (nil = unknown / stalled)
local function Eta(uid, progress, frame)
	local t = track[uid]
	if not t or progress < t.p - 0.0001 then                 -- new, or progress went backwards (it was damaged / reset): start over
		t = { f = frame, p = progress, seen = frame }
		track[uid] = t
		return nil
	end
	t.seen = frame
	if frame - t.f >= SAMPLE_FRAMES then
		local v = (progress - t.p) / ((frame - t.f) / FPS)
		t.v = t.v and (t.v * (1 - SMOOTH) + v * SMOOTH) or v
		t.f, t.p = frame, progress
	end
	if not t.v or t.v < MIN_SPEED then return nil end
	return (1 - progress) / t.v
end

function widget:DrawScreen()
	if not enabled then return end
	local frame = spGetGameFrame()
	if frame < lastFrame then track = {} end                 -- a reload went back in time
	lastFrame = frame

	local units = spGetVisibleUnits(-1, nil, false)
	if not units then return end
	local myTeam = spGetMyTeamID()
	local allSeeing = spGetSpectatingState and select(1, spGetSpectatingState())
	local _, vsy = Spring.GetViewGeometry()
	local size = 12 * UI.TextBoost(vsy, WG and WG.VBTextBoostOverride) * max(0.8, min(1.6, (vsy or 1080) / 1080))

	local drawn = 0
	for i = 1, #units do
		local uid = units[i]
		local being, progress = spGetUnitIsBeingBuilt(uid)
		if being and progress then
			local team = spGetUnitTeam(uid)
			if allSeeing or team == myTeam or (team and spAreTeamsAllied(team, myTeam)) then
				local eta = Eta(uid, progress, frame)         -- keeps the history of every visible unfinished unit up to date
				local x, y, z = spGetUnitPosition(uid)
				if x then
					local h = (spGetUnitHeight and spGetUnitHeight(uid)) or 40
					local sx, sy = spWorldToScreen(x, y + h + 12, z)
					if sx and sy then
						drawn = drawn + 1
						if drawn > MAX_LABELS then break end
						local txt = "ETA " .. (eta and Clock(eta) or "--:--")
						local w = VBFont.Width(txt, size)
						local pad = size * 0.4
						local x1, y1 = sx - w / 2 - pad, sy + size * 0.6
						gl.Color(0, 0, 0, 0.62)
						gl.Rect(x1, y1, x1 + w + pad * 2, y1 + size * 1.35)
						if eta then
							VBFont.Text(txt, sx - w / 2, y1 + size * 0.3, size, "o", 0.55, 0.95, 1, 1)
						else
							VBFont.Text(txt, sx - w / 2, y1 + size * 0.3, size, "o", 1, 0.45, 0.35, 1)
						end
					end
				end
			end
		end
	end
	gl.Color(1, 1, 1, 1)

	for uid, t in pairs(track) do                            -- forget units that are finished, dead or out of sight
		if frame - t.seen > FORGET_FRAMES then track[uid] = nil end
	end
end

function widget:UnitDestroyed(uid) track[uid] = nil end
function widget:UnitFinished(uid) track[uid] = nil end
