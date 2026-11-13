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

-- Track discovered mex values per unit ID
local discoveredMexValues = {}

-- Mark unit defs that are mexes
local mexUnitDefs = {}
for id, ud in pairs(UnitDefs) do
    if ud.customParams and ud.customParams.kind == "mex" then
        mexUnitDefs[id] = true
    end
end

function gadget:Initialize()
    -- Store mex values for existing mex units
    for unitID, unitDefID in pairs(UnitDefs) do
        if mexUnitDefs[unitDefID] then
            local x, _, z = Spring.GetUnitPosition(unitID)
            if x then
                local metalVal = Spring.GetMetalAmount(math.floor(x / 16), math.floor(z / 16)) or 0
                discoveredMexValues[unitID] = metalVal
            end
        end
    end
end

-- When a mex unit is created, register its metal value
function gadget:UnitCreated(unitID, unitDefID, unitTeam)
    if mexUnitDefs[unitDefID] then
        local x, _, z = Spring.GetUnitPosition(unitID)
        if x then
            local metalVal = Spring.GetMetalAmount(math.floor(x / 16), math.floor(z / 16)) or 0
            discoveredMexValues[unitID] = metalVal
            Spring.Echo(string.format("Auto-RECOGNIZED MEX at %.1f,%.1f: %.1f metal/s", x, z, metalVal))
        end
    end
end

-- When mouse is over a unit, show metal value if it's a mex
function gadget:UnitHover(unitID, x, y)
    if not unitID then return end
    
    local ud = UnitDefs[Spring.GetUnitDefID(unitID)]
    if not ud then return end
    
    -- If it's a mex, ensure its value is recorded
    if ud.customParams and ud.customParams.kind == "mex" then
        local xPos, _, zPos = Spring.GetUnitPosition(unitID)
        if xPos and not discoveredMexValues[unitID] then
            local metalVal = Spring.GetMetalAmount(math.floor(xPos / 16), math.floor(zPos / 16)) or 0
            discoveredMexValues[unitID] = metalVal
            Spring.Echo(string.format("Auto-RECOGNIZED MEX: %.1f,%.1f = %.1f metal/s", xPos, zPos, metalVal))
        end
    end
end

-- When a builder selects a build location, suggest nearest mex
function gadget:AllowBuild(unitID, unitDefID, teamID, cmdID, cx, cy, cz)
    -- Only process for builder units
    local ud = UnitDefs[unitDefID]
    if not ud or not ud.builder then return true end
    
    -- Find nearest mex unit
    local bestMex = nil
    local bestDist = 999999
    
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
        Spring.Echo(string.format("Suggested build: nearest MEX unit %d (%.0f elmos away)", bestMex, math.sqrt(bestDist)))
    end
    
    return true
end

-- Chat command: /automex info
function gadget:AllowMessage(msg, playerID)
    if msg:sub(1, 8) == "/automex" then
        local args = {}
        for w in msg:sub(10):gmatch("%S+") do table.insert(args, w) end
        if args[1] == "info" then
            local count = 0
            for _, v in pairs(discoveredMexValues) do
                if v and v > 0 then count = count + 1 end
            end
            Spring.Echo(string.format("Auto-MEX Recognizer: %d mex(es) currently recognized", count))
        else
            Spring.Echo("Usage: /automex info")
        end
        return true
    end
    return false
end