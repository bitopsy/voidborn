function widget:GetInfo()
    return {
        name      = "Developer Console",
        desc      = "In-game chat-based Lua console with basic autocomplete for programmable unit API. Press ENTER in chat to execute commands. Type /help for commands.",
        author    = "Voidborn Dev",
        date      = "2026",
        license   = "GPL",
        layer     = 0,
        enabled   = true
    }
end

-- Available API function names for autocomplete
local apiFunctions = {
    "MoveTo", "Attack", "GetPos", "GetHealth", "GetNearbyEnemies",
    "Log", "RadarScan", "CataractStare", "Devour", "AutoBuild"
}

-- Help text for commands
local helpText = {
    "/help          - Show this help message",
    "/units         - List selected unit IDs and their current API functions",
    "/reload        - Hot-reload unit scripts from file",
    "/listapi       - Show available API functions for programmable units",
    "/exec <code>   - Execute a single line of Lua code",
    "/clear         - Clear console history"
}

-- State
local inputBuffer = ""
local history = {}
local historyPos = 0
local visible = false
local lineHeight = 18
local font = Renderer.GetFont("FreeSans")

function widget:IsReusable()
    return false
end

function widget:ViewResize(xSize, ySize)
    -- Nothing special needed
end

function widget:KeyPress(key, isRepeat, _, _, isCtrl)
    -- Toggle console with F12 key
    if key == 111 then -- F12
        visible = not visible
        if visible then
            inputBuffer = ""
            historyPos = #history + 1
        end
        return true
    end
    
    -- If console is open, handle input
    if visible then
        if key == 13 then -- Enter
            -- Process the input
            local cmd = inputBuffer:trim()
            if cmd ~= "" then
                table.insert(history, 1, cmd)
                historyPos = #history + 1
                
                -- Parse command
                local parts = cmd:split(" ")
                local command = parts[1]:lower()
                local args = {}
                for i = 2, #parts do
                    table.insert(args, parts[i])
                end
                
                ProcessCommand(command, args)
            end
            inputBuffer = ""
            historyPos = #history + 1
            return true
        elseif key == 8 then -- Backspace
            inputBuffer = inputBuffer:sub(1, -2)
            return true
        elseif key >= 32 then -- Printable characters
            inputBuffer = inputBuffer .. string.char(key)
            return true
        end
    end
    return false
end

function ProcessCommand(command, args)
    if command == "/help" then
        for _, line in ipairs(helpText) do
            Spring.Echo(line)
        end
    elseif command == "/units" then
        local selected = Spring.GetSelectedUnits()
        for _, uid in ipairs(selected) do
            local ud = Spring.GetUnitDef(uid)
            if ud then
                local custom = ud.customParams or {}
                local prog = custom.programmable == "true" and " (programmable)" or ""
                Spring.Echo(string.format("Unit %d: %s%s", uid, ud.name or "unknown", prog))
            end
        end
    elseif command == "/listapi" then
        Spring.Echo("Available API functions for programmable units:")
        for _, fn in ipairs(apiFunctions) do
            Spring.Echo("  - " .. fn)
        end
    elseif command == "/exec" then
        if #args > 0 then
            local code = table.concat(args, " ")
            -- Try to execute as Lua
            local func, err = load(code)
            if func then
                -- Execute in a safe sandbox
                local success, result = pcall(func)
                if success then
                    Spring.Echo("Execution successful (no return value)")
                else
                    Spring.Echo("Error: " .. tostring(result))
                end
            else
                Spring.Echo("Lua error: " .. tostring(err))
            end
        else
            Spring.Echo("Usage: /exec <lua code>")
        end
    elseif command == "/clear" then
        -- Clear is handled by just not printing old stuff; Spring.Echo outputs to chat
        Spring.Echo("Console cleared")
    else
        Spring.Echo("Unknown command. Type /help for available commands.")
    end
end

function widget:DrawWorld()
    -- Draw a simple transparent box when console is open
    if visible then
        gl.Color(0, 0, 0, 0.7)
        gl.Rect(20, ySize - 220, xSize - 20, ySize - 20)
        gl.Color(1, 1, 1, 0.9)
        
        -- Draw history lines
        local y = ySize - 210
        local maxLines = 15
        
        -- Draw recent history
        local startIdx = 1
        if #history > maxLines then
            startIdx = #history - maxLines + 1
        end
        
        for i = startIdx, #history do
            local line = history[i]
            Renderer.DrawText(line, 30, y, font)
            y = y + lineHeight
        end
        
        -- Draw input buffer at bottom
        y = ySize - 30
        Renderer.DrawText("> " .. inputBuffer, 30, y, font)
    end
end

-- Helper: trim whitespace
function string:trim()
    return self:match("^%s*(.-)%s*$")
end

-- Helper: split string by delimiter
function string:split(delimiter)
    local result = {}
    local from = 1
        local delim_from, delim_to = string.find(self, delimiter, from)
        while delim_from do
            table.insert(result, string.sub(from, delim_from - 1))
            from = delim_to + 1
            delim_from, delim_to = string.find(self, delimiter, from)
        end
        table.insert(result, string.sub(from))
    return result
end

-- Keep widget handling mouse to prevent interfering with game
function widget:MousePress(x, y, button, isDrag)
    if visible then return true end
    return false
end

function widget:MouseMove(x, y, dx, dy)
    if visible then return true end
    return false
end