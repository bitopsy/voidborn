function widget:GetInfo()
	return { name = "Voidborn Upgrade Bars", desc = "Progress bar above a factory that is being upgraded to Tier 2 or Tier 3",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 9, enabled = true }
end

-- The gadget vb_factory_upgrade.lua publishes the upgrades of a team as the team rules param "vbu_list":
--     "<unitID>:<progress 0..1000>:<b|s>;..."      b = paying and building, s = stalled (not enough metal / energy)
-- This widget draws one bar above each of them (allied teams too).

local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

local list = {}          -- { unitID, progress 0..1, stalled }
local nextPoll = 0

local function Poll()
	list = {}
	local myAllyTeam = Spring.GetMyAllyTeamID()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, _, _, allyTeam = Spring.GetTeamInfo(teamID, false)
		if allyTeam == myAllyTeam or Spring.GetSpectatingState() then
			local s = Spring.GetTeamRulesParam(teamID, "vbu_list")
			if type(s) == "string" and s ~= "" then
				for uid, prog, st in s:gmatch("(%d+):(%d+):(%a)") do
					list[#list + 1] = { tonumber(uid), (tonumber(prog) or 0) / 1000, st == "s" }
				end
			end
		end
	end
end

function widget:Update()
	local now = Spring.GetTimer()
	if not widget.t0 then widget.t0 = now end
	local t = Spring.DiffTimers(now, widget.t0)
	if t >= nextPoll then nextPoll = t + 0.2; Poll() end
end

function widget:DrawScreen()
	for _, e in ipairs(list) do
		local uid = e[1]
		if Spring.ValidUnitID(uid) and Spring.IsUnitVisible(uid, nil, true) then
			local x, y, z = Spring.GetUnitPosition(uid)
			local h = (Spring.GetUnitHeight and Spring.GetUnitHeight(uid)) or 60
			local sx, sy = Spring.WorldToScreenCoords(x, y + h + 24, z)
			if sx and sy then
				local w, hh = 96, 9
				local x1, y1 = sx - w / 2, sy
				gl.Color(0, 0, 0, 0.75); gl.Rect(x1 - 2, y1 - 2, x1 + w + 2, y1 + hh + 2)
				if e[3] then gl.Color(1.0, 0.4, 0.25, 0.95) else gl.Color(0.95, 0.75, 0.2, 0.95) end
				gl.Rect(x1, y1, x1 + w * e[2], y1 + hh)
				-- the tier being built comes from the factory's own def (customParams.upgrade_tier, 2 when absent)
				local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
				local tier = tonumber(ud and ud.customParams and ud.customParams.upgrade_tier) or 2
				local label = e[3] and ("T" .. tier .. " UPGRADE - STALLED") or string.format("T%d UPGRADE %d%%", tier, math.floor(e[2] * 100 + 0.5))
				VBFont.Text(label, sx - VBFont.Width(label, 10) / 2, y1 + hh + 5, 10, "o", 1, 0.92, 0.65, 1)
			end
		end
	end
end
