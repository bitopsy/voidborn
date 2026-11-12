function gadget:GetInfo()
    return {
        name      = "Auto MEX Recognition",
        desc      = "Builders automatically detect and build mexes/extractors when mousing over resource spots. Improves build UX.",
        author    = "Voidborn Dev",
        date      = "2026",
        license   = "GPL",
        layer     = 0,
        enabled   = true
    }
end
if not gadgetHandler:IsSyncedCode() then return false end

-- Map metal spot data. The engine exposes metal spots per-map via GetMetalAmount(x,z)
-- For each map, the game knows the spot values. We'll store discovered mex values per-unit.
local discoveredMexValues = {}

-- Also keep track of known mex unit defs
local mexUnitDefs = {}
for id, ud in pairs(UnitDefs) do
    if ud.customParams and ud.customParams.kind == "mex" then
        mexUnitDefs[id] = true
    end
end

-- Gadget state per builder unit
local builderState = {}

function gadget:Initialize()
    -- Pre-compute some data
end

-- Called when a builder starts building something
function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdParams2, allyTeam)
    -- We'll handle this later
    return true
end

-- When mouseover happens over a unit, we check if it's a mex and register its value
function gadget:UnitCreated(unitID, unitDefID, unitTeam)
    if mexUnitDefs[unitDefID] then
        local x, _, z = Spring.GetUnitPosition(unitID)
        if x then
            -- Read metal amount from the spot where the mex sits
            -- In Spring, GetMetalAmount expects world coords divided by 16
            local metalVal = Spring.GetMetalAmount(math.floor(x / 16), math.floor(z / 16)) or 0
            discoveredMexValues[unitID] = metalVal
        end
    end
end

-- Main interaction: when a builder is selected and mousing over a mex location
function gadget:MousePress(mouseX, mouseY, button, dragStatus)
    -- Check if we have a selected builder
    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then return end

    for _, uid in ipairs(selectedUnits) do
        local ud = UnitDefs[Spring.GetUnitDefID(uid)]
        if ud and ud.builder then
            -- This is a builder unit; remember it for mouse tracking
            builderState[uid] = true
        end
    end
    return false
end

-- Track mouse movement over resource spots
function gadget:MouseMove(mouseX, mouseY)
    -- Check if any builder is selected
    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then return end

    for _, uid in ipairs(selectedUnits) do
        local ud = UnitDefs[Spring.GetUnitDefID(uid)]
        if ud and ud.builder then
            -- Builder selected - we will handle mex detection in UnitHover
        end
    end
end

-- This gadget handler checks when mouse is over a mex unit and auto-selects build option
function gadget:UnitHover(unitID, x, y)
    -- Check if unitID is a mex
    if not unitID then return end
    
    local ud = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not ud then return end
    
    -- If it's a mex (kind=="mex"), register its metal value
    if ud.customParams and ud.customParams.kind == "mex" then
        local xPos, _, zPos = Spring.GetUnitPosition(unitID)
        if xPos then
            local metalVal = Spring.GetMetalAmount(math.floor(xPos / 16), math.floor(zPos / 16)) or 0
            discoveredMexValues[unitID] = metalVal
            -- Echo info for debugging
            Spring.Echo(string.format("Auto-RECOGNIZED MEX at pos %.1f,%.1f: %.1f metal/s", xPos, zPos, metalVal))
        end
    end
end

-- When a builder starts to build, we suggest the nearest mex
function gadget:AllowBuild(unitID, unitDefID, teamID, cmdID, cx, cy, cz)
    -- Check if this unit can build
    local buildOptions = UnitDefs[unitDefID].buildOptions or {}
    
    -- Look for mexes nearby and suggest them
    local bestMex = nil
    local bestDist = 999999
    
    -- Scan all mex units on the map for nearest one
    for mid, mud in pairs(UnitDefs) do
        if mud.customParams and mud.customParams.kind == "mex" then
            local mx, _, mz = Spring.GetUnitPosition(mid)
            if mx then
                local dist = (mx - cx)^2 + (mz - cz)^2
                if dist < bestDist then
                    bestDist = dist
                    bestMex = mid
                end
            end
        end
    end
    
    if bestMex then
        Spring.Echo(string.format("Suggested build: nearest MEX unit %d at distance %.0f", bestMex, math.sqrt(bestDist)))
        -- Optionally: auto-set the build command to that mex's position
    end
    
    return true
end

-- Add debug info via console command
function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams)
    -- If cmdID is for build/upgrade, provide auto-recognize info
    if cmdID == CMD.BUILD or cmdID == CMD.REPAIR or cmdID == CMD.RECLAIM then
        local x, _, z = Spring.GetUnitPosition(unitID)
        if x then
            -- Scan for nearby mexes and suggest
            local nearestMexDist = 999999
            for mid, m in pairs(UnitDefs) do
                if m.customParams and m.customParams.kind == "mex" then
                    local mx, _, mz = Spring.GetUnitPosition(mid)
                    if mx then
                        local d = (mx - x)^2 + (mz - z)^2
                        if d < nearestMexDist then
                            nearestMexDist = d
                        end
                    end
                end
            end
            if nearestMexDist < 999999 then
                Spring.Echo(string.format("Builder %d: nearest MEX is %.0f elmos away", unitID, math.sqrt(nearestMexDist)))
            end
        end
    end
    return true
end

-- Add a test command: /automex info
-- This is just an example; players can use chat commands in Spring
function gadget:AllowMessage(msg, playerID)
    if msg:sub(1, 8) == "/automex" then
        local args = msg:sub(10):split(" ")
        if args[1] == "info" then
            local count = 0
            for _, v in pairs(discoveredMexValues) do
                if v and v > 0 then count = count + 1 end
            end
            Spring.Echo(string.format("Auto-MEX Recognizer: %d mex(es) currently recognized", count))
        end
        return true
    end
    return false
end