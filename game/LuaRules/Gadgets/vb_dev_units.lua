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
local NUM_KEYS = { "hp", "metal", "energy", "buildtime", "sight", "speed", "range", "dmg", "reload", "alt", "x", "z", "count", "team", "pngsize", "fire", "move", "repeat" }
local STR_KEYS = { "id", "name", "base", "lua", "png", "shape" }

-- the price rules (shared with the forge panel in LuaUI)
local okCost, Cost = pcall(VFS.Include, "LuaRules/Headers/vb_cost.h.lua")
if not okCost or type(Cost) ~= "table" or type(Cost.Cost) ~= "function" then
	Cost = { Cost = function() return nil end, BaseDamage = function() return 0 end,
	         BaseRange = function() return 0 end, Primitives = function() return 0 end, RATE = {} }
end

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
	-- the price: a unit that is stronger than its base unit costs more, and it
	-- takes longer to build.  The rules are in LuaRules/Headers/vb_cost.h.lua, the
	-- same file the forge panel uses to show the price while you design.
	local cost = Cost.Cost(spec, UnitDefs[defID])
	if cost then
		local c = { metalCost = cost.metal, energyCost = cost.energy, buildTime = cost.build }
		if Try({ Spring.SetUnitCosts }, unitID, c) then applied.costs = true else skipped[#skipped + 1] = "costs" end
		if cost.premium > 0 then applied.premium = true end
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
	if spec.shape and spec.shape ~= "" then
		-- custom 3D shape, drawn in the world by LuaUI/Widgets/vb_shape3d.lua
		if spec.shape:find("[^%w%-%.,;:%@]") or #spec.shape > 2000 then
			skipped[#skipped + 1] = "shape (malformed)"
		else
			Spring.SetUnitRulesParam(unitID, "vb_shape", spec.shape, { public = true })
			applied.shape = true
		end
	end
	-- initial stances: fire state, move state and the repeat flag
	local rep = spec["repeat"]
	if spec.fire or spec.move or rep then
		local stances = {}
		if spec.fire then stances[#stances + 1] = { CMD.FIRE_STATE, { Clamp(math.floor(spec.fire), 0, 2) } } end
		if spec.move then stances[#stances + 1] = { CMD.MOVE_STATE, { Clamp(math.floor(spec.move), 0, 1) } } end
		if rep then stances[#stances + 1] = { CMD.REPEAT, { (rep ~= 0) and 1 or 0 } } end
		for _, st in ipairs(stances) do
			if Try({ Spring.GiveOrderToUnit }, unitID, st[1], st[2], 0) then applied.stance = true end
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
	local madeIDs = {}
	for i = 0, count - 1 do
		local gx, gz = i % side, math.floor(i / side)
		local x = Clamp(cx + (gx - (side - 1) / 2) * step, 16, Game.mapSizeX - 16)
		local z = Clamp(cz + (gz - (side - 1) / 2) * step, 16, Game.mapSizeZ - 16)
		local unitID = Spring.CreateUnit(ud.id, x, Spring.GetGroundHeight(x, z), z, 0, teamID)
		if unitID then
			made = made + 1
			madeIDs[#madeIDs + 1] = unitID
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
	-- what the unit costs (the forge shows the same numbers)
	local cost = Cost.Cost(spec, ud)
	if cost then
		msg = msg .. string.format(" | price: %d metal, %d energy, %ds build", cost.metal, cost.energy, cost.build)
	end
	Say(msg)
	return madeIDs
end

-- Entry points for the production queue (vb_dev_queue.lua).  The console (/vbcreate) stays free and cheat-gated,
-- but a unit that the queue already charged for may be created by anyone when the "vb_forge" modoption is on.
GG.VB_DevAllowed = Allowed        -- cheats on, or a single human: may run lua= and use the free console
function GG.VB_ForgeAllowed(playerID)
	if Allowed(playerID) then return true end
	local fo = Spring.GetModOptions().vb_forge
	return fo == nil or fo == "1" or fo == 1 or fo == true
end
function GG.VB_QueueSpawn(t, playerID)
	local spec = {}
	for _, k in ipairs(NUM_KEYS) do if type(t[k]) == "number" then spec[k] = t[k] end end
	for _, k in ipairs(STR_KEYS) do if type(t[k]) == "string" then spec[k] = t[k] end end
	if not Allowed(playerID) then spec.lua = nil end      -- no custom scripts in a real match
	return HandleSpawn(spec, playerID)
end

function gadget:RecvLuaMsg(msg, playerID)
	if type(msg) ~= "string" or msg:sub(1, #PREFIX) ~= PREFIX then return end
	if not Allowed(playerID) then
		Say("dev unit creation needs cheats (/cheat) or a single-player game")
		return true
	end
	-- custom units need a finished tier 2 factory (vb_factory_upgrade.lua); cheats and the modoption lift that
	local teamID = select(4, Spring.GetPlayerInfo(playerID, false))
	if teamID and GG.VB_ForgeUnlocked and not GG.VB_ForgeUnlocked(teamID) then
		Say("custom units need a Tier 2 factory: upgrade your factory first")
		Spring.SendMessageToPlayer(playerID, "[VB] custom units need a Tier 2 factory: upgrade your factory first")
		return true
	end
	local spec, err = ParseSpec(msg:sub(#PREFIX + 1))
	if not spec then Say(err) return true end
	HandleSpawn(spec, playerID)
	return true
end
