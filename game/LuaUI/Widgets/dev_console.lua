-- Voidborn developer console (rewritten)
-- Open with the key left of "1" (` on QWERTY, ² on AZERTY) or type /vbconsole in chat.
function widget:GetInfo()
	return { name = "Developer Console", desc = "Toggle with the grave/tilde key or /vbconsole",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = 0, enabled = true }
end

local visible, input = false, ""
local hist, histPos = {}, 0
local pending, gotText = nil, false   -- de-duplicates KeyPress fallback vs TextInput
local hasSDL = Spring.SDL and Spring.SDL.StartTextInput and Spring.SDL.StopTextInput
local function SetOpen(v)
	visible = v
	if hasSDL then if v then Spring.SDL.StartTextInput() else Spring.SDL.StopTextInput() end end
end
-- QWERTY shifted symbols, used only when the engine gives us no TextInput events
local SHIFT = { ["1"]="!",["2"]="@",["3"]="#",["4"]="$",["5"]="%",["6"]="^",["7"]="&",["8"]="*",["9"]="(",["0"]=")",
	["-"]="_",["="]="+",["["]="{",["]"]="}",[";"]=":",["'"]='"',[","]="<",["."]=">",["/"]="?",["\\"]="|",["`"]="~" }
local vsx, vsy = Spring.GetViewGeometry()
local out = {}  -- scrollback lines

local function Print(s) out[#out + 1] = tostring(s); if #out > 14 then table.remove(out, 1) end; Spring.Echo(s) end
local compile = loadstring or load

local function Split(s) local t = {} for w in s:gmatch("%S+") do t[#t + 1] = w end return t end

local function ListWidgets()
	local n = 0
	local kw = widgetHandler and widgetHandler.knownWidgets
	if not kw then Print("Widget list not exposed to widgets - press F11 for the widget selector.") return end
	for name, w in pairs(kw) do
		n = n + 1
		Print(string.format(" [%s] %s", w.active and "ON" or "off", name))
	end
	Print("Total widgets known: " .. n .. "   (F11 opens the widget selector)")
end

local commands = {
	help = function() Print("/vbhelp /vbunits /vbexec <lua> /vbclear /vbwidgets /vbautomex") end,
	units = function()
		local sel = Spring.GetSelectedUnits() or {}
		Print("Selected: " .. #sel)
		for _, u in ipairs(sel) do
			local ud = UnitDefs[Spring.GetUnitDefID(u)]
			Print("  " .. u .. ": " .. (ud and ud.name or "?"))
		end
	end,
	clear = function() out = {} end,
	widgets = ListWidgets,
	automex = function() Print("See infolog: 'Auto-RECOGNIZED MEX' lines (gadget runs in synced code).") end,
}

local function Run(line)
	line = line:gsub("^/", "")
	local args = Split(line)
	local name = (args[1] or ""):lower():gsub("^vb", "")
	if name == "exec" then
		local f, err = compile(line:match("^%S+%s+(.*)$") or "")
		if not f then Print("SYNTAX: " .. tostring(err)) return true end
		local ok, res = pcall(f); Print(ok and "OK" or ("ERR: " .. tostring(res)))
		return true
	end
	if commands[name] then commands[name]() return true end
	return false
end

function widget:Initialize()
	Spring.Echo("[VB] Developer Console loaded. Press ` / ² or type /vbhelp")
	-- register as proper actions too (most reliable way to receive /commands)
	if widgetHandler and widgetHandler.AddAction then
		for _, name in ipairs({ "vbhelp", "vbunits", "vbwidgets", "vbclear", "vbexec", "vbautomex" }) do
			widgetHandler:AddAction(name, function(_, extra, args)
				local line = name .. " " .. (type(extra) == "string" and extra or "")
				Run(line)
				return true
			end, nil, "t")
		end
		widgetHandler:AddAction("vbconsole", function() SetOpen(not visible) return true end, nil, "t")
	end
end

-- engine chat commands: "/vbhelp" arrives here as "vbhelp"
function widget:TextCommand(cmd)
	if cmd == "vbconsole" then SetOpen(not visible) return true end
	if cmd:sub(1, 2) == "vb" then return Run(cmd) end
	if cmd == "help" or cmd == "units" then return Run(cmd) end  -- plain /help and /units also work
end

-- grave key on any layout: SDL scancode 53, or keysyms ` (96), ² (178), § (167), ~ (126)
local function IsToggleKey(key, scanCode)
	return scanCode == 53 or key == 96 or key == 178 or key == 167 or key == 126
end

function widget:KeyPress(key, mods, isRepeat, label, unicode, scanCode)
	if IsToggleKey(key, scanCode) then
		if not isRepeat then SetOpen(not visible) end
		return true
	end
	if not visible then return false end
	if key == 13 or key == 271 then                -- Return / keypad Enter
		if input ~= "" then
			table.insert(hist, 1, input); histPos = 0
			if not Run(input) then Print("Unknown: " .. input .. "   (try /vbhelp)") end
		end
		input = ""
	elseif key == 8 then input = input:sub(1, -2)  -- Backspace
	elseif key == 27 then SetOpen(false)           -- Esc
	elseif key == 273 then                         -- Up: older command
		if histPos < #hist then histPos = histPos + 1; input = hist[histPos] end
	elseif key == 274 then                         -- Down: newer command
		if histPos > 1 then histPos = histPos - 1; input = hist[histPos] else histPos = 0; input = "" end
	elseif not gotText and key >= 32 and key <= 126 then   -- fallback typing (QWERTY), only until TextInput proves to work
		local ch = string.char(key)
		if mods and mods.shift then ch = (ch:match("%a") and ch:upper()) or SHIFT[ch] or ch end
		input = input .. ch; pending = ch
	end
	return true  -- swallow keys while open
end

local TOGGLE_CHARS = { ["`"]=true, ["~"]=true, ["²"]=true, ["§"]=true }
function widget:TextInput(char)
	if not visible then return false end
	if TOGGLE_CHARS[char] then return true end                  -- ignore the key that opened us
	gotText = true
	if pending == char then pending = nil return true end        -- already typed by the fallback just now
	pending = nil
	input = input .. char
	return true
end
function widget:Shutdown() if visible and hasSDL then Spring.SDL.StopTextInput() end end
function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:DrawScreen()
	if not visible then return end
	local h = 230  -- compact strip along the top; does not cover the unit/order panels
	gl.Color(0.05, 0.05, 0.08, 0.85)
	gl.Rect(10, vsy - h - 10, vsx - 10, vsy - 10)
	gl.Color(1, 1, 1, 1)
	for i, line in ipairs(out) do gl.Text(line, 20, vsy - 30 - (i - 1) * 12, 11, "o") end
	gl.Text("> " .. input .. "_", 20, vsy - h, 14, "o")
end
