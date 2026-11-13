function gadget:GetInfo()
	return {
		name = "Voidborn dev units",
		desc = "Open-ended runtime unit creation for the dev console (/vbcreate, /vbspawn)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then return false end

--------------------------------------------------------------------------------
-- What this does (and does not) do
--
-- Spring/Recoil loads every UnitDef when the game starts; new unit TYPES cannot be
-- registered while it runs. So "creating a unit" here means: clone any existing
-- unit def (base=) and override whatever you like on the spawned unit - health,
-- speed, weapon range/damage/reload, costs, sight, name - and optionally run your
-- own Lua on every spawned unit (lua=). The widget (dev_console.lua) remembers
-- these recipes as "templates" so /vbspawn <id> can stamp out more of them.
--
-- Wire format: widget -> SendLuaRulesMsg("vbdev:" .. <lua table literal>)
-- Allowed when cheats are on (/cheat), or when there is only one human player
-- (the shipped Play_*_vs_Bot.txt start scripts), so it is never open in a real match.
--------------------------------------------------------------------------------

local PREFIX = "vbdev:"
local MAX_COUNT = 50
local NUM_KEYS = { "hp", "metal", "energy", "buildtime", "sight", "speed", "range", "dmg", "reload", "alt", "x", "z", "count", "team", "pngsize" }
local STR_KEYS = { "id", "name", "base", "lua", "png" }

local function Say(s) Spring.Echo("[VB dev] " .. s) end

local function Allowed(playerID)
	if Spring.IsCheatingEnabled() then return true end
	local humans = 0
	for _, pid in ipairs(Spring.GetPlayerList()) do
		local _, active, spectator = Spring.GetPlayerInfo(pid, false)
		if active and not spectator then humans = humans + 1 end
	end
	return humans <= 1
end

local function ParseSpec(payload)
	local f = loadstring("return " .. payload)
	if not f then return nil, "malformed request" end
	setfenv(f, {})                       -- data only: no functions reachable from the literal
	local ok, t = pcall(f)
	if not ok or type(t) ~= "table" then return nil, "malformed request" end
	local spec = {}
	for _, k in ipairs(NUM_KEYS) do if type(t[k]) == "number" then spec[k] = t[k] end end
	for _, k in ipairs(STR_KEYS) do if type(t[k]) == "string" then spec[k] = t[k] end end
	return spec
end

local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

-- try several engine setters; the exact API differs a little between Recoil versions
local function Try(fns, ...)
	for i = 1, 6 do                       -- explicit bound: the list may contain nil holes
		local fn = fns[i]
		if type(fn) == "function" then
			local ok = pcall(fn, ...)
			if ok then return true end
		end
	end
	return false
end

local function SetSpeed(unitID, mult)
	local mt = Spring.GetUnitMoveTypeData and Spring.GetUnitMoveTypeData(unitID)
	if not (mt and mt.maxSpeed) then return false end
	local v = mt.maxSpeed * mult              -- scale the live value so units always match the engine's own
	local mc = Spring.MoveCtrl or {}
	local isGround = mt.name == "ground"
	local fns = isGround and { mc.SetGroundMoveTypeData, Spring.SetGroundMoveTypeData, Spring.SetUnitMoveTypeData }
		or { mc.SetAirMoveTypeData, Spring.SetAirMoveTypeData, mc.SetGunshipMoveTypeData, Spring.SetUnitMoveTypeData }
	return Try(fns, unitID, "maxSpeed", v)
end

local function ApplyWeapons(unitID, defID, spec, applied, skipped)
	local ud = UnitDefs[defID]
	local n = ud and ud.weapons and #ud.weapons or 0
	if n == 0 then
		if spec.range or spec.dmg or spec.reload then skipped[#skipped + 1] = "weapons (unit has none)" end
		return
	end
	local maxRange = 0
	for w = 1, n do
		if spec.range then
			local cur = Spring.GetUnitWeaponState(unitID, w, "range")
			if cur and Try({ Spring.SetUnitWeaponState }, unitID, w, "range", cur * spec.range) then cur = cur * spec.range end
			maxRange = math.max(maxRange, cur or 0)
		end
		if spec.reload then
			local cur = Spring.GetUnitWeaponState(unitID, w, "reloadTime")
			if cur then Try({ Spring.SetUnitWeaponState }, unitID, w, "reloadTime", math.max(0.03, cur * spec.reload)) end
		end
		if spec.dmg then
			local cur = Spring.GetUnitWeaponDamages and Spring.GetUnitWeaponDamages(unitID, w, "default")
			if cur then Try({ Spring.SetUnitWeaponDamages }, unitID, w, "default", cur * spec.dmg) end
		end
	end
	if spec.range and maxRange > 0 and Spring.SetUnitMaxRange then pcall(Spring.SetUnitMaxRange, unitID, maxRange) end
	if spec.range then applied.range = true end
	if spec.reload then applied.reload = true end
	if spec.dmg then applied.dmg = true end
end

GG.VB_unitSpec = GG.VB_unitSpec or {}      -- unitID -> spec table (read by vb_experience.lua so split units inherit /vbcreate changes)

local function Customize(unitID, defID, teamID, spec, applied, skipped, luaFn)
	GG.VB_unitSpec[unitID] = spec
	if spec.hp then
		local hp = Clamp(spec.hp, 1, 1e7)
		if Try({ Spring.SetUnitMaxHealth }, unitID, hp) then Try({ Spring.SetUnitHealth }, unitID, hp); applied.hp = true
		else skipped[#skipped + 1] = "hp" end
	end
	if spec.metal or spec.energy or spec.buildtime then
		local c = {}
		if spec.metal then c.metalCost = spec.metal end
		if spec.energy then c.energyCost = spec.energy end
		if spec.buildtime then c.buildTime = spec.buildtime end
		if Try({ Spring.SetUnitCosts }, unitID, c) then applied.costs = true else skipped[#skipped + 1] = "costs" end
	end
	if spec.sight then
		if Try({ Spring.SetUnitSensorRadius }, unitID, "los", spec.sight) then applied.sight = true else skipped[#skipped + 1] = "sight" end
		pcall(Spring.SetUnitSensorRadius, unitID, "airLos", spec.sight)
	end
	if spec.speed then
		if SetSpeed(unitID, Clamp(spec.speed, 0.05, 50)) then applied.speed = true else skipped[#skipped + 1] = "speed" end
	end
	if spec.alt then
		local mc = Spring.MoveCtrl or {}
		if Try({ mc.SetAirMoveTypeData, Spring.SetAirMoveTypeData }, unitID, "wantedHeight", spec.alt) then applied.alt = true
		else skipped[#skipped + 1] = "alt" end
	end
	if spec.range or spec.dmg or spec.reload then ApplyWeapons(unitID, defID, spec, applied, skipped) end
	if spec.name and spec.name ~= "" then
		if Try({ Spring.SetUnitTooltip }, unitID, spec.name) then applied.name = true end
		Spring.SetUnitRulesParam(unitID, "vb_name", spec.name)
	end
	if spec.id then Spring.SetUnitRulesParam(unitID, "vb_template", spec.id) end
	if spec.png and spec.png ~= "" then
		-- image shown above the unit by LuaUI/Widgets/vb_unitpng.lua; only plain relative paths are accepted
		local png = spec.png
		if png:find("..", 1, true) or png:find("^[/\\]") or png:find("[^%w_%-%./ ]") then
			skipped[#skipped + 1] = "png (bad path)"
		else
			Spring.SetUnitRulesParam(unitID, "vb_png", png, { public = true })
			if spec.pngsize then Spring.SetUnitRulesParam(unitID, "vb_pngsize", Clamp(spec.pngsize, 8, 2000), { public = true }) end
			applied.png = true
		end
	end
	if luaFn then
		local env = setmetatable({ unitID = unitID, unitDefID = defID, teamID = teamID, spec = spec }, { __index = _G })
		setfenv(luaFn, env)
		local ok, err = pcall(luaFn)
		if ok then applied.lua = true else skipped[#skipped + 1] = "lua error: " .. tostring(err) end
	end
end

-- re-apply a stored spec to a freshly created unit (used when a unit splits). The lua= snippet is NOT re-run.
function GG.VB_ApplySpec(unitID, spec)
	local defID, teamID = Spring.GetUnitDefID(unitID), Spring.GetUnitTeam(unitID)
	if defID and spec then Customize(unitID, defID, teamID, spec, {}, {}, nil) end
end

function gadget:UnitDestroyed(unitID) GG.VB_unitSpec[unitID] = nil end

local function HandleSpawn(spec, playerID)
	local ud = spec.base and UnitDefNames[spec.base]
	if not ud then
		Say("unknown base unit '" .. tostring(spec.base) .. "'. Use a unit name such as ch_hoplite or mw_leviathan (try /vbbases).")
		return
	end
	local luaFn
	if spec.lua then
		local err
		luaFn, err = loadstring(spec.lua)
		if not luaFn then Say("lua= does not compile: " .. tostring(err)); return end
	end

	local _, _, _, myTeam = Spring.GetPlayerInfo(playerID, false)
	local teamID = spec.team and math.floor(spec.team) or myTeam
	if teamID ~= myTeam and not Spring.IsCheatingEnabled() then
		Say("spawning for another team needs /cheat"); return
	end
	if not teamID or not select(1, Spring.GetTeamInfo(teamID, false)) then
		Say("no such team: " .. tostring(teamID)); return
	end

	local count = Clamp(math.floor(spec.count or 1), 1, MAX_COUNT)
	local cx = Clamp(spec.x or Game.mapSizeX / 2, 16, Game.mapSizeX - 16)
	local cz = Clamp(spec.z or Game.mapSizeZ / 2, 16, Game.mapSizeZ - 16)
	local step = math.max(40, (ud.radius or 20) * 2.2)
	local side = math.ceil(math.sqrt(count))

	local applied, skipped, made = {}, {}, 0
	for i = 0, count - 1 do
		local gx, gz = i % side, math.floor(i / side)
		local x = Clamp(cx + (gx - (side - 1) / 2) * step, 16, Game.mapSizeX - 16)
		local z = Clamp(cz + (gz - (side - 1) / 2) * step, 16, Game.mapSizeZ - 16)
		local unitID = Spring.CreateUnit(ud.id, x, Spring.GetGroundHeight(x, z), z, 0, teamID)
		if unitID then
			made = made + 1
			Customize(unitID, ud.id, teamID, spec, applied, skipped, luaFn)
		end
	end

	local keys = {}
	for k in pairs(applied) do keys[#keys + 1] = k end
	table.sort(keys)
	local label = (spec.id and ("'" .. spec.id .. "' ") or "") .. "(" .. spec.base .. ")"
	local msg = string.format("spawned %d/%d %s for team %d", made, count, label, teamID)
	if #keys > 0 then msg = msg .. " | applied: " .. table.concat(keys, ", ") end
	if #skipped > 0 then msg = msg .. " | NOT applied: " .. table.concat(skipped, "; ") end
	if made < count then msg = msg .. " | (some spawns refused: unit limit or blocked spot)" end
	Say(msg)
end

function gadget:RecvLuaMsg(msg, playerID)
	if type(msg) ~= "string" or msg:sub(1, #PREFIX) ~= PREFIX then return end
	if not Allowed(playerID) then
		Say("dev unit creation needs cheats (/cheat) or a single-player game")
		return true
	end
	local spec, err = ParseSpec(msg:sub(#PREFIX + 1))
	if not spec then Say(err) return true end
	HandleSpawn(spec, playerID)
	return true
end
