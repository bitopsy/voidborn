function widget:GetInfo()
    return {
        name      = "Developer Console",
        desc      = "Lua console. Press TILDE (~) to open, use /commands in chat.",
        author    = "Voidborn Dev",
        date      = "2026",
        license   = "GPL",
        layer     = 0,
        enabled   = true
    }
end

-- [[ Local state initialization ]]
local visible = false
local inputBuffer = ""
local history = {}

-- Simple command processing with new /widgetlist command
local function ProcessCommand(cmd)
    local c = cmd:lower()
    if c == "/help" then
        Spring.Echo("Commands: /help, /units, /listapi, /exec, /clear, /automex info, /widgetlist")
    elseif c == "/units" then
        local sel = Spring.GetSelectedUnits()
        Spring.Echo("Selected: " .. (#sel or 0) .. " unit(s)")
        for _,u in ipairs(sel or {}) do
            local ud = UnitDefs[Spring.GetUnitDefID(u)]
            Spring.Echo("  Unit " .. u .. ": " .. (ud and ud.name or "unknown"))
        end
    elseif c == "/listapi" then
        Spring.Echo("API: MoveTo, Attack, GetPos, GetHealth, GetNearbyEnemies, Log")
    elseif c:sub(1,5) == "/exec" then
        local code = cmd:sub(7)
        local func, err = load(code)
        if func then
            local ok, res = pcall(func)
            if ok then Spring.Echo("OK") else Spring.Echo("ERR: " .. tostring(res)) end
        else
            Spring.Echo("SYNTAX: " .. tostring(err))
        end
    elseif c == "/clear" then
        Spring.Echo("Cleared")
    elseif c:sub(1,6) == "/automex" then
        local a = cmd:split(" ")
        if a[2] == "info" then
            local cnt = 0
            for _,v in pairs(_G.autoMexValues or {}) do if v and v>0 then cnt=cnt+1 end end
            Spring.Echo("MEX recognized: " .. cnt)
        else
            Spring.Echo("Usage: /automex info")
        end
    elseif c == "/widgetlist" then
        ListWidgets()
    else
        Spring.Echo("Unknown command. Type /help")
    end
end

-- List all widgets and their status
function ListWidgets()
    local wgh = Spring.GetWidgetHandler()
    if not wgh then
        Spring.Echo("Could not access widget handler")
        return
    end
    
    local count = wgh:GetWidgetCount()
    if count == 0 then
        Spring.Echo("No widgets found")
        return
    end
    
    Spring.Echo(string.format("Total widgets: %d", count))
    Spring.Echo(string.rep("-", 60))
    
    local foundAny = false
    for i = 0, count - 1 do
        local widgetID = wgh:GetWidgetID(i)
        if widgetID then
            local info = wgh:GetWidgetInfo(widgetID)
            if info then
                local name = info.name or "Unnamed"
                local desc = info.desc or ""
                local enabled = wgh:IsWidgetEnabled(widgetID)
                local state = enabled and "ON" or "OFF"
                
                foundAny = true
                local line = string.format(" [%s] %s", state, name)
                if desc and desc ~= "" then
                    line = line .. " - " .. desc
                end
                Spring.Echo(line)
            end
        end
    end
    
    if not foundAny then
        Spring.Echo("No widget info available (widgets may use legacy API)")
    end
    
    Spring.Echo(string.rep("-", 60))
    Spring.Echo("Use /help for other commands")
end

-- Toggle console with TILDE (~) key
function widget:KeyPress(key, isRepeat)
    -- Tilde key (~), typically key code 199
    if key == 199 then
        visible = not visible
        Spring.Echo("Console " .. (visible and "opened" or "closed"))
        return true
    end
    
    -- If console is open, handle text input
    if not visible then return false end
    
    if key == 13 then -- Enter
        if inputBuffer ~= "" then
            ProcessCommand(inputBuffer)
            table.insert(history, 1, inputBuffer)
        end
        inputBuffer = ""
        return true
    elseif key == 8 then -- Backspace
        inputBuffer = inputBuffer:sub(1, -2)
        return true
    elseif key >= 32 then -- Printable ASCII
        inputBuffer = inputBuffer .. string.char(key)
        return true
    end
    return false
end

-- Ensure tilde key passes through to widget even if engine tries to consume it
function widget:AllowKeyPress(key)
    if key == 199 then return true end
    return false
end

-- Draw the console screen
function widget:DrawScreen()
    if not visible then return end
    
    -- Draw semi-transparent background
    gl.Color(0.1, 0.1, 0.1, 0.95)
    gl.Rect(20, 20, xSize - 20, ySize - 20)
    
    -- Draw input line
    gl.Color(1, 1, 1, 1)
    Spring.DrawText(30, ySize - 40, "> " .. inputBuffer, xSize - 60, 30, "l")
    
    -- Draw hint
    Spring.DrawText(30, 40, "~ to toggle | /help for commands", xSize - 60, 20, "l")
end

function widget:ViewResize(w, h)
    xSize = w
    ySize = h
end

-- Process chat messages - this handles /commands typed in game chat
function widget:AllowMessage(msg, playerID)
    local cmd = msg:lower()
    -- Only process commands that start with /
    if cmd:sub(1,1) == "/" then
        -- Don't process if console is open and waiting for input (avoid duplicate processing)
        if not visible then
            local parts = {}
            for w in cmd:gmatch("%S+") do table.insert(parts, w) end
            if #parts > 0 then
                ProcessCommand(cmd)
            end
        end
        return true -- prevent the command from being processed again
    end
    return false
end