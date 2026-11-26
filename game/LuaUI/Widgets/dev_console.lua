-- Developer tool: only loaded when the "Developer tools" game option (vb_dev, see modoptions.lua) is on, or the dashboard button "DEV MODE" was pressed.
if (Spring.GetModOptions() or {}).vb_dev ~= "1" and not (WG and WG.VBDevMode) then return false end   -- game option, or the DEV MODE button of the dashboard

-- Voidborn developer console (rewritten)
-- Open with the key left of "1" (` on QWERTY, ² on AZERTY) or type /vbconsole in chat.
-- Unit creation:  /vbcreate <id> base=<unit> [name= hp= speed= range= dmg= reload= metal= energy= sight= count= team= lua=...]
--                 /vbspawn <id> [count]   /vbtemplates   /vbforget <id>   /vbbases
--                 /vbexec vb.create{ id="x", base="ch_hoplite", hp=5000 }
function widget:GetInfo()
	return { name = "Developer Console", desc = "Toggle with the grave/tilde key or /vbconsole",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = false }
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
local cursor = 1            -- caret position inside `input` (1 = start)
local hist, histPos = {}, 0
local pending, gotText = nil, false   -- de-duplicates KeyPress fallback vs TextInput
local hasSDL = Spring.SDL and Spring.SDL.StartTextInput and Spring.SDL.StopTextInput
local function SetOpen(v)
	visible = v
	if hasSDL then if v then Spring.SDL.StartTextInput() else Spring.SDL.StopTextInput() end end
	if v then cursor = #input + 1 end
end

-- ---------------------------------------------------------------------------------------
-- autocomplete / autofill / syntax highlighting (shared by every /vb* command)
-- ---------------------------------------------------------------------------------------
local okC, Complete = pcall(VFS.Include, "LuaUI/Headers/vb_complete.h.lua")
if not okC or type(Complete) ~= "table" then
	Complete = { commands = {}, COL = {}, Words = function() return {} end,
	             WordAt = function() return nil end, Candidates = function() return {} end,
	             Highlight = function() return {} end, CommandOf = function() end }
end

-- ---------------------------------------------------------------------------------------
-- the shared template store (the forge panel and this console use the same recipes)
-- ---------------------------------------------------------------------------------------
local okF2, Forge = pcall(VFS.Include, "LuaUI/Headers/vb_forge.h.lua")
if not okF2 or type(Forge) ~= "table" then
	Forge = { templates = {}, rev = 0, Bump = function() end, TemplateIds = function() return {} end,
	          SetTemplate = function() end, DelTemplate = function() end }
end
local templates = Forge.templates

-- cached name lists (rebuilt when the game starts, they never change afterwards)
local unitNameList, pngNameList
local function UnitNames()
	if not unitNameList then
		local names = {}
		for name in pairs(UnitDefNames) do names[#names + 1] = name end
		table.sort(names)
		unitNameList = names
	end
	return unitNameList
end
local function PngNames()
	if not pngNameList then
		local names = {}
		local seen = {}
		local function Add(dir)
			local ok, list = pcall(VFS.DirList, dir, "*.png", VFS.ZIP_ONLY)
			if ok and list then
				for _, f in ipairs(list) do
					local n = f:match("([^/]+)%.png$")
					if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
				end
			end
			local ok2, list2 = pcall(VFS.DirList, dir, "*.png", VFS.RAW_ONLY)
			if ok2 and list2 then
				for _, f in ipairs(list2) do
					local n = f:match("([^/]+)%.png$")
					if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
				end
			end
		end
		Add("unitpics/")
		Add("icons/")
		table.sort(names)
		pngNameList = names
	end
	return pngNameList
end
local function TemplateNames()
	local ids = {}
	for id in pairs(templates) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end
local function Providers()
	return {
		units      = UnitNames,
		pngs       = PngNames,
		templates  = TemplateNames,
		isUnit     = function(n) return UnitDefNames[n] ~= nil end,
		isTemplate = function(n) return templates[n] ~= nil end,
	}
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
-- templates (id -> spec) is declared early (above the completion helpers)
local NUMERIC = { hp = true, metal = true, energy = true, buildtime = true, sight = true, speed = true, range = true,
	dmg = true, reload = true, alt = true, x = true, z = true, count = true, team = true, pngsize = true,
	fire = true, move = true, ["repeat"] = true }
local TEXT = { id = true, name = true, base = true, lua = true, png = true, shape = true }
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
		-- the key is quoted so that Lua keywords ("repeat") survive the round trip
		if type(v) == "number" then parts[#parts + 1] = string.format("[%q]=%s", k, string.format("%.6g", v))
		elseif type(v) == "string" then parts[#parts + 1] = string.format("[%q]=%q", k, v) end
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
	Forge.SetTemplate(spec.id, keep)
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
			else Print("unknown option '" .. k .. "' (known: id name base hp metal energy buildtime sight speed range dmg reload alt count team x z png pngsize lua shape fire move repeat)") return end
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
		Print("/vbforge opens the unit forge (design a unit with a 3D shape), /vbsettings opens the split and growth settings")
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
		if id and Forge.DelTemplate(id) then Print("forgot template " .. id) else Print("no such template") end
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
-- the forge and the settings panel own their own commands, so leave them alone
local OTHER = { vbforge = true, vbsettings = true }
function widget:TextCommand(cmd)
	if cmd == "vbconsole" then SetOpen(not visible) return true end
	if OTHER[cmd] then return true end
	if cmd:sub(1, 2) == "vb" then return Run(cmd) end
	if cmd == "help" or cmd == "units" then return Run(cmd) end  -- plain /help and /units also work
end

-- grave key on any layout: SDL scancode 53, or keysyms ` (96), ² (178), § (167), ~ (126)
local function IsToggleKey(key, scanCode)
	return scanCode == 53 or key == 96 or key == 178 or key == 167 or key == 126
end

-- ---------------------------------------------------------------------------------------
-- editing helpers
-- ---------------------------------------------------------------------------------------
local function ClampCursor()
	if cursor < 1 then cursor = 1 end
	if cursor > #input + 1 then cursor = #input + 1 end
end
local function Insert(str)
	input = input:sub(1, cursor - 1) .. str .. input:sub(cursor)
	cursor = cursor + #str
	ClampCursor()
end
local function Backspace()
	if cursor > 1 then
		input = input:sub(1, cursor - 2) .. input:sub(cursor)
		cursor = cursor - 1
	end
end
local function Delete()
	if cursor <= #input then
		input = input:sub(1, cursor - 1) .. input:sub(cursor + 1)
	end
end

-- ---------------------------------------------------------------------------------------
-- completion: TAB completes the word under the cursor, a second TAB cycles the candidates
-- ---------------------------------------------------------------------------------------
local cands, candIdx = {}, 0

local function RefreshCandidates()
	cands = Complete.Candidates(input, cursor, Providers()) or {}
	if candIdx > #cands then candIdx = 0 end
end

local function ApplyCandidate(i)
	local c = cands[i]
	if not c then return end
	local word = Complete.WordAt(input, cursor)
	if not word then return end
	-- replace the word under the cursor with the candidate
	local head = input:sub(1, word.start - 1)
	local tail = input:sub(word.stop + 1)
	input = head .. c.text .. tail
	cursor = word.start + #c.text
	ClampCursor()
end

local function CompleteOnce()
	RefreshCandidates()
	if #cands == 0 then
		Print("no completion for: " .. (input:sub(1, cursor)))
		return
	end
	if #cands == 1 then
		ApplyCandidate(1)
		candIdx = 0
		return
	end
	-- several matches: show them, and cycle through them on every further TAB
	candIdx = (candIdx % #cands) + 1
	ApplyCandidate(candIdx)
end

local function ShowCandidateList()
	local list = {}
	for i, c in ipairs(cands) do
		list[#list + 1] = (i == candIdx and "> " or "  ") .. c.text .. "   (" .. c.kind .. ")"
	end
	return list
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
		input = ""; cursor = 1; cands, candIdx = {}, 0
	elseif key == 9 then                         -- Tab: autocomplete
		if not isRepeat then CompleteOnce() end
	elseif key == 8 then Backspace()             -- Backspace
	elseif key == 127 then Delete()              -- Delete
	elseif key == 27 then SetOpen(false)         -- Esc
	elseif key == 273 then                       -- Up: older command
		if histPos < #hist then histPos = histPos + 1; input = hist[histPos]; cursor = #input + 1 end
	elseif key == 274 then                       -- Down: newer command
		if histPos > 1 then histPos = histPos - 1; input = hist[histPos]
		else histPos = 0; input = "" end
		cursor = #input + 1
	elseif key == 276 then cursor = cursor + 1   -- Right
	elseif key == 275 then cursor = cursor - 1   -- Left
	elseif key == 277 then cursor = 1            -- Home
	elseif key == 278 then cursor = #input + 1   -- End
	elseif not gotText and key >= 32 and key <= 126 then   -- fallback typing (QWERTY), only until TextInput proves to work
		local ch = string.char(key)
		if mods and mods.shift then ch = (ch:match("%a") and ch:upper()) or SHIFT[ch] or ch end
		Insert(ch); pending = ch
	end
	ClampCursor()
	return true  -- swallow keys while open
end

local TOGGLE_CHARS = { ["`"]=true, ["~"]=true, ["²"]=true, ["§"]=true }
function widget:TextInput(char)
	if not visible then return false end
	if TOGGLE_CHARS[char] then return true end                  -- ignore the key that opened us
	gotText = true
	if pending == char then pending = nil return true end        -- already typed by the fallback just now
	pending = nil
	Insert(char)
	return true
end
function widget:GetConfigData() return { templates = templates, rev = Forge.rev } end
function widget:SetConfigData(d)
	-- the forge panel keeps its own copy of the template store; only the newer one wins
	if d and type(d.templates) == "table" and (d.rev or 0) > (Forge.rev or 0) then
		for k in pairs(templates) do templates[k] = nil end
		for k, v in pairs(d.templates) do templates[k] = v end
		Forge.rev = d.rev
	end
	API.templates = templates
end
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

	-- the input line, syntax highlighted
	local segs = Complete.Highlight(input, Providers()) or {}
	local x, y, fs = 20, vsy - h, 14
	local charW = gl.GetTextWidth("M") * (fs / 12)
	-- "> " prompt
	MonoText("> ", x, y, fs)
	x = x + charW * 2
	-- the text before the caret is drawn normally, the part after it dimmed
	for _, seg in ipairs(segs) do
		local before = (seg.start or 1) <= cursor
		local txt = seg.text
		-- split the segment at the caret
		local cut = cursor - (seg.start or 1)
		if seg.start == nil then
			-- the highlight helper does not track offsets; fall back to a plain colour
			gl.Color(seg.col[1], seg.col[2], seg.col[3], 1)
			MonoText(txt, x, y, fs)
			x = x + charW * #txt
		else
			local a = txt:sub(1, cut)
			local b = txt:sub(cut + 1)
			if a ~= "" then
				gl.Color(seg.col[1], seg.col[2], seg.col[3], 1)
				MonoText(a, x, y, fs)
				x = x + charW * #a
			end
			if b ~= "" then
				gl.Color(seg.col[1], seg.col[2], seg.col[3], 0.45)
				MonoText(b, x, y, fs)
				x = x + charW * #b
			end
		end
	end
	-- the caret
	gl.Color(0.45, 0.95, 1.0, 0.95)
	gl.Rect(x - 1, y - 2, x + 1, y + fs)

	-- the inline hint: the rest of the best candidate, drawn dimmed after the caret
	local hint
	do
		local list = Complete.Candidates(input, cursor, Providers()) or {}
		if #list == 1 then
			local word = Complete.WordAt(input, cursor)
			if word and list[1].text:sub(1, #word.text) == word.text then
				hint = list[1].text:sub(#word.text + 1)
			end
		end
	end
	if hint and hint ~= "" then
		gl.Color(0.42, 0.48, 0.60, 1)
		MonoText(hint, x, y, fs)
	end

	-- the candidate list (TAB dropdown)
	if #cands > 1 then
		local lines = ShowCandidateList()
		local lw = 0
		for _, l in ipairs(lines) do lw = math.max(lw, gl.GetTextWidth(l)) end
		local bx = math.min(vsx - 20 - lw - 20, x)
		local by = y - 16 - (#lines * 14) - 8
		gl.Color(0.06, 0.06, 0.10, 0.95)
		gl.Rect(bx - 10, by, bx + lw + 14, by + #lines * 14 + 10)
		gl.Color(0.35, 0.85, 1.0, 0.5)
		gl.Rect(bx - 10, by, bx + lw + 14, by + 1)
		for i, l in ipairs(lines) do
			local c = (i == candIdx) and { 0.45, 0.95, 1.0 } or { 0.7, 0.75, 0.85 }
			gl.Color(c[1], c[2], c[3], 1)
			MonoText(l, bx, by + 6 + (i - 1) * 14, 11)
		end
	end
end
