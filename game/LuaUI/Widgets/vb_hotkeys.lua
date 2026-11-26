function widget:GetInfo()
	return { name = "Voidborn Hotkeys", desc = "BAR-style hotkeys: orders (a s m f p g r e t d w), build keys (z x c v b n j u), Ctrl+D = detonate the selected units (five second countdown)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true }
end

-- EDIT HERE -------------------------------------------------------------------
-- order keys: letter -> engine command action
local ORDER_KEYS = {
	a = "attack", s = "stop", m = "move", f = "fight", p = "patrol", g = "guard",
	-- d / q: the flying commander's weapons. The engine gives flying units no "manualfire" command, so
	-- the gadget vb_manualfire.lua adds these two custom ones (d = Devour, q = Destabilisation Gun).
	r = "repair", e = "reclaim", t = "repeat", d = "vbdgun", q = "vbdestab", k = "vbcloak", w = "wait",
}
-- build keys, used when a BUILDER is selected: letter -> customParams.kind of the unit to build
local BUILD_KEYS = {
	z = "mex", x = "solar", c = "fac", v = "radar", b = "store", n = "def1", j = "def2", u = "heart",
}
-- production keys, used when a FACTORY is selected: letter -> kind of unit to queue
local FACTORY_KEYS = {
	z = "con", x = "scout", c = "raider", v = "assault", b = "art", n = "support", j = "heavy",
}
-- -----------------------------------------------------------------------------

-- the dashboard's KEYS page reads these
WG.VBHotkeys = { orders = ORDER_KEYS, build = BUILD_KEYS, factory = FACTORY_KEYS }

local function Describe(tbl) local t = {} for k, v in pairs(tbl) do t[#t + 1] = k:upper() .. "=" .. v end table.sort(t) return table.concat(t, "  ") end

-- Ctrl+D: detonate every selected unit (the LuaRules gadget vb_explode.lua applies the blasts;
-- blast radius is proportional to each unit's health). Also available as the text command /vbexplode.
-- It has to be defined before the functions that call it: a local that is not yet in scope
-- would be looked up as a global at call time and come out nil.
--
-- The detonation is not immediate: the units get five seconds to change their mind.
-- Ctrl+D again while the clock is running cancels it.
local COUNTDOWN = 5          -- seconds between the order and the blast
local pending = nil          -- the moment the countdown was started
local function Explode()
	local sel = Spring.GetSelectedUnits()
	if not sel or #sel == 0 or Spring.GetSpectatingState() then return false end
	local now = Spring.GetLastUpdateSeconds()
	if pending and (now - pending) < COUNTDOWN then
		-- the clock is already running: this press cancels it
		Spring.SendLuaRulesMsg("vbexplode:cancel")
		pending = nil
		Spring.Echo("[VB] Detonation cancelled")
		return true
	end
	for i = 1, #sel, 100 do      -- chunks of 100 ids keep every message small
		Spring.SendLuaRulesMsg("vbexplode:" .. table.concat(sel, ",", i, math.min(i + 99, #sel)))
	end
	pending = now
	Spring.Echo("[VB] Detonation in " .. COUNTDOWN .. " seconds - Ctrl+D again to cancel")
	return true
end

function widget:Initialize()
	Spring.Echo("[VB] Hotkeys loaded. Orders: " .. Describe(ORDER_KEYS))
	Spring.Echo("[VB] Build keys: " .. Describe(BUILD_KEYS) .. "   Factory keys: " .. Describe(FACTORY_KEYS))
end
function widget:TextCommand(cmd)
	if cmd == "vbexplode" then Explode() return true end
	if cmd == "vbcmds" then
		-- diagnostic: the first selected unit's weapons as the engine resolved them, and its commands
		local sel = Spring.GetSelectedUnits()
		local u = sel and sel[1]
		if not u then Spring.Echo("[VB] vbcmds: select a unit first") return true end
		local ud = UnitDefs[Spring.GetUnitDefID(u)]
		Spring.Echo("[VB] unit " .. tostring(ud and ud.name) .. " - weapons as the engine sees them:")
		local n = 0
		for i, w in pairs(ud and ud.weapons or {}) do
			n = n + 1
			local wd = w.weaponDef and WeaponDefs[w.weaponDef]
			Spring.Echo(string.format("  weapon%s -> %s  type=%s  manualFire=%s  paralyzer=%s  range=%s",
				tostring(i), tostring(wd and wd.name), tostring(wd and wd.type), tostring(wd and wd.manualFire),
				tostring(wd and wd.paralyzer), tostring(wd and wd.range)))
		end
		if n == 0 then Spring.Echo("  (no weapons resolved)") end
		local cmds, list = Spring.GetActiveCmdDescs() or {}, {}
		for i = 1, #cmds do
			local c = cmds[i]
			if type(c) == "table" then list[#list + 1] = tostring(c.action) .. "(" .. tostring(c.id) .. ")" end
		end
		Spring.Echo("[VB] commands: " .. table.concat(list, " "))
		return true
	end
	if cmd == "vbkeys" then
		Spring.Echo("Orders: " .. Describe(ORDER_KEYS)); Spring.Echo("Builders: " .. Describe(BUILD_KEYS))
		Spring.Echo("Factories: " .. Describe(FACTORY_KEYS)) return true
	end
end

-- try the action name first, then fall back to the command's index in the active command list
local function Activate(action, matchFn)
	local ok, res = pcall(Spring.SetActiveCommand, action)
	if ok and res ~= false then return true end
	local cmds = Spring.GetActiveCmdDescs() or {}
	for i = 1, #cmds do
		local c = cmds[i]
		if type(c) == "table" and matchFn(c) then
			local ok2 = pcall(Spring.SetActiveCommand, i - 1, 1, true, false, false, false, false, false)
			if ok2 then return true end
		end
	end
	return false
end

-- does this command description belong to that action?  The D-gun is matched by its command id
-- as well, so it is found whatever the engine calls it ("manualfire" or the old "dgun").
local function IsAction(c, action)
	if c.action == action then return true end
	return false
end

local function FindBuild(builderDefID, kind)
	local bd = UnitDefs[builderDefID]
	for _, optID in ipairs(bd and bd.buildOptions or {}) do
		local ud = UnitDefs[optID]
		if ud and ud.customParams and ud.customParams.kind == kind then return optID, ud end
	end
end


-- Tab: select your commander and fly the camera to it (press again to cycle if you own several)
local lastComm = nil
local function JumpToCommander()
	if Spring.GetSpectatingState() then return false end
	local list = {}
	for _, uid in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local cp = UnitDefs[Spring.GetUnitDefID(uid)] and UnitDefs[Spring.GetUnitDefID(uid)].customParams
		if cp and cp.iscommander == "true" and not Spring.GetUnitIsDead(uid) then list[#list + 1] = uid end
	end
	if #list == 0 then return false end
	table.sort(list)
	local pick = list[1]
	if lastComm then
		for i, uid in ipairs(list) do if uid == lastComm then pick = list[i % #list + 1] break end end
	end
	lastComm = pick
	Spring.SelectUnitArray({ pick })
	local x, y, z = Spring.GetUnitPosition(pick)
	if x then Spring.SetCameraTarget(x, y, z, 0.4) end
	return true
end

function widget:KeyPress(key, mods, isRepeat)
	if key == 9 and not (mods and (mods.ctrl or mods.alt or mods.meta or mods.shift)) then   -- 9 = Tab
		if isRepeat then return true end
		return JumpToCommander()
	end
	if mods and mods.ctrl and not mods.alt and not mods.meta and not mods.shift and key == 100 then   -- 100 = 'd'
		if isRepeat then return true end
		return Explode()
	end
	if isRepeat or not key or key < 97 or key > 122 then return false end
	if mods and (mods.ctrl or mods.alt or mods.meta) then return false end
	local ch = string.char(key)
	local sel = Spring.GetSelectedUnits()
	if not sel or #sel == 0 then return false end

	-- build / production keys: use the first selected unit that can build something with that kind
	for _, u in ipairs(sel) do
		local defID = Spring.GetUnitDefID(u)
		local bd = UnitDefs[defID]
		if bd and bd.buildOptions and #bd.buildOptions > 0 then
			local map = bd.isFactory and FACTORY_KEYS or BUILD_KEYS
			local kind = map[ch]
			if kind then
				local optID, ud = FindBuild(defID, kind)
				if optID then
					Activate("buildunit_" .. ud.name, function(c) return c.id == -optID end)
					return true
				end
			end
		end
	end

	local action = ORDER_KEYS[ch]
	if action == "vbcloak" then
		-- K: toggle the cloak of every selected unit that has one (all go the same way, by the first)
		local want, any
		for _, u in ipairs(sel) do
			local i = Spring.FindUnitCmdDesc(u, 35002)
			if i then
				local cd = Spring.GetUnitCmdDescs(u, i, i)
				local cur = cd and cd[1] and cd[1].params and tonumber(cd[1].params[1]) or 0
				if want == nil then want = (cur == 0) and 1 or 0 end
				Spring.GiveOrderToUnit(u, 35002, { want }, {})
				any = true
			end
		end
		if any then return true end
	end
	if action then
		-- only grab the key if some selected unit actually has that command (so e.g. 'r' stays free otherwise)
		local cmds = Spring.GetActiveCmdDescs() or {}
		local has = false
		for i = 1, #cmds do local c = cmds[i]; if type(c) == "table" and IsAction(c, action) then has = true break end end
		if has or action == "stop" or action == "wait" then
			if action == "stop" then Spring.GiveOrder(CMD.STOP, {}, {}) return true end
			if action == "wait" then Spring.GiveOrder(CMD.WAIT, {}, {}) return true end
			return Activate(action, function(c) return IsAction(c, action) end)
		elseif action == "vbdgun" or action == "vbdestab" or action == "vbcloak" then
			Spring.Echo("[VB] " .. ch:upper() .. ": the selection has no " .. action .. " command (is vb_manualfire.lua loaded? is the unit flying with manualFire weapons?)")
		end
	end
	return false
end
