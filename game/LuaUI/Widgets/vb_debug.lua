-- Developer tool: only loaded when the "Developer tools" game option (vb_dev, see modoptions.lua) is on, or the dashboard button "DEV MODE" was pressed.
if (Spring.GetModOptions() or {}).vb_dev ~= "1" and not (WG and WG.VBDevMode) then return false end   -- game option, or the DEV MODE button of the dashboard

function widget:GetInfo()
	return { name = "VB Debug", desc = "/vbdbg dumps the selected unit's weapon and attack state", layer = 0, enabled = true }
end

-- call a Spring function safely; returns its results as a string ("n/a" if the function does not exist in this engine)
local function try(fn, ...)
	if type(fn) ~= "function" then return "n/a" end
	local res = { pcall(fn, ...) }
	if not res[1] then return "err" end
	local out = {}
	for i = 2, #res do out[#out + 1] = tostring(res[i]) end
	return table.concat(out, ",")
end

function widget:TextCommand(cmd)
	if cmd ~= "vbdbg" then return end
	local sel = Spring.GetSelectedUnits()
	if #sel == 0 then Spring.Echo("[vbdbg] nothing selected") return end

	for _, uid in ipairs(sel) do
		local ud = UnitDefs[Spring.GetUnitDefID(uid)]
		local st = Spring.GetUnitStates(uid)
		Spring.Echo("== " .. ud.name .. " id=" .. uid)
		if type(st) == "table" then
			Spring.Echo("  firestate=" .. tostring(st.firestate) .. " movestate=" .. tostring(st.movestate))
		end
		Spring.Echo("  cloaked=" .. tostring(Spring.GetUnitIsCloaked(uid)) ..
			" stunned=" .. tostring(Spring.GetUnitIsStunned(uid)))

		for i = 1, #(ud.weapons or {}) do
			local wd = WeaponDefs[ud.weapons[i].weaponDef]
			Spring.Echo(string.format("  w%d %s range=%s reloadState=%s",
				i, tostring(wd and wd.name),
				tostring(Spring.GetUnitWeaponState(uid, i, "range")),
				tostring(Spring.GetUnitWeaponState(uid, i, "reloadState"))))
		end

		local cmds = Spring.GetUnitCommands(uid, 5) or {}
		Spring.Echo("  queued commands: " .. #cmds)
		for _, c in ipairs(cmds) do
			Spring.Echo("   cmd id=" .. tostring(c.id) .. " params=" .. table.concat(c.params or {}, ","))
		end

		-- if the first command is an attack on a unit, ask the engine why weapon 1 will not fire at it
		local c = cmds[1]
		if c and c.id == CMD.ATTACK and c.params and #c.params == 1 then
			local t = c.params[1]
			local tdef = Spring.GetUnitDefID(t)
			local x, y, z = Spring.GetUnitPosition(uid)
			local tx, ty, tz = Spring.GetUnitPosition(t)
			if tx then
				local d = math.sqrt((x - tx) ^ 2 + (y - ty) ^ 2 + (z - tz) ^ 2)
				Spring.Echo(string.format("  target id=%d %s dist=%.0f", t, tdef and UnitDefs[tdef].name or "?", d))
			end
			Spring.Echo("  w1 canFire=" .. try(Spring.GetUnitWeaponCanFire, uid, 1) ..
				" testTarget=" .. try(Spring.GetUnitWeaponTestTarget, uid, 1, t) ..
				" testRange=" .. try(Spring.GetUnitWeaponTestRange, uid, 1, t) ..
				" freeLOF=" .. try(Spring.GetUnitWeaponHaveFreeLineOfFire, uid, 1, t))
			Spring.Echo("  w1 engine target (type,isUser,target)=" .. try(Spring.GetUnitWeaponTarget, uid, 1))
		end
	end
end
