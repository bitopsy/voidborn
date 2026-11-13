# VOIDBORN PROGRAMMABLE RTS ARCHITECTURE
*Spring/Recoil Engine Technical Specification & Implementation Plan*

---

## Architecture Overview

To transform **VOIDBORN** into a developer-programmable RTS where players control units via custom Lua code while preserving deterministic multiplayer synchronization and strict security, we divide the codebase into two execution realms:

1. **Synced Realm (`LuaRules/Gadgets/`)**: Authoritative simulation running identically on all clients and the server. It handles game state, unit movement/combat, CPU budgeting, and the sandboxed execution of user code.
2. **Unsynced Realm (`LuaUI/Widgets/`)**: Local client environment handling rendering, HUDs, local file-watching, hot-reloading, and custom tactical overlays without risking simulation desyncs.

---

## 1. Synced Unit Scripting Sandbox (`LuaRules/Gadgets/`)

### Code Ingestion & Sync Pipeline

Players edit their script locally (e.g., in VS Code). A LuaUI widget reads the file content, compresses or chunks it if needed, and transmits it via `Spring.SendLuaRulesMsg()`.

```
[Local VS Code] -> [LuaUI File Watcher] -> (SendLuaRulesMsg) -> [Synced Gadget: GotNetMsg] -> [Validation & Sandbox Compilation]
```

#### Gadget Implementation (`LuaRules/Gadgets/programmable_units.lua`)

```lua
function gadget:GetInfo()
    return {
        name      = "Programmable Units Sandbox",
        desc      = "Securely compiles and executes per-unit user scripts",
        author    = "goddot info@bitopsy.com",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true
    }
end

if not gadgetHandler:IsSyncedCode() then
    return
end

-- Synced state tracking
local unitScripts = {} -- [unitID] = { env = {}, chunk = fn, cpuLimit = 1000 }

-- Sandbox base environment (stripped of unsafe globals)
local SAFE_GLOBALS = {
    ipairs = ipairs,
    pairs = pairs,
    next = next,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    table = {
        insert = table.insert,
        remove = table.remove,
        sort = table.sort,
        unpack = table.unpack,
    },
    math = {
        abs = math.abs,
        acos = math.acos,
        asin = math.asin,
        atan = math.atan,
        atan2 = math.atan2,
        ceil = math.ceil,
        cos = math.cos,
        deg = math.deg,
        exp = math.exp,
        floor = math.floor,
        log = math.log,
        max = math.max,
        min = math.min,
        pi = math.pi,
        rad = math.rad,
        sin = math.sin,
        sqrt = math.sqrt,
        tan = math.tan,
    }
}

-- Curated Unit Control API Builder (Hardware-Gated)
local function BuildUnitAPI(unitID, unitTeam)
    return {
        MoveTo = function(x, y, z)
            if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end
            Spring.GiveOrderToUnit(unitID, CMD.MOVE, {x, y, z}, 0)
        end,
        Attack = function(targetID)
            if type(targetID) ~= "number" then return end
            Spring.GiveOrderToUnit(unitID, CMD.ATTACK, {targetID}, 0)
        end,
        GetPos = function()
            local x, y, z = Spring.GetUnitPosition(unitID)
            return x, y, z
        end,
        GetHealth = function()
            local hp, maxHp = Spring.GetUnitHealth(unitID)
            return hp, maxHp
        end,
        GetNearbyEnemies = function(radius)
            radius = math.min(radius or 500, 2000) -- clamp search range
            local x, y, z = Spring.GetUnitPosition(unitID)
            local enemies = Spring.GetUnitsInCylinder(x, z, radius, unitTeam) -- Note: team filtering logic
            local result = {}
            for _, eID in ipairs(enemies) do
                if Spring.GetUnitTeam(eID) ~= unitTeam then
                    table.insert(result, eID)
                end
            end
            return result
        end,
        Log = function(msg)
            Spring.Echo(string.format("[Unit %d Script]: %s", unitID, tostring(msg)))
        end
    }
end

-- Hook instruction limit handler for CPU budgeting
local function instructionLimitHook(unitID)
    return function(step)
        error(string.format("CPU limit exceeded for unit %d (infinite loop or heavy computation)", unitID))
    end
end

-- Ingestion via LuaRules message
function gadget:RecvLuaMsg(msg, playerID)
    if not msg:sub(1, 14) == "SET_SCRIPT:" then return end
    -- Format: SET_SCRIPT:<unitID>:<lua_code>
    local _, _, uIDStr, code = string.find(msg, "SET_SCRIPT:(%d+):(.*)")
    local unitID = tonumber(uIDStr)
    if not unitID or not Spring.ValidUnitID(unitID) then return end

    local teamID = Spring.GetUnitTeam(unitID)
    
    -- Compile code in sandbox
    local env = {}
    for k, v in pairs(SAFE_GLOBALS) do env[k] = v end
    env.unit = BuildUnitAPI(unitID, teamID)

    local chunk, err = load(code, "UnitScript_" .. unitID, "t", env)
    if not chunk then
        Spring.Echo(string.format("Compilation error on unit %d script: %s", unitID, tostring(err)))
        return
    end

    unitScripts[unitID] = {
        chunk = chunk,
        env = env,
        unitID = unitID
    }
    Spring.Echo(string.format("Successfully hot-loaded script for Unit %d", unitID))
end

function gadget:GameFrame(n)
    for unitID, data in pairs(unitScripts) do
        if not Spring.ValidUnitID(unitID) then
            unitScripts[unitID] = nil
        else
            -- Run user script tick function if defined
            local updateFn = data.env.OnUpdate
            if type(updateFn) == "function" then
                debug.sethook(data.chunk, instructionLimitHook(unitID), "", 2000) -- max 2000 bytecode instructions per frame
                local success, err = pcall(updateFn)
                debug.sethook() -- clear hook

                if not success then
                    Spring.Echo(string.format("Runtime error in Unit %d script: %s", unitID, tostring(err)))
                    -- Disable broken script to prevent spam
                    data.env.OnUpdate = nil
                end
            end
        end
    end
end

function gadget:UnitDestroyed(unitID)
    unitScripts[unitID] = nil
end
```

---

## 2. Hardware-Gated API Architecture (2-Faction Integration)

Factions and upgrade modules dynamically extend or restrict the available methods inside `env.unit`. For example, **Choir of the Eye** units equipped with a *Seer Gaze Module* gain access to `unit:RadarScan()`, whereas **Maw Swarm** units equipped with a *Cyst Node* gain `unit:AbsorbBiomass()`.

```lua
local function BuildFactionAPI(unitID, unitTeam, unitDefID)
    local unitDef = UnitDefs[unitDefID]
    local customParams = unitDef.customParams or {}
    local api = BuildUnitAPI(unitID, unitTeam) -- Base API

    -- Hardware gating based on customParams or custom game states
    if customParams.has_radar == "true" or Spring.GetUnitRulesParam(unitID, "equipped_radar") == 1 then
        api.RadarScan = function(range)
            -- Radar scan implementation
            local x,y,z = Spring.GetUnitPosition(unitID)
            return Spring.GetUnitsInCylinder(x, z, range or 1000)
        end
    end

    if customParams.faction == "choir" then
        api.CataractStare = function(targetID)
            Spring.GiveOrderToUnit(unitID, CMD.INSERT, {CMD.STOP, targetID}, {"alt"})
        end
    elseif customParams.faction == "maw" then
        api.Devour = function(targetID)
            Spring.GiveOrderToUnit(unitID, CMD.ATTACK, {targetID}, 0)
        end
    end

    return api
end
```

---

## 3. Unsynced Custom Vision & HUD Widgets (`LuaUI/Widgets/`)

Players write local widgets to render custom tactical overlays, debug logs, and telemetry graphs.

### Widget Implementation (`LuaUI/Widgets/hud_programmable_debug.lua`)

```lua
function widget:GetInfo()
    return {
        name      = "Programmable Unit Debug HUD",
        desc      = "Renders custom world-space overlays and telemetry for programmable units",
        author    = "goddot info@bitopsy.com",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true
    }
end

function widget:DrawWorld()
    local _, _, spec, teamID = Spring.GetPlayerInfo(Spring.GetMyPlayerID())
    local myUnits = Spring.GetTeamUnits(teamID)

    gl.Color(0, 1, 0.5, 0.8)
    gl.LineWidth(1.5)

    for _, unitID in ipairs(myUnits) do
        local x, y, z = Spring.GetUnitPosition(unitID)
        if x then
            -- Draw tactical selection ring or state indicator
            gl.DrawGroundCircle(x, y, z, 45, 32)
            
            -- Render world text above unit
            local screenX, screenY, screenZ = Spring.WorldToScreenCoords(x, y + 30, z)
            if screenZ and screenZ > 0 and screenZ < 1 then
                -- Optional: draw debug text if font is loaded
            end
        end
    end
end
```

---

## 4. Developer Workflow (Hot-Reloading Widget)

### File Watcher & Hot-Reload Widget (`LuaUI/Widgets/dev_script_watcher.lua`)

```lua
function widget:GetInfo()
    return {
        name      = "Script Hot-Reloader",
        desc      = "Watches local lua file changes and sends updates to synced gadget",
        author    = "goddot info@bitopsy.com",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true
    }
end

local watchFile = "Voidborn/scripts/my_unit_ai.lua"
local lastCheck = 0
local lastMtime = 0

function widget:Update(dt)
    -- Check every 1 second (Spring doesn't have native async fs watch, use io.open or os.date check if permitted, 
    -- or trigger manually via keybind / console command)
end

-- Manual reload trigger via chat or keybind /action
function widget.KeyPress(key, mods, isRepeat)
    if key == 0x72 and mods.ctrl then -- Ctrl+R hotkey
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits == 0 then
            Spring.Echo("Hot-Reload: No units selected!")
            return
        end

        -- Read local script file
        -- Note: In standard Spring LuaUI, io operations are restricted unless LuaSocket/lfs is enabled,
        -- or files are loaded from the allowed LuaUI/data directory.
        local f = io.open("lua_scripts/active_ai.lua", "r")
        if f then
            local code = f:read("*all")
            f:close()

            for _, uID in ipairs(selectedUnits) do
                Spring.SendLuaRulesMsg(string.format("SET_SCRIPT:%d:%s", uID, code))
            end
            Spring.Echo(string.format("Hot-Reloaded script onto %d units!", #selectedUnits))
        else
            Spring.Echo("Hot-Reload error: Could not open lua_scripts/active_ai.lua")
        end
    end
end
```

---

## Example Starter Unit AI Script (`lua_scripts/active_ai.lua`)

```lua
-- Starter Unit AI Script
-- Available API: unit.GetPos(), unit.GetHealth(), unit.GetNearbyEnemies(radius), unit.MoveTo(x,y,z), unit.Attack(targetID), unit.Log(msg)

local state = "PATROL"
local patrolTarget = { x = 1000, y = 0, z = 1000 }

function OnUpdate()
    local x, y, z = unit.GetPos()
    local enemies = unit.GetNearbyEnemies(800)

    if #enemies > 0 then
        -- Engage nearest enemy
        local nearestEnemy = enemies[1]
        unit.Log("Enemy spotted! Engaging unit " .. tostring(nearestEnemy))
        unit.Attack(nearestEnemy)
    else
        -- Move towards patrol point
        local dx, dz = x - patrolTarget.x, z - patrolTarget.z
        local dist = math.sqrt(dx*dx + dz*dz)
        if dist < 100 then
            -- Swap patrol target
            patrolTarget.x = math.random(200, 4800)
            patrolTarget.z = math.random(200, 4800)
        end
        unit.MoveTo(patrolTarget.x, 0, patrolTarget.z)
    end
end
```

---

## Common Spring/Recoil Desync Pitfalls to Avoid

1. **`pairs()` Iteration Order Non-Determinism**: 
   Iterating over standard Lua tables using `pairs()` has randomized key ordering in Lua 5.1/Luajit depending on memory allocation history. If user scripts iterate over entity tables and perform simulation actions (like issuing orders or modifying synced game state) based on iteration order, **clients will immediately desync**. 
   * *Solution*: Always sort keys into an array using `table.sort()` before iterating in synced code.

2. **Floating-Point Math Discrepancies (`math.sin`, `math.cos`)**:
   Different CPU architectures or compiler flags can produce microscopic floating-point rounding differences in trigonometric functions. 
   * *Solution*: Restrict user scripts from performing raw trigonometric calculations that affect critical unit positioning, or ensure all movement decisions are delegated to engine command queues (`Spring.GiveOrderToUnit`) rather than custom coordinate math executed per frame in synced gadgets.

3. **Global State Pollution**:
   Failing to wipe `_g` or sharing state tables across different unit scripts can lead to cross-talk where one unit's script inadvertently modifies globals accessed by another unit or gadget.
   * *Solution*: Always compile each unit's script with a fresh environment table via `load(code, name, "t", env)` where `env` has an isolated metatable pointing back to `SAFE_GLOBALS`.
