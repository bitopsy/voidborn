-- Voidborn developer console (rewritten)
-- Open with the key left of "1" (` on QWERTY, ² on AZERTY) or type /vbconsole in chat.
-- Unit creation:  /vbcreate <id> base=<unit> [name= hp= speed= range= dmg= reload= metal= energy= sight= count= team= lua=...]
--                 /vbspawn <id> [count]   /vbtemplates   /vbforget <id>   /vbbases
--                 /vbexec vb.create{ id="x", base="ch_hoplite", hp=5000 }
function widget:GetInfo()
	return { name = "Developer Console", desc = "Toggle with the grave/tilde key or /vbconsole",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

-- Lua code is case sensitive, so the console keeps a normal monospace face now that the glyph font is global
local monoFont, monoTried
local function MonoText(str, x, y, size)
	if not monoTried then
		monoTried = true
		if gl.LoadFont then local ok, f = pcall(gl.LoadFont, "fonts/VoidbornMono.ttf", 32, 3, 1.5); if ok then monoFont = f end end
	end
	if monoFont then monoFont:Begin(); monoFont:Print(str, x, y, size, "o"); monoFont:End() else gl.Text(str, x, y, size, "o") end
end

-- alien UI font (falls back to the engine font if the file or API is missing). The input/output lines below
-- deliberately keep the engine font: the alien face is all-caps and Lua code is case sensitive.
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
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

-- ---------------------------------------------------------------------------------------------
-- unit creation: /vbcreate, /vbspawn, templates
-- ---------------------------------------------------------------------------------------------
local templates = {}      -- id -> spec (saved with the widget config, so recipes survive restarts)
local NUMERIC = { hp = true, metal = true, energy = true, buildtime = true, sight = true, speed = true, range = true,
	dmg = true, reload = true, alt = true, x = true, z = true, count = true, team = true, pngsize = true }
local TEXT = { id = true, name = true, base = true, lua = true, png = true }
local ALIAS = { health = "hp", cost = "metal", bt = "buildtime", los = "sight", n = "count", num = "count", unit = "base", pic = "png", img = "png", image = "png", picsize = "pngsize" }

local function Tokenize(str)   -- splits on spaces; "double quoted" parts stay together (key="two words")
	local t, i, n = {}, 1, #str
	while i <= n do
		if str:sub(i, i):match("%s") then i = i + 1
		else
			local tok = ""
			while i <= n and not str:sub(i, i):match("%s") do
				local ch = str:sub(i, i)
				if ch == '"' then
					local j = str:find('"', i + 1, true) or (n + 1)
					tok = tok .. str:sub(i + 1, j - 1); i = j + 1
				else tok = tok .. ch; i = i + 1 end
			end
			t[#t + 1] = tok
		end
	end
	return t
end

local function Ser(t)   -- spec table -> lua table literal (numbers / strings only)
	local parts = {}
	for k, v in pairs(t) do
		if type(v) == "number" then parts[#parts + 1] = k .. "=" .. string.format("%.6g", v)
		elseif type(v) == "string" then parts[#parts + 1] = k .. "=" .. string.format("%q", v) end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function CursorPos()
	local mx, my = Spring.GetMouseState()
	local _, pos = Spring.TraceScreenRay(mx, my, true)
	if type(pos) == "table" and pos[1] then return pos[1], pos[3] end
	local sel = Spring.GetSelectedUnits() or {}
	if sel[1] then local x, _, z = Spring.GetUnitPosition(sel[1]); if x then return x, z end end
	local x, _, z = Spring.GetTeamStartPosition(Spring.GetMyTeamID())
	return x, z
end

local function Send(spec)
	local s = {}
	for k, v in pairs(spec) do s[k] = v end
	if not s.x or not s.z then s.x, s.z = CursorPos() end
	Spring.SendLuaRulesMsg("vbdev:" .. Ser(s))
end

local function Remember(spec)
	if not spec.id or spec.id == "" then return end
	local keep = {}
	for k, v in pairs(spec) do if k ~= "x" and k ~= "z" then keep[k] = v end end
	templates[spec.id] = keep
end

local autoN = 0
local function Create(spec)
	if type(spec) ~= "table" then Print("vb.create needs a table, e.g. vb.create{ id='x', base='ch_hoplite', hp=5000 }") return false end
	if not spec.base or not UnitDefNames[spec.base] then
		Print("unknown base unit '" .. tostring(spec.base) .. "' - /vbbases lists the unit names") return false
	end
	if not spec.id then autoN = autoN + 1; spec.id = "custom" .. autoN end
	Remember(spec)
	Send(spec)
	return true
end

local function Spawn(id, count, team)
	local t = templates[id]
	if not t then Print("no template '" .. tostring(id) .. "' - see /vbtemplates") return false end
	local spec = {}
	for k, v in pairs(t) do spec[k] = v end
	if count then spec.count = count end
	if team then spec.team = team end
	Send(spec)
	return true
end

local function CmdCreate(rest)
	if rest == "" then
		Print("/vbcreate <id> base=<unit> [name=\"My Unit\" hp=5000 speed=1.5 range=1.3 dmg=2 reload=0.5 metal= energy= sight= count=5 team=1]")
		Print("   speed/range/dmg/reload are multipliers of the base unit. lua=<code> (last option) runs on every spawned unit (unitID is set).")
		Print("   png=<file> shows that image above the unit (bare name = unitpics/<name>.png); pngsize=<elmos> sets its size.")
		Print("   example: /vbcreate dread base=ch_hoplite name=Dread hp=6000 dmg=2.5 range=1.4 count=3 png=dread")
		return
	end
	local code
	local pre, post = rest:match("^(.-)%s+lua=(.*)$")
	if not pre then pre, post = rest:match("^()lua=(.*)$"); if pre then pre = "" end end
	if post then
		rest = pre; code = post
		if #code > 1 and code:sub(1, 1) == '"' and code:sub(-1) == '"' then code = code:sub(2, -2) end
	end
	local spec, bare = {}, {}
	for _, tok in ipairs(Tokenize(rest)) do
		local k, v = tok:match("^([%w_]+)=(.*)$")
		if k then
			k = ALIAS[k:lower()] or k:lower()
			if NUMERIC[k] then
				local n = tonumber(v)
				if not n then Print("'" .. k .. "' needs a number, got '" .. v .. "'") return end
				spec[k] = n
			elseif TEXT[k] then spec[k] = v
			else Print("unknown option '" .. k .. "' (known: id name base hp metal energy buildtime sight speed range dmg reload alt count team x z png pngsize lua)") return end
		else bare[#bare + 1] = tok end
	end
	-- bare words: "/vbcreate ch_hoplite hp=9" (unit name only), "/vbcreate dread ch_hoplite", or "/vbcreate dread base=ch_hoplite"
	if not spec.base and #bare == 1 and UnitDefNames[bare[1]] then spec.base = bare[1]
	elseif not spec.base and bare[2] and UnitDefNames[bare[2]] then spec.id, spec.base = bare[1], bare[2]
	elseif bare[1] and not spec.id then spec.id = bare[1] end
	if code and code ~= "" then spec.lua = code end
	if Create(spec) then
		Print("create request sent: " .. (spec.id or "?") .. " <- " .. tostring(spec.base) .. "  (result is echoed in the chat log)")
	end
end

local function CmdSpawn(rest)
	local a = Tokenize(rest)
	if not a[1] then Print("/vbspawn <id> [count] [team=N]   (templates: /vbtemplates)") return end
	local count, team
	for i = 2, #a do
		local t = a[i]:match("^team=(%d+)$")
		if t then team = tonumber(t) elseif tonumber(a[i]) then count = tonumber(a[i]) end
	end
	if Spawn(a[1], count, team) then Print("spawn request sent: " .. a[1]) end
end

local function CmdTemplates()
	local ids = {}
	for id in pairs(templates) do ids[#ids + 1] = id end
	table.sort(ids)
	if #ids == 0 then Print("no templates yet - make one with /vbcreate") return end
	for _, id in ipairs(ids) do
		local t, bits = templates[id], {}
		for _, k in ipairs({ "name", "hp", "speed", "range", "dmg", "reload", "metal", "energy", "sight", "count", "team", "png", "pngsize" }) do
			if t[k] ~= nil then bits[#bits + 1] = k .. "=" .. tostring(t[k]) end
		end
		Print(string.format(" %-14s <- %-14s %s%s", id, tostring(t.base), table.concat(bits, " "), t.lua and " lua" or ""))
	end
end

local function CmdBases()
	local names = {}
	for name in pairs(UnitDefNames) do names[#names + 1] = name end
	table.sort(names)
	local line = ""
	for _, n in ipairs(names) do
		if #line + #n > 100 then Print(line); line = "" end
		line = line .. n .. "  "
	end
	if line ~= "" then Print(line) end
end

local API = { create = Create, spawn = Spawn, templates = templates, bases = CmdBases }

local commands = {
	help = function()
		Print("/vbhelp /vbunits /vbwidgets /vbclear /vbautomex /vbexec <lua>")
		Print("/vbcreate <id> base=<unit> [opts]   /vbspawn <id> [n]   /vbtemplates   /vbforget <id>   /vbbases   (/vbcreate alone: usage)")
	end,
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
	templates = CmdTemplates,
	bases = CmdBases,
}

local function Run(line)
	line = line:gsub("^/", "")
	local args = Split(line)
	local name = (args[1] or ""):lower():gsub("^vb", "")
	local rest = line:match("^%S+%s+(.*)$") or ""
	if name == "exec" then
		local f, err = compile(rest)
		if not f then Print("SYNTAX: " .. tostring(err)) return true end
		if setfenv then setfenv(f, setmetatable({ vb = API }, { __index = _G })) end   -- vb.create{...} / vb.spawn(...)
		local ok, res = pcall(f); Print(ok and (res ~= nil and tostring(res) or "OK") or ("ERR: " .. tostring(res)))
		return true
	end
	if name == "create" then CmdCreate(rest) return true end
	if name == "spawn" then CmdSpawn(rest) return true end
	if name == "forget" then
		local id = args[2]
		if id and templates[id] then templates[id] = nil; Print("forgot template " .. id) else Print("no such template") end
		return true
	end
	if commands[name] then commands[name]() return true end
	return false
end

function widget:Initialize()
	Spring.Echo("[VB] Developer Console loaded. Press ` / ² or type /vbhelp")
	-- register as proper actions too (most reliable way to receive /commands)
	if widgetHandler and widgetHandler.AddAction then
		for _, name in ipairs({ "vbhelp", "vbunits", "vbwidgets", "vbclear", "vbexec", "vbautomex",
			"vbcreate", "vbspawn", "vbtemplates", "vbforget", "vbbases" }) do
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
function widget:GetConfigData() return { templates = templates } end
function widget:SetConfigData(d) if d and type(d.templates) == "table" then templates = d.templates; API.templates = templates end end
function widget:Shutdown() if visible and hasSDL then Spring.SDL.StopTextInput() end end
function widget:ViewResize(w, h) vsx, vsy = w, h end

function widget:DrawScreen()
	if not visible then return end
	local h = 230  -- compact strip along the top; does not cover the unit/order panels
	gl.Color(0.05, 0.05, 0.08, 0.85)
	gl.Rect(10, vsy - h - 10, vsx - 10, vsy - 10)
	VBFont.Text("VOIDBORN // DEV CONSOLE", vsx - 20, vsy - 30, 15, "or", 0.45, 0.9, 1.0, 0.9)
	gl.Color(1, 1, 1, 1)
	for i, line in ipairs(out) do MonoText(line, 20, vsy - 30 - (i - 1) * 12, 11) end
	MonoText("> " .. input .. "_", 20, vsy - h, 14)
end
