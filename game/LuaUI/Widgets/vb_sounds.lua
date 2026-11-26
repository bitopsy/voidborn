function widget:GetInfo()
	return { name = "Voidborn Sounds", desc = "Game-event sounds and announcements: start, construction, unit ready, commander alarm / lost, cloak, tier 2 / tier 3, low resources, victory / defeat, ambience (/vbsound)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

-- /vbsound                 show settings
-- /vbsound off | on        mute / unmute everything from this widget
-- /vbsound ambient off|on  background drone only
-- /vbsound test <name>     play one sound now, e.g. /vbsound test vox_energy_full  (checks the sound path works)
-- /vbsound debug on|off    echo every announcement to the chat log as it is played
-- /vbsound vol 0-100       master volume of this widget (unit voices/weapons use the engine's own sound sliders)
local vol, ambientOn, enabled = 1.0, true, true
local STREAM, STREAM_VOL = "sounds/ambient_void.ogg", 0.22
local ALARM_COOLDOWN = 12 * 30            -- frames between commander-under-attack alarms
local lastAlarm = -1e9
local streamStarted = false
local nextStreamCheck = 0

local debugOn = false
local function Play(name, v)
	if debugOn then Spring.Echo("[VB sound] play " .. name .. (enabled and "" or "  (muted: /vbsound on)")) end
	if enabled then Spring.PlaySoundFile("sounds/" .. name .. ".wav", (v or 0.8) * vol, "ui") end
end

local function Mine(unitTeam) return unitTeam == Spring.GetMyTeamID() end
local function Mobile(ud) return ud and ud.canMove and (ud.speed or 0) > 0 and not ud.isFactory end

local startPlayed = false
local function StartJingle() if not startPlayed then startPlayed = true; Play("game_start", 0.8) end end
function widget:GameStart() StartJingle() end
function widget:GameFrame(f) if not startPlayed and f >= 1 and f < 300 then StartJingle() end end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	if not Mine(unitTeam) then return end
	local ud = UnitDefs[unitDefID]
	if ud and not Mobile(ud) and select(5, Spring.GetUnitHealth(unitID)) and select(5, Spring.GetUnitHealth(unitID)) < 1 then
		Play("build_start", 0.7)                  -- a structure was just placed (still being built)
	end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if not Mine(unitTeam) then return end
	if Spring.GetGameFrame() < 5 then return end   -- starting units
	local cp = UnitDefs[unitDefID] and UnitDefs[unitDefID].customParams
	if cp and cp.kind == "fac3" then return end -- played by vb_factory_upgrade                     -- the Tier 3 upgrade is done
	if cp and cp.kind == "fac2" then return end -- played by vb_factory_upgrade                      -- the Tier 2 upgrade is done
	if cp and cp.kind == "heavy3" then Play("vox_t3_unit_ready", 1.0) return end                 -- a Tier 3 heavy is ready
	Play(Mobile(UnitDefs[unitDefID]) and "unit_ready" or "struct_done", 0.75)
end

-- ---------------------------------------------------------------------------------------------
-- announcements
local lastLost, lastCloak = -1e9, -1e9
local lastEnergy, lastMetal, nextResCheck = -1e9, -1e9, 0
local RES_COOLDOWN = 25 * 30                 -- frames between two low-resource warnings of one kind

local function IsCommander(unitDefID)
	local cp = UnitDefs[unitDefID] and UnitDefs[unitDefID].customParams
	return cp and cp.iscommander == "true"
end

local function Spectating() return select(1, Spring.GetSpectatingState()) end

-- cloak on / off for my own units (commanders and constructors can cloak)
function widget:UnitCloaked(unitID, unitDefID, unitTeam)
	if not Mine(unitTeam) then return end
	local f = Spring.GetGameFrame()
	if f - lastCloak > 20 then lastCloak = f; Play("cloak_on", 0.6) end
end
function widget:UnitDecloaked(unitID, unitDefID, unitTeam)
	if not Mine(unitTeam) then return end
	local f = Spring.GetGameFrame()
	if f - lastCloak > 20 then lastCloak = f; Play("cloak_off", 0.6) end
end

-- my commander died / an enemy commander died
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if not IsCommander(unitDefID) or Spectating() then return end
	if Mine(unitTeam) then
		lastLost = Spring.GetGameFrame(); Play("commander_lost", 1.0)
	elseif not Spring.AreTeamsAllied(unitTeam, Spring.GetMyTeamID()) then
		Play("enemy_commander_down", 0.9)
	end
end

-- the game is over: fanfare or dirge (no dirge on top of the bell toll of a commander that has just died)
function widget:GameOver(winners)
	if Spectating() then return end
	local mine, won = Spring.GetMyAllyTeamID(), false
	for _, a in ipairs(winners or {}) do if a == mine then won = true end end
	if won then Play("victory", 1.0)
	elseif Spring.GetGameFrame() - lastLost > 10 * 30 then Play("defeat", 1.0) end
end

-- energy / metal: stall (storage nearly empty while spending more than coming in) and full (storage topped up)
--   Each kind is "armed" again once the level has moved away (above 10% after a stall, below 90% after a full), so it is
--   said once per event and not over and over, and not at the start when the storage begins full.
local resState = {
	energy = { stallArmed = true, fullArmed = false, fullTicks = 0, lastStall = -1e9, lastFull = -1e9 },
	metal  = { stallArmed = true, fullArmed = false, fullTicks = 0, lastStall = -1e9, lastFull = -1e9 },
}
local FULL_TICKS = 3                           -- checks (1 per second) that the storage must stay full
local function CheckKind(kind, team, f)
	local cur, stor, pull, income = Spring.GetTeamResources(team, kind)
	local st = resState[kind]
	if not (cur and stor and stor > 0) then return end
	local frac = cur / stor
	if frac > 0.10 then st.stallArmed = true end
	if frac < 0.90 then st.fullArmed = true; st.fullTicks = 0 end
	if frac < 0.03 and st.stallArmed and (pull or 0) > (income or 0) and f - st.lastStall > RES_COOLDOWN then
		st.stallArmed, st.lastStall = false, f
		Play(kind .. "_low", 1.0)                 -- sounds/energy_low.wav, sounds/metal_low.wav
	elseif frac >= 0.99 then
		st.fullTicks = st.fullTicks + 1
		if st.fullArmed and st.fullTicks >= FULL_TICKS and f - st.lastFull > 2 * RES_COOLDOWN then
			st.fullArmed, st.lastFull = false, f
			Play("vox_" .. kind .. "_full", 1.0)
		end
	end
end

-- labs: "queue empty" when a lab runs out of queued units, "factory idle" when one has stood idle for a while
local labState = {}                            -- labID -> { had = bool, idleSince = frame, told = bool }
local lastQueueMsg, lastIdleMsg = -1e9, -1e9
local IDLE_AFTER, IDLE_COOLDOWN = 40 * 30, 90 * 30
local function CheckLabs(team, f)
	local busy = {}
	for entry in (Spring.GetTeamRulesParam(team, "vbq") or ""):gmatch("[^;]+") do
		local line = tonumber(entry:match("|(%d+)$"))
		if line and line > 0 then busy[line] = true end
	end
	local seen = {}
	for _, uid in ipairs(Spring.GetTeamUnits(team) or {}) do
		local cp = UnitDefs[Spring.GetUnitDefID(uid)] and UnitDefs[Spring.GetUnitDefID(uid)].customParams
		local kind = cp and cp.kind
		if (kind == "fac" or kind == "fac2" or kind == "fac3") and not Spring.GetUnitIsBeingBuilt(uid) then
			seen[uid] = true
			local ls = labState[uid]
			if not ls then ls = { used = false, idleSince = f, told = false }; labState[uid] = ls end
			if busy[uid] then
				ls.used, ls.idleSince, ls.told = true, f, false
			elseif ls.used then
				if not ls.wasEmpty then   -- the line has just run dry
					ls.wasEmpty, ls.idleSince = true, f
					if f - lastQueueMsg > 20 * 30 then lastQueueMsg = f; Play("vox_queue_empty", 1.0) end
				elseif not ls.told and f - ls.idleSince > IDLE_AFTER and f - lastIdleMsg > IDLE_COOLDOWN then
					ls.told, lastIdleMsg = true, f
					Play("vox_factory_idle", 1.0)
				end
			end
			if busy[uid] then ls.wasEmpty = false end
		end
	end
	for uid in pairs(labState) do if not seen[uid] then labState[uid] = nil end end
end

local function CheckResources()
	local f = Spring.GetGameFrame()
	if f < 900 or f < nextResCheck or Spectating() then return end
	nextResCheck = f + 30
	local team = Spring.GetMyTeamID()
	CheckKind("energy", team, f)
	CheckKind("metal", team, f)
	CheckLabs(team, f)
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage)
	if not Mine(unitTeam) or damage <= 0 then return end
	local ud = UnitDefs[unitDefID]
	local cp = ud and ud.customParams
	if cp and cp.iscommander == "true" then
		local f = Spring.GetGameFrame()
		if f - lastAlarm > ALARM_COOLDOWN then lastAlarm = f; Play("alarm_commander", 0.9) end
	end
end

-- ambience: PlaySoundStream does not loop on its own, so start it again when it finishes
function widget:Update()
	if enabled then CheckResources() end
	if not (enabled and ambientOn) then return end
	local now = Spring.GetTimer and Spring.GetTimer()
	local t = Spring.DiffTimers and now and Spring.DiffTimers(now, widget.t0 or now) or 0
	widget.t0 = widget.t0 or now
	if t < nextStreamCheck then return end
	nextStreamCheck = t + 2
	local playing = false
	if Spring.GetSoundStreamTime then
		local ok, pos, len = pcall(Spring.GetSoundStreamTime)
		playing = ok and (len or 0) > 0 and (pos or 0) < (len or 0) - 0.1
	end
	if not playing and VFS.FileExists(STREAM) then pcall(Spring.PlaySoundStream, STREAM, STREAM_VOL * vol) end
end

local function Say(s) Spring.Echo("[VB sound] " .. s) end

function widget:GetConfigData() return { vol = vol, ambientOn = ambientOn, enabled = enabled } end
function widget:SetConfigData(d)
	if type(d) ~= "table" then return end
	if type(d.vol) == "number" then vol = math.max(0, math.min(1, d.vol)) end
	if d.ambientOn ~= nil then ambientOn = d.ambientOn end
	if d.enabled ~= nil then enabled = d.enabled end
end

local function Cmd(_, extra, args)
	local a, b = args and args[1], args and args[2]
	if a == "off" then enabled = false; pcall(Spring.StopSoundStream); Say("off")
	elseif a == "on" then enabled = true; Say("on")
	elseif a == "debug" and (b == "on" or b == "off") then debugOn = b == "on"; Say("debug " .. b)
	elseif a == "test" and b then
		local was = enabled; enabled = true; Play(b, 1.0); enabled = was
		Say("test " .. b .. (VFS.FileExists("sounds/" .. b .. ".wav") and "" or "  - NO SUCH FILE sounds/" .. b .. ".wav"))
	elseif a == "ambient" and (b == "off" or b == "on") then
		ambientOn = b == "on"; if not ambientOn then pcall(Spring.StopSoundStream) end; Say("ambient " .. b)
	elseif a == "vol" and tonumber(b) then vol = math.max(0, math.min(100, tonumber(b))) / 100; Say("volume " .. math.floor(vol * 100))
	else Say(string.format("%s, volume %d, ambient %s   (/vbsound on|off | vol 0-100 | ambient on|off)", enabled and "on" or "off", vol * 100, ambientOn and "on" or "off")) end
	return true
end

function widget:Initialize()
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbsound", Cmd, nil, "t") end
end
function widget:Shutdown()
	if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbsound") end
	pcall(Spring.StopSoundStream)
end
function widget:TextCommand(cmd)
	local name, rest = cmd:match("^(%S+)%s*(.*)$")
	if name == "vbsound" then
		local args = {}; for w in rest:gmatch("%S+") do args[#args + 1] = w end
		return Cmd(nil, rest, args)
	end
end
