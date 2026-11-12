function widget:GetInfo()
    return {
        name      = "Developer Console",
        desc      = "Lua console. Hold SHIFT and press TILDE (~) to open, use /commands in chat.",
        author    = "Voidborn Dev",
        date      = "2026",
        license   = "GPL",
        layer     = 0,
        enabled   = true
    }
end

-- Simple command processing
local function ProcessCommand(cmd)
    local c = cmd:lower()
    if c == "/help" then
        Spring.Echo("Commands: /help, /units, /listapi, /exec, /clear, /automex info")
    elseif c == "/units" then
        local sel = Spring.GetSelectedUnits()
        Spring.Echo("Selected: " .. (#sel or 0) .. " unit(s)")
        for _,u in ipairs(sel or {}) do
            local ud = Spring.GetUnitDef(u)
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
    else
        Spring.Echo("Unknown command. Type /help")
    end
end

-- Toggle console with TILDE (~) key - this key is less likely to be captured by engine screenshot sys
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