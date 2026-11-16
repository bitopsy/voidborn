function widget:GetInfo()
	return { name = "Voidborn Hotkeys", desc = "BAR-style hotkeys: orders (a s m f p g r e t d w), build keys (z x c v b n j u), Ctrl+B = detonate selected units",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true }
end

-- EDIT HERE -------------------------------------------------------------------
-- order keys: letter -> engine command action
local ORDER_KEYS = {
	a = "attack", s = "stop", m = "move", f = "fight", p = "patrol", g = "guard",
	r = "repair", e = "reclaim", t = "resurrect", d = "dgun", w = "wait", y = "capture",
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

-- Ctrl+B: detonate every selected unit (the LuaRules gadget vb_explode.lua applies the blasts;
-- blast radius is proportional to each unit's health). Also available as the text command /vbexplode.
-- It has to be defined before the functions that call it: a local that is not yet in scope
-- would be looked up as a global at call time and come out nil.
local function Explode()
	local sel = Spring.GetSelectedUnits()
	if not sel or #sel == 0 or Spring.GetSpectatingState() then return false end
	for i = 1, #sel, 100 do      -- chunks of 100 ids keep every message small
		Spring.SendLuaRulesMsg("vbexplode:" .. table.concat(sel, ",", i, math.min(i + 99, #sel)))
	end
	Spring.Echo("[VB] Detonating " .. #sel .. " unit(s)")
	return true
end

function widget:Initialize()
	Spring.Echo("[VB] Hotkeys loaded. Orders: " .. Describe(ORDER_KEYS))
	Spring.Echo("[VB] Build keys: " .. Describe(BUILD_KEYS) .. "   Factory keys: " .. Describe(FACTORY_KEYS))
end
function widget:TextCommand(cmd)
	if cmd == "vbexplode" then Explode() return true end
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

local function FindBuild(builderDefID, kind)
	local bd = UnitDefs[builderDefID]
	for _, optID in ipairs(bd and bd.buildOptions or {}) do
		local ud = UnitDefs[optID]
		if ud and ud.customParams and ud.customParams.kind == kind then return optID, ud end
	end
end


function widget:KeyPress(key, mods, isRepeat)
	if mods and mods.ctrl and not mods.alt and not mods.meta and not mods.shift and key == 98 then   -- 98 = 'b'
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
	if action then
		-- only grab the key if some selected unit actually has that command (so e.g. 'r' stays free otherwise)
		local cmds = Spring.GetActiveCmdDescs() or {}
		local has = false
		for i = 1, #cmds do local c = cmds[i]; if type(c) == "table" and c.action == action then has = true break end end
		if has or action == "stop" or action == "wait" then
			if action == "stop" then Spring.GiveOrder(CMD.STOP, {}, {}) return true end
			if action == "wait" then Spring.GiveOrder(CMD.WAIT, {}, {}) return true end
			return Activate(action, function(c) return c.action == action end)
		end
	end
	return false
end
