function widget:GetInfo()
	return { name = "Voidborn Build Panel", desc = "Compact draggable build/order/toggle panel with scale handle and close button",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 6, enabled = true }
end

-- alien UI font; falls back to the engine font automatically if it cannot load
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end

-- the unit forge: the [+] tile at the end of the build row opens it, and the designs saved in it
-- show up as tiles in this panel (for this game only).
local okG, Forge0 = pcall(VFS.Include, "LuaUI/Headers/vb_forge.h.lua")
if not okG or type(Forge0) ~= "table" then
	Spring.Echo("[VB] build panel: could not load LuaUI/Headers/vb_forge.h.lua: " .. tostring(Forge0))
	Forge0 = nil
end
local NOFORGE = { RequestOpen = function() end, IsForgeReady = function() return false end, templates = {},
	TemplateIds = function() return {} end, ReadQueue = function() return {}, {} end, Price = function() return nil end,
	QueueReady = function() return false end, QueueAdd = function() end, QueueRemove = function() end,
	QueueHold = function() end, EditTemplate = function() end, DeleteTemplate = function() end, PngPath = function() end,
	T2Ready = function() return true end }
-- The forge widget publishes its own table in WG.VBForge; prefer it when it is ready, so that the two
-- widgets always talk about the same templates even if the header got loaded twice.
local function ForgeRef()
	local w = WG and WG.VBForge
	if w and w.IsForgeReady and w.IsForgeReady() then return w end
	return Forge0 or NOFORGE
end

-- build points per second of the production queue (same header the forge and the gadgets use)
local okCH, CostH = pcall(VFS.Include, "LuaRules/Headers/vb_cost.h.lua")
local BUILD_POWER = (okCH and type(CostH) == "table" and tonumber(CostH.BUILD_POWER)) or 100

-- Tier 2: the [+] tile and the saved designs stay grey until the faction's factory is upgraded to Tier 2.
local function T2Locked()
	local F = ForgeRef()
	return F.T2Ready and not F.T2Ready() or false
end
local UPG_COST
local function UpgradeCost()      -- { metal, energy } read from the factory defs, the one place the rule lives
	if UPG_COST then return UPG_COST end
	UPG_COST = { metal = 2000, energy = 2800 }
	for id, ud in pairs(UnitDefs) do
		local cp = type(id) == "number" and ud.customParams
		if cp and cp.upgrade_metal then
			UPG_COST = { metal = tonumber(cp.upgrade_metal) or 2000, energy = tonumber(cp.upgrade_energy) or 2800 }
			break
		end
	end
	return UPG_COST
end
local function UpgradeProgress()  -- 0..1 of the most advanced upgrade of mine under way, or nil
	local s = Spring.GetTeamRulesParam(Spring.GetMyTeamID(), "vbu_list")
	local best
	if type(s) == "string" then
		for _, p in s:gmatch("(%d+:)(%d+)") do best = math.max(best or 0, (tonumber(p) or 0) / 1000) end
	end
	return best
end

local function Snd(name, vol) Spring.PlaySoundFile("sounds/" .. name .. ".wav", vol or 0.7, "ui") end
local lastHoverID, lastHoverSnd   -- id of the command last hovered (nil = none), timer of the last hover sound

-- Stock units go through the same production queue as the forge designs (LuaRules/Gadgets/vb_dev_queue.lua)
-- when a factory is selected: pie chart, hold, right-click to take one out.  Structures still use the engine
-- (they have to be placed), and so does everything when the queue gadget is not running.
local function PlainId(name) return ((("d_" .. name):gsub("[^%w_%-]", "_")):sub(1, 24)) end

-- A lab = a factory (the Hive, Palm, Womb, Nostril, Echo and their tier 2 versions).  Every lab has its own
-- roster (what IT can build) and its own production queue, so the panel always shows ONE lab: the selected one,
-- else the one picked with its chip, else the first.  A tier 1 and a tier 2 lab are never mixed together.
local function IsLab(ud)
	if not ud then return false end
	if ud.isFactory then return true end
	local cp = ud.customParams
	if cp and (cp.kind == "fac" or cp.kind == "fac2") then return true end
	return (not ud.canMove and ud.buildOptions and #ud.buildOptions > 0) and true or false
end
local function LabTier(ud) return tonumber(ud and ud.customParams and ud.customParams.tier) or 1 end
local labs = {}          -- my labs in unitID order: { uid, def, tier, n }
local labPick            -- the lab picked with its chip (used when no lab is selected)
local function SelectedFactory()
	local sel = Spring.GetSelectedUnits() or {}
	for i = 1, #sel do
		local ud = UnitDefs[Spring.GetUnitDefID(sel[i]) or -1]
		if IsLab(ud) then return sel[i] end
	end
end
local function ActiveLab()
	local sel = SelectedFactory()
	if sel then return sel end
	if labPick then
		for _, l in ipairs(labs) do if l.uid == labPick then return labPick end end
	end
	return labs[1] and labs[1].uid
end
-- the lab that builds forge designs: the active one when it is tier 2, else the first tier 2 lab (nil = the team line)
local designLab
local function DesignLab(act)
	for _, l in ipairs(labs) do if l.uid == act and l.tier >= 2 then return act end end
	for _, l in ipairs(labs) do if l.tier >= 2 then return l.uid end end
end

-- Categories: every tile belongs to one of four, shown all at once as labelled sections.
--   ECONOMY  mex, energy, storage, heart       COMBAT  fighting units and defences
--   UTILITY  radar, support units              BUILD   labs and constructors
local CATS = {
	{ id = "E", name = "ECONOMY", col = { 1.00, 0.82, 0.25 } },
	{ id = "C", name = "COMBAT",  col = { 1.00, 0.42, 0.32 } },
	{ id = "U", name = "UTILITY", col = { 0.40, 0.85, 1.00 } },
	{ id = "B", name = "BUILD",   col = { 0.50, 1.00, 0.55 } },
}
local KIND_CAT = { mex = "E", solar = "E", heart = "E", store = "E",
	art = "C", art2 = "C", heavy = "C", heavy2 = "C", assault = "C", assault2 = "C", raider = "C", raider2 = "C",
	scout = "C", combat = "C", def1 = "C", def2 = "C",
	radar = "U", support = "U", support2 = "U",
	fac = "B", fac2 = "B", con = "B", com = "B" }
local catCache = {}
local function CatOf(ud)
	if not ud then return "U" end
	local id = ud.id or 0
	local c = catCache[id]
	if c then return c end
	local cp = ud.customParams
	c = cp and KIND_CAT[cp.kind]
	if not c then      -- no kind given: decide from what the def can do
		if (ud.energyMake or 0) > 0 or (ud.extractsMetal or 0) > 0 or (ud.metalStorage or 0) > 0 or (ud.energyStorage or 0) > 0 then c = "E"
		elseif ud.buildOptions and #ud.buildOptions > 0 then c = "B"
		elseif ud.weapons and #ud.weapons > 0 then c = "C"
		else c = "U" end
	end
	catCache[id] = c
	return c
end

local BUILD_TAG = "q4"        -- shown in the title bar so you can tell which version of the panel is running
do   -- plus the stamp that build_sdz.py puts in the archive (vb_build.txt): proves which .sdz the game loaded
	local okS, st = pcall(function() return VFS.LoadFile("vb_build.txt") end)
	if okS and type(st) == "string" and st ~= "" then BUILD_TAG = BUILD_TAG .. " " .. st:gsub("%s+", "") end
end
do   -- plus the game version: the engine's Game.gameVersion, else the version field of modinfo.lua
	local ver = Game and Game.gameVersion
	if type(ver) ~= "string" or ver == "" or ver:find("$VERSION", 1, true) then
		ver = nil
		local okM, mi = pcall(VFS.Include, "modinfo.lua")
		if okM and type(mi) == "table" and mi.version then ver = tostring(mi.version) end
		if (not ver or ver == "") then
			local okT, txt = pcall(function() return VFS.LoadFile("modinfo.lua") end)
			if okT and type(txt) == "string" then ver = txt:match("version%s*=%s*[\"']([^\"']+)[\"']") end
		end
	end
	if ver and ver ~= "" and not ver:find("$VERSION", 1, true) then
		ver = ver:gsub("^%s+", ""):gsub("%s+$", "")
		BUILD_TAG = BUILD_TAG .. "  v" .. ver:gsub("^[vV]", "")
	end
end

-- Roster: every mobile unit that one of your factories can build, shown whatever is selected.
-- roster[i] = { def = unitDefID, facs = { factory unitIDs that can build it } }
local roster, rosterFrame = {}, -100
local function FactoryDef(uid)
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if IsLab(ud) then return ud end
end
local function CanBuild(fd, defID)
	for _, b in ipairs(fd.buildOptions or {}) do if b == defID or (UnitDefs[defID] and b == UnitDefs[defID].name) then return true end end
	return false
end
-- constr[defID] = { n = how many are under construction, prog = the most advanced 0..1, active = a builder is working on one }
local constr = {}
local function RebuildRoster(skip)
	local order, pend, target = {}, {}, {}
	local ready = (Spring.GetGameRulesParam("vbq_ready") or 0) == 1
	labs = {}
	for _, uid in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID()) or {}) do
		local did = Spring.GetUnitDefID(uid)
		local ud = did and UnitDefs[did]
		if ud then
			-- structures (and units) that are still being built, and what the builders are working on right now
			local _, _, _, _, bp = Spring.GetUnitHealth(uid)
			if bp and bp < 1 then pend[#pend + 1] = { uid, did, bp } end
			if ud.isBuilder or ud.isFactory then
				local t = Spring.GetUnitIsBuilding(uid)
				if t then target[t] = true end
			end
			if IsLab(ud) then labs[#labs + 1] = { uid = uid, def = did, tier = LabTier(ud) } end
		end
	end
	table.sort(labs, function(a, b) return a.uid < b.uid end)
	for i, l in ipairs(labs) do l.n = i end
	-- the roster is what the ACTIVE lab can build: each lab has its own list and its own queue
	local act = ActiveLab()
	local ad = act and FactoryDef(act)
	if ready and ad then
		local seen = {}
		for _, b in ipairs(ad.buildOptions or {}) do
			local bd = type(b) == "number" and UnitDefs[b] or UnitDefNames[b]
			if bd and bd.canMove and not skip[bd.id] and not seen[bd.id] then
				seen[bd.id] = true
				order[#order + 1] = { def = bd.id, facs = { act } }
			end
		end
	end
	constr = {}
	for _, p in ipairs(pend) do
		local c = constr[p[2]]
		if not c then c = { n = 0, prog = 0, active = false }; constr[p[2]] = c end
		c.n = c.n + 1
		if p[3] > c.prog then c.prog = p[3] end
		if target[p[1]] then c.active = true end
	end
	table.sort(order, function(a, b) return (UnitDefs[a.def].metalCost or 0) < (UnitDefs[b.def].metalCost or 0) end)
	roster = order
end
-- Is the factory finished?  A factory that is still under construction cannot build
-- anything yet; the queue entry waits for it (state "p").
local function FactoryReady(uid)
	if not uid or not Spring.ValidUnitID(uid) then return false end
	if Spring.GetUnitIsBeingBuilt and Spring.GetUnitIsBeingBuilt(uid) then return false end
	return true
end
-- the factory that will build this roster unit: the selected one if it can, else the
-- first that can - a factory that is finished comes first, one that is still being
-- built is only used when there is no other choice (the entry then waits for it)
local function RosterFactory(r)
	return r.facs[1]      -- the roster only holds what the active lab builds
end

-- one click on a stock-unit tile (a roster tile or an engine tile that is routed through the queue)
local function QueueClick(name, fac, button)
	local _, ctrl, _, shift = Spring.GetModKeyState()
	local id = PlainId(name)
	local ref = id .. "@" .. fac
	if button == 1 then
		Spring.SendLuaRulesMsg(string.format('vbq:add:%d:{["base"]=%q,["fac"]=%d,["id"]=%q,["plain"]=1}', shift and 5 or 1, name, fac, id))
		Snd("ui_select")
	elseif button == 2 then Spring.SendLuaRulesMsg("vbq:hold:1:" .. ref); Snd("ui_click")
	elseif button == 3 then
		if ctrl then Spring.SendLuaRulesMsg("vbq:clear:1:" .. ref)
		else Spring.SendLuaRulesMsg("vbq:rem:" .. (shift and 5 or 1) .. ":" .. ref) end
		Snd("ui_close", 0.5)
	end
end

-- the unit def a build tile stands for when it should go through the queue, else nil
local function RoutedDef(b)
	if not (b and b.c and b.c.id < 0) then return nil end
	local ud = UnitDefs[-b.c.id]
	if not ud or not ud.canMove then return nil end
	if (Spring.GetGameRulesParam("vbq_ready") or 0) ~= 1 then return nil end
	if not SelectedFactory() then return nil end
	return ud
end
-- saved settings -------------------------------------------------------------
local px, py = 12, 250          -- bottom-left corner in screen pixels
local scale, closed = 1.0, false
local MIN_SCALE, MAX_SCALE = 0.6, 2.2
-- base sizes (multiplied by scale) ---------------------------------------------
local ICON, GAP, PAD, TITLE, COLS = 54, 4, 6, 18, 5

local vsx, vsy = Spring.GetViewGeometry()
local okUI, UI = pcall(VFS.Include, "LuaUI/Headers/vb_uiscale.h.lua")
local function TextBoost() return (okUI and type(UI) == "table") and UI.TextBoost(vsy, WG.VBTextBoostOverride) or 1 end
local drag, scaling = nil, nil
local builds, toggles, orders = {}, {}, {}
local rects, panelBox, hover, hoverRect, lastH, frame = {}, nil, nil, nil, 120, 0
local hoverTpl, hoverTplRect = nil, nil   -- saved design under the mouse
local hoverRu, hoverRuRect = nil, nil      -- roster tile (stock unit) under the mouse
local hoverPlus, hoverPlusRect = false, nil   -- the [+] tile is under the mouse

-- order buttons that are left out of the panel: every wait variant, and load units
local HIDE_ORDER = {}
for _, k in ipairs({ "WAIT", "TIMEWAIT", "DEATHWAIT", "SQUADWAIT", "GATHERWAIT", "LOAD_UNITS" }) do
	if CMD[k] then HIDE_ORDER[CMD[k]] = true end
end
local function HiddenOrder(c)
	if HIDE_ORDER[c.id] then return true end
	local n = string.lower(c.name or "")
	return n:find("wait", 1, true) ~= nil or n == "load units" or n == "load"
end

-- Developer tools ("vb_dev" game option): the buttons show their hotkey
local DEV = (Spring.GetModOptions() or {}).vb_dev == "1"
local showKeys = false      -- the [Keys] button (after Q-gun): every button shows its key bind
local hintCache = {}
local function CmdAction(c)
	local a = string.lower(c.action or "")
	if a == "" then a = (string.lower(c.name or ""):gsub("%s", "")) end
	return a
end
-- the key of a command: the Voidborn order keys first (vb_hotkeys.lua), then whatever the engine has bound
local function KeyHint(c)
	if not (DEV or showKeys) then return nil end
	local act = CmdAction(c)
	local h = hintCache[act]
	if h == nil then
		h = false
		local HK = WG.VBHotkeys and WG.VBHotkeys.orders
		if HK then for k, v in pairs(HK) do if v == act then h = k:upper() end end end
		if not h and Spring.GetActionHotKeys then
			local t = Spring.GetActionHotKeys(act)
			if t and t[1] then h = (tostring(t[1]):gsub("^[Aa]ny%+", "")):upper() end
		end
		hintCache[act] = h
	end
	return h or nil
end
-- the key of a unit or structure: the engine's buildunit_<name> bind, or any Voidborn hotkey table
-- (WG.VBHotkeys.*) that maps a key to the unit's name or to buildunit_<name>
local buildKeyCache = {}
local function BuildKey(ud)
	if not ud then return nil end
	local h = buildKeyCache[ud.name]
	if h == nil then
		h = false
		local act = "buildunit_" .. ud.name
		local kind = ud.customParams and ud.customParams.kind
		local function Is(v)      -- does this hotkey value stand for this unit?
			if type(v) == "table" then for _, x in pairs(v) do if Is(x) then return true end end return false end
			return v == ud.name or v == act or v == ud.id or (kind and v == kind) or false
		end
		local VH = WG.VBHotkeys
		if type(VH) == "table" then
			for name, tbl in pairs(VH) do
				if type(tbl) == "table" and name ~= "orders" then
					-- either key -> unit ({ z = "mw_extractor" }) or unit -> key ({ mw_extractor = "z" })
					local rev = tbl[ud.name] or tbl[act] or (kind and tbl[kind])
					if type(rev) == "string" and #rev <= 12 then h = rev:upper() end
					if not h then
						for k, v in pairs(tbl) do
							if type(k) == "string" and Is(v) then h = k:upper() break end
						end
					end
				end
				if h then break end
			end
		end
		if not h and Spring.GetActionHotKeys then
			local t = Spring.GetActionHotKeys(act)
			if t and t[1] then h = (tostring(t[1]):gsub("^[Aa]ny%+", "")):upper() end
		end
		buildKeyCache[ud.name] = h
	end
	return h or nil
end

-- order buttons are coloured by what they do: combat red, movement blue, work green, the rest violet
local TINT_COMBAT = { 1.00, 0.35, 0.25 }
local TINT_MOVE   = { 0.35, 0.60, 1.00 }
local TINT_WORK   = { 0.30, 0.85, 0.45 }
local TINT_OTHER  = { 0.70, 0.50, 0.95 }
local ORDER_TINT = {
	attack = TINT_COMBAT, areaattack = TINT_COMBAT, fight = TINT_COMBAT, manualfire = TINT_COMBAT, dgun = TINT_COMBAT,
	vbdgun = TINT_COMBAT, vbdestab = TINT_COMBAT, selfd = TINT_COMBAT,
	move = TINT_MOVE, patrol = TINT_MOVE, guard = TINT_MOVE, stop = TINT_MOVE,
	repair = TINT_WORK, reclaim = TINT_WORK, resurrect = TINT_WORK, capture = TINT_WORK, restore = TINT_WORK,
}
local function OrderTint(c) return ORDER_TINT[CmdAction(c)] or TINT_OTHER end

-- energy needed to fire the special guns: the order button gets a small LED that lights up when you can afford it
local QGUN_ENERGY, DGUN_ENERGY = 1000, 500
-- extra command actions / names (lower case, letters and digits only) for each gun, if yours is called differently
local QGUN_NAMES = { qgun = true, quantumgun = true }
local DGUN_NAMES = { dgun = true, manualfire = true }
local function Plain(str) return (string.lower(str or ""):gsub("[^%w]", "")) end      -- "Q-Gun" -> "qgun"
local function Matches(list, str)
	if str == "" then return false end
	if list[str] then return true end
	for k in pairs(list) do if str:find(k, 1, true) then return true end end
	return false
end
local function GunEnergy(c)
	local a, n = Plain(c.action), Plain(c.name)
	if Matches(QGUN_NAMES, a) or Matches(QGUN_NAMES, n) then return QGUN_ENERGY end
	if Matches(DGUN_NAMES, a) or Matches(DGUN_NAMES, n) then return DGUN_ENERGY end
	return nil
end

-- shorter captions for the toggles that would not fit
local TOGGLE_LABEL = { ["fire state"] = "Fire", ["move state"] = "Move" }

local function Refresh()
	hintCache, buildKeyCache = {}, {}
	local cmds = Spring.GetActiveCmdDescs() or {}
	-- layout.lua flags every command as hidden to blank the engine's stock panel, so the engine's own
	-- "hidden" flag is useless here. The untouched list handed to LayoutButtons is kept in
	-- widgetHandler.commands: use that to find commands that are genuinely hidden.
	local realHidden = {}
	local orig = widgetHandler and widgetHandler.commands
	if type(orig) == "table" then
		for i = 1, (orig.n or #orig) do
			local oc = orig[i]
			if type(oc) == "table" and oc.hidden and oc.id then realHidden[oc.id] = true end
		end
	end
	builds, toggles, orders = {}, {}, {}
	for i = 1, #cmds do
		local c = cmds[i]
		if type(c) == "table" and c.id and not realHidden[c.id] then
			if c.id < 0 then builds[#builds + 1] = { c = c, i = i }
			elseif c.name and c.name ~= "" and c.id ~= CMD.OPT_SHIFT then
				if c.type == CMDTYPE.ICON_MODE and c.params and #c.params >= 2 then
					-- "Land mode" and "Repair level" are left out of the panel on purpose
					local nm = string.lower(c.name)
					if not (nm:find("land mode") or nm:find("repair level")) then toggles[#toggles + 1] = { c = c, i = i } end
				elseif not HiddenOrder(c) then orders[#orders + 1] = { c = c, i = i } end
			end
		end
	end
	if #orders > 0 then      -- the [Keys] button goes right after Q-gun, or at the end when there is no Q-gun
		local at = #orders + 1
		for n, o in ipairs(orders) do if GunEnergy(o.c) == QGUN_ENERGY then at = n + 1 break end end
		table.insert(orders, at, { keys = true })
	end
end

local function RefreshRoster()
	local skip = {}
	for _, b in ipairs(builds) do if b.c.id < 0 then skip[-b.c.id] = true end end
	RebuildRoster(skip)
end

function widget:SelectionChanged() RefreshRoster() end      -- another lab selected: its own roster and queue at once

-- /vbguns lists every order button with its action, and which ones get an energy LED (to find the gun's real name)
local function ListOrders()
	for _, o in ipairs(orders) do if o.c then
		local need = GunEnergy(o.c)
		Spring.Echo(string.format("[VB] order: name=%q action=%q id=%s%s", tostring(o.c.name), tostring(o.c.action), tostring(o.c.id),
			need and ("  -> LED at " .. need .. " E") or ""))
	end end
	if #orders <= 1 then Spring.Echo("[VB] no order buttons: select the unit with the guns first") end
end
function widget:Initialize()
	Spring.Echo("[VB] Build panel (" .. BUILD_TAG .. ") loaded: drag title bar to move, corner handle to scale, X to close (/vbpanel reopens)")
	if widgetHandler and widgetHandler.AddAction then
		widgetHandler:AddAction("vbpanel", function() closed = not closed return true end, nil, "t")
		widgetHandler:AddAction("vbguns", function() ListOrders() return true end, nil, "t")
	end
	Refresh()
end
function widget:TextCommand(cmd)
	if cmd == "vbpanel" then closed = not closed return true end
	if cmd == "vbguns" then ListOrders() return true end
end

function widget:GetConfigData() return { px = px, py = py, scale = scale, closed = closed, showKeys = showKeys } end
function widget:SetConfigData(d)
	if d and d.px then px, py = d.px, d.py end
	-- always open by default; ignore saved closed state
	closed = false
	if d and d.showKeys ~= nil then showKeys = d.showKeys and true or false end
	if d and d.scale then scale = math.max(MIN_SCALE, math.min(MAX_SCALE, d.scale)) end
end
function widget:ViewResize(w, h) vsx, vsy = w, h end

-- Default layout (vb_layout.lua): it places the panel (bottom left corner) and picks the scale that gives the
-- panel the column width.  Moving or scaling the panel by hand hands the layout back to the player.
local function UserTookOver() if WG.VBLayout and WG.VBLayout.Release then WG.VBLayout.Release() end end
local BASE_W = COLS * (ICON + GAP) - GAP + PAD * 2      -- panel width at scale 1
WG.VBBuildPanel = {
	Box = function()
		if closed or not panelBox then return nil end
		return px, py, panelBox.w, panelBox.h
	end,
	Place = function(x, y, w)
		px, py = x, y
		scale = math.max(MIN_SCALE, math.min(MAX_SCALE, w / BASE_W))
	end,
}

function widget:Update()
	frame = frame + 1
	if frame % 6 == 0 then Refresh() end
	if frame % 10 == 0 then RefreshRoster() end
end

local function Inside(x, y, r) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
local function Clamp(w, h)
	px = math.max(0, math.min(vsx - w, px)); py = math.max(0, math.min(vsy - h, py))
end
local function Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
local function Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end
-- the key bind in the tile's top-right corner (only while [Keys] is on)
local function TileKey(k, ix, iy, icon, s)      -- bottom-right corner of the tile
	local kw = VBFont.Width(k, 10 * s) + 5 * s
	Box(ix + icon - kw - 1, iy + 1, ix + icon - 1, iy + 13 * s, 0, 0, 0, 0.8)
	Frame(ix + icon - kw - 1, iy + 1, ix + icon - 1, iy + 13 * s, 1, 0.9, 0.5, 0.6)
	VBFont.Text(k, ix + icon - kw + 1.5 * s, iy + 3 * s, 10 * s, "o", 1, 0.9, 0.5, 1)
end
-- the key of a unit / structure tile, drawn while [Keys] is on (c: the engine command of the tile, if any)
local function DrawTileKey(ud, c, ix, iy, icon, s)
	if not showKeys then return end
	local k = BuildKey(ud) or (c and KeyHint(c))
	if k then TileKey(k, ix, iy, icon, s) return true end
end
-- the [Keys] button itself: a yellow LED shows that it is on
local function DrawKeysButton(bx, by, w, h, over, s, fs)
	local on = showKeys
	Box(bx, by, bx + w, by + h, on and 0.30 or (over and 0.20 or 0.12), on and 0.26 or (over and 0.18 or 0.11), on and 0.10 or (over and 0.14 or 0.10), 1)
	Frame(bx, by, bx + w, by + h, 1, 0.9, 0.5, on and 0.9 or (over and 0.6 or 0.3))
	Box(bx, by, bx + 3 * s, by + h, 1, 0.9, 0.5, on and 1 or 0.45)
	VBFont.Text("Keys", bx + 7 * s, by + h * 0.3, fs, "o", 1, 0.9, 0.5, on and 1 or 0.7)
	local ls = 6 * s
	local lx2, ly1 = bx + w - 4 * s, by + h / 2 - ls / 2
	Box(lx2 - ls, ly1, lx2, ly1 + ls, on and 1 or 0.3, on and 0.85 or 0.25, on and 0.3 or 0.1, 1)
end
-- energy LED of a qgun / dgun button: lit green when there is enough energy to fire, dim red when not.
-- Returns the x where the key hint has to end (left of the LED).
local function DrawGunLed(c, bx, by, w, h, s)
	local right = bx + w - 4 * s
	local need = GunEnergy(c)
	if not need then return right end
	local cur = Spring.GetTeamResources(Spring.GetMyTeamID(), "energy") or 0
	local ls = 6 * s
	local ly1 = by + h / 2 - ls / 2
	Box(right - ls - 1, ly1 - 1, right + 1, ly1 + ls + 1, 0, 0, 0, 0.8)
	if cur >= need then
		Box(right - ls - 2 * s, ly1 - 2 * s, right + 2 * s, ly1 + ls + 2 * s, 0.2, 1, 0.35, 0.25)      -- glow
		Box(right - ls, ly1, right, ly1 + ls, 0.25, 1, 0.4, 1)
	else
		Box(right - ls, ly1, right, ly1 + ls, 0.35, 0.1, 0.08, 1)
	end
	return right - ls - 4 * s
end

-- pie chart of the production progress of a saved design.
--   state: "b" building (green)   "s" stalled, not enough resources (red)   "w" waiting in the queue (blue)
--          "h" on hold (yellow, with a pause sign)   "p" pending (cyan, the factory is still being built)
local function PieVerts(cx, cy, r, frac)
	local v = { { v = { cx, cy } } }
	local steps = math.max(2, math.ceil(48 * frac))
	for i = 0, steps do
		local a = math.rad(90 - 360 * frac * i / steps)          -- starts at 12 o'clock, runs clockwise
		v[#v + 1] = { v = { cx + r * math.cos(a), cy + r * math.sin(a) } }
	end
	return v
end
local PIE_COL = { b = { 0.3, 1.0, 0.45 }, s = { 1.0, 0.4, 0.25 }, w = { 0.5, 0.65, 1.0 }, h = { 1.0, 0.85, 0.2 }, p = { 0.3, 0.85, 1.0 } }
local function DrawPie(cx, cy, r, prog, st, s)
	prog = math.max(0, math.min(1, prog or 0))
	local col = PIE_COL[st] or PIE_COL.w
	gl.Color(0, 0, 0, 0.62); gl.Shape(GL.TRIANGLE_FAN, PieVerts(cx, cy, r + 2 * s, 1))
	if prog > 0.004 then
		gl.Color(col[1], col[2], col[3], st == "h" and 0.55 or 0.9)
		gl.Shape(GL.TRIANGLE_FAN, PieVerts(cx, cy, r, math.min(prog, 0.9999)))
	end
	gl.LineWidth(1.5); gl.Color(col[1], col[2], col[3], 1); gl.Shape(GL.LINE_LOOP, (function()
		local v = {}
		for i = 0, 31 do local a = math.pi * 2 * i / 32; v[#v + 1] = { v = { cx + (r + 2 * s) * math.cos(a), cy + (r + 2 * s) * math.sin(a) } } end
		return v
	end)())
	gl.LineWidth(1)
	if st == "h" then                                            -- pause sign
		gl.Color(0, 0, 0, 0.85)
		gl.Rect(cx - r * 0.32, cy - r * 0.45, cx - r * 0.1, cy + r * 0.45)
		gl.Rect(cx + r * 0.1, cy - r * 0.45, cx + r * 0.32, cy + r * 0.45)
	elseif st == "s" then
		VBFont.Text("!", cx - 3 * s, cy - 6 * s, 14 * s, "o", 1, 1, 1, 1)
	elseif st == "p" then                                       -- a clock: the factory is still building
		gl.Color(0, 0, 0, 0.9)
		local ring = {}
		for i = 0, 15 do local a = math.pi * 2 * i / 16; ring[#ring + 1] = { v = { cx + r * 0.46 * math.cos(a), cy + r * 0.46 * math.sin(a) } } end
		gl.Shape(GL.LINE_LOOP, ring)
		gl.Rect(cx - 1 * s, cy - r * 0.46, cx + 1 * s, cy + 1 * s)
		gl.Rect(cx - 1 * s, cy - 1 * s, cx + r * 0.3, cy + 1 * s)
	elseif st == "w" and prog <= 0.004 then
		VBFont.Text("...", cx - 7 * s, cy - 4 * s, 10 * s, "o", 1, 1, 1, 1)
	else
		local txt = math.floor(prog * 100 + 0.5) .. "%"
		VBFont.Text(txt, cx - VBFont.Width(txt, 9 * s) / 2, cy - 3 * s, 9 * s, "o", 0, 0, 0, 1)
	end
end

-- hexagonal unit stats HUD ------------------------------------------------------------------------------
local statCache = {}
local C_METAL, C_ENERGY, C_TIME = { 0.65, 0.8, 1.0 }, { 1.0, 0.9, 0.3 }, { 0.85, 0.85, 0.85 }
local C_HP, C_RANGE, C_DMG, C_MISC = { 0.4, 1.0, 0.5 }, { 0.4, 0.9, 1.0 }, { 1.0, 0.45, 0.35 }, { 0.8, 0.7, 1.0 }

local function Num(n)
	n = tonumber(n) or 0
	if n >= 10000 then return string.format("%.1fk", n / 1000) end
	if math.abs(n - math.floor(n + 0.5)) < 0.05 then return string.format("%d", math.floor(n + 0.5)) end
	return string.format("%.1f", n)
end

-- raw numbers for one unit def (shared by the stat rows and the radar chart)
local function Metrics(ud)
	local m = { hp = ud.health or 0, speed = ud.speed or 0, sight = ud.losRadius or 0, cost = ud.metalCost or 0,
		range = 0, volley = 0, dps = 0, nW = 0 }
	local arm = (Game and Game.armorTypes and Game.armorTypes.default) or 0
	for _, w in ipairs(ud.weapons or {}) do
		local wd = w.weaponDef and WeaponDefs[w.weaponDef]
		if wd then
			m.nW = m.nW + 1
			local d = wd.damages and (wd.damages[arm] or wd.damages[0] or wd.damages[1]) or 0
			local shots = (wd.projectiles or 1) * (wd.salvoSize or 1)
			local rl = math.max(wd.reload or 1, 0.03)
			m.range = math.max(m.range, wd.range or 0)
			m.volley = m.volley + d * shots
			m.dps = m.dps + d * shots / rl
			m.reload = m.reload and math.min(m.reload, rl) or rl
		end
	end
	return m
end

-- spec (optional): a forge design.  Its changes are applied on top of the base unit def, exactly like the
-- gadget does it when the unit is built: hp and sight are absolute, speed/range/dmg/reload are multipliers.
-- pr (optional): the price of the design ({ metal, energy, seconds }) from the shared cost rules.
local function BuildStats(ud, spec, pr)
	local rows = {}
	local function Add(label, value, col) rows[#rows + 1] = { label, value, col } end
	local m = Metrics(ud)
	local metal, energy, btime = ud.metalCost, ud.energyCost, ud.buildTime
	if spec then
		local function Pos(v) v = tonumber(v); return v and v > 0 and v or nil end
		if Pos(spec.hp) then m.hp = Pos(spec.hp) end
		if Pos(spec.speed) then m.speed = m.speed * Pos(spec.speed) end
		if Pos(spec.sight) then m.sight = Pos(spec.sight) end
		if Pos(spec.range) then m.range = m.range * Pos(spec.range) end
		local dm, rl = Pos(spec.dmg) or 1, Pos(spec.reload) or 1
		m.volley = m.volley * dm
		m.dps = m.dps * dm / rl
		if m.reload then m.reload = math.max(0.03, m.reload * rl) end
		if pr then metal, energy, btime = pr.metal, pr.energy, (pr.seconds or 0) * BUILD_POWER end
		m.cost = metal
	end
	Add("METAL", Num(metal), C_METAL)
	Add("ENERGY", Num(energy), C_ENERGY)
	Add("BUILD TIME", Num(btime), C_TIME)
	Add("HEALTH", Num(m.hp), C_HP)
	if m.speed > 0 then Add("SPEED", Num(m.speed), C_MISC) end
	if m.sight > 0 then Add("SIGHT", Num(m.sight), C_RANGE) end
	if (ud.radarRadius or 0) > 0 then Add("RADAR", Num(ud.radarRadius), C_RANGE) end
	if m.nW > 0 then
		Add("RANGE", Num(m.range), C_RANGE)
		Add("DAMAGE", Num(m.volley), C_DMG)
		Add("DPS", Num(m.dps), C_DMG)
		Add("RELOAD", Num(m.reload) .. "s", C_TIME)
		if m.nW > 1 then Add("WEAPONS", tostring(m.nW), C_MISC) end
	end
	-- economy / support
	if (ud.metalMake or 0) > 0 then Add("METAL +/S", Num(ud.metalMake), C_METAL) end
	if (ud.extractsMetal or 0) > 0 then Add("EXTRACTS", Num(ud.extractsMetal * 1000), C_METAL) end
	if (ud.energyMake or 0) > 0 then Add("ENERGY +/S", Num(ud.energyMake), C_ENERGY) end
	if (ud.energyUpkeep or 0) > 0 then Add("UPKEEP", Num(ud.energyUpkeep), C_ENERGY) end
	if (ud.metalStorage or 0) > 0 then Add("M STORAGE", Num(ud.metalStorage), C_METAL) end
	if (ud.energyStorage or 0) > 0 then Add("E STORAGE", Num(ud.energyStorage), C_ENERGY) end
	if (ud.buildSpeed or 0) > 0 then Add("BUILD POWER", Num(ud.buildSpeed), C_MISC) end
	return rows, m
end

-- key: unitDefID for a stock unit, or "t:<id>#<rev>" for a forge design (the rev changes when a design is edited)
local function GetStats(key, ud, spec, pr)
	local st = statCache[key]
	if st == nil then
		local ok, rows, m = pcall(BuildStats, ud, spec, pr)
		st = ok and { rows = rows, m = m } or false
		if not ok then Spring.Echo("[VB] hex stats error: " .. tostring(rows)) end
		statCache[key] = st
	end
	return st
end

-- radar chart: six axes, each unit is scaled against the strongest Voidborn unit on that axis (sqrt scale so small
-- values stay visible). Maxima are computed once from every def that belongs to a faction.
local AXES = { { "hp", "HP" }, { "speed", "SPD" }, { "sight", "SGT" }, { "range", "RNG" }, { "dps", "DPS" }, { "cost", "COST" } }
local axisMax
local function AxisMax()
	if axisMax then return axisMax end
	axisMax = {}
	for _, a in ipairs(AXES) do axisMax[a[1]] = 1 end
	for _, ud in pairs(UnitDefs) do
		local cp = ud.customParams
		if cp and cp.faction then
			local ok, m = pcall(Metrics, ud)
			if ok then for _, a in ipairs(AXES) do if (m[a[1]] or 0) > axisMax[a[1]] then axisMax[a[1]] = m[a[1]] end end end
		end
	end
	return axisMax
end

local function RadarPoint(cx, cy, r, i)
	local ang = math.rad(90 - 60 * (i - 1))
	return cx + r * math.cos(ang), cy + r * math.sin(ang)
end

local function DrawRadar(m, cx, cy, R, s)
	local mx = AxisMax()
	local ring = function(f)
		local v = {}
		for i = 1, 6 do local x, y = RadarPoint(cx, cy, R * f, i); v[i] = { v = { x, y } } end
		return v
	end
	-- grid
	gl.LineWidth(1)
	for _, f in ipairs({ 0.25, 0.5, 0.75, 1.0 }) do
		gl.Color(0.85, 0.65, 0.2, f == 1.0 and 0.5 or 0.22); gl.Shape(GL.LINE_LOOP, ring(f))
	end
	gl.Color(0.85, 0.65, 0.2, 0.22)
	for i = 1, 6 do
		local x, y = RadarPoint(cx, cy, R, i)
		gl.Shape(GL.LINES, { { v = { cx, cy } }, { v = { x, y } } })
	end
	-- unit profile
	local poly, pts = { { v = { cx, cy } } }, {}
	for i, a in ipairs(AXES) do
		local f = math.min(1, math.sqrt(math.max(0, (m[a[1]] or 0)) / mx[a[1]]))
		local x, y = RadarPoint(cx, cy, R * f, i)
		poly[#poly + 1] = { v = { x, y } }; pts[i] = { x, y }
	end
	poly[#poly + 1] = poly[2]
	gl.Color(1.0, 0.8, 0.3, 0.28); gl.Shape(GL.TRIANGLE_FAN, poly)
	local loop = {}
	for i = 1, 6 do loop[i] = { v = pts[i] } end
	gl.LineWidth(2); gl.Color(1.0, 0.85, 0.35, 0.95); gl.Shape(GL.LINE_LOOP, loop); gl.LineWidth(1)
	gl.Color(1, 1, 1, 0.95)
	for i = 1, 6 do gl.Rect(pts[i][1] - 2 * s, pts[i][2] - 2 * s, pts[i][1] + 2 * s, pts[i][2] + 2 * s) end
	-- labels
	for i, a in ipairs(AXES) do
		local x, y = RadarPoint(cx, cy, R + 11 * s, i)
		VBFont.Text(a[2], x, y - 4 * s, 9 * s, "oc", 0.7, 0.8, 0.9, 1)
	end
end

-- hexagon (flat top/bottom, pointed left/right) as a convex polygon
local function HexVerts(x1, y1, x2, y2, k)
	local ym = (y1 + y2) / 2
	return { { v = { x1 + k, y2 } }, { v = { x2 - k, y2 } }, { v = { x2, ym } },
		{ v = { x2 - k, y1 } }, { v = { x1 + k, y1 } }, { v = { x1, ym } } }
end

-- extra (optional) = { key, spec, price, name, sub } turns it into the panel of a forge design
local function DrawHexPanel(ud, icon, extra)
	local st
	if extra then st = GetStats(extra.key, ud, extra.spec, extra.price) else st = GetStats(ud.id, ud) end
	if not st then return end
	local rows = st.rows
	local s = math.max(0.8, scale)
	local rowH, W = 15 * s, 250 * s
	local headH = 46 * s
	local R = 52 * s                                      -- radar radius
	local radarH = 2 * R + 40 * s                         -- room for the chart, its labels and a caption
	local H = headH + #rows * rowH + radarH + 22 * s
	local k = H * 0.12                                    -- how far the left/right points stick out
	-- beside the build panel, vertically centred on the hovered icon; flip to the left side if no room
	local cy = (icon[2] + icon[4]) / 2
	local drawerW = (WG.VBCensus and WG.VBCensus.Width and WG.VBCensus.Width()) or 0      -- the census drawer slides out on this side
	local hx1 = px + (panelBox and panelBox.w or 0) + 10 + drawerW
	if hx1 + W > vsx then hx1 = px - 10 - W end
	local hy1 = math.max(4, math.min(vsy - H - 4, cy - H / 2))
	local hx2, hy2 = hx1 + W, hy1 + H

	gl.Color(0.05, 0.05, 0.09, 0.93); gl.Shape(GL.TRIANGLE_FAN, HexVerts(hx1, hy1, hx2, hy2, k))
	gl.LineWidth(2); gl.Color(0.85, 0.65, 0.2, 0.95); gl.Shape(GL.LINE_LOOP, HexVerts(hx1, hy1, hx2, hy2, k))
	local i2 = 5 * s                                      -- thin inner hexagon
	gl.LineWidth(1); gl.Color(0.85, 0.65, 0.2, 0.35); gl.Shape(GL.LINE_LOOP, HexVerts(hx1 + i2, hy1 + i2, hx2 - i2, hy2 - i2, k - i2 * 0.3))
	gl.LineWidth(1)

	local cx = (hx1 + hx2) / 2
	local name = (extra and extra.name) or ud.humanName or ud.name or "?"
	VBFont.Text(name, cx, hy2 - 22 * s, 15 * s, "oc", 1, 0.92, 0.65, 1)
	local desc = (extra and extra.sub) or ud.tooltip or ""
	if #desc > 0 then
		if #desc > 34 then desc = desc:sub(1, 33) .. "." end
		VBFont.Text(desc, cx, hy2 - 38 * s, 9 * s, "oc", 0.7, 0.7, 0.8, 1)
	end
	gl.Color(0.85, 0.65, 0.2, 0.5); gl.Rect(hx1 + k + 6 * s, hy2 - headH + 3 * s, hx2 - k - 6 * s, hy2 - headH + 4 * s)

	local lx, rx = hx1 + k + 10 * s, hx2 - k - 10 * s
	local y = hy2 - headH - rowH + 3 * s
	for _, r in ipairs(rows) do
		VBFont.Text(r[1], lx, y, 11 * s, "o", 0.62, 0.62, 0.72, 1)
		VBFont.Text(r[2], rx, y, 12 * s, "or", r[3][1], r[3][2], r[3][3], 1)
		y = y - rowH
	end

	-- radar profile below the rows
	local sepY = y + rowH - 4 * s
	gl.Color(0.85, 0.65, 0.2, 0.5); gl.Rect(hx1 + k + 6 * s, sepY, hx2 - k - 6 * s, sepY + 1)
	VBFont.Text("PROFILE", cx, sepY - 11 * s, 9 * s, "oc", 0.85, 0.65, 0.2, 1)
	if st.m then DrawRadar(st.m, cx, hy1 + 14 * s + (radarH - 14 * s) / 2 - 6 * s, R, s) end
end

-- per lab: how many units are queued on its line and the most telling state (s stalled > b building > p pending)
local STATE_RANK = { s = 3, b = 2, p = 1 }
local function LabInfo(queue)
	local info = {}
	for k, e in pairs(queue) do
		if type(k) == "string" and k:find("@", 1, true) and (e.fac or 0) > 0 then
			local li = info[e.fac]
			if not li then li = { n = 0 }; info[e.fac] = li end
			li.n = li.n + e.n
			if (STATE_RANK[e.st] or 0) > (STATE_RANK[li.st] or 0) then li.st = e.st end
		end
	end
	return info
end

local function DrawClosedTab()
	local s = 22
	local x1, y1 = px, math.max(0, math.min(vsy - s, py + lastH - s))
	rects = { { x1, y1, x1 + s, y1 + s, open = true } }
	panelBox = { w = s, h = s }
	Box(x1, y1, x1 + s, y1 + s, 0.06, 0.06, 0.09, 0.9); Frame(x1, y1, x1 + s, y1 + s, 0.85, 0.65, 0.2, 0.9)
	VBFont.Text("+", x1 + 7, y1 + 6, 14, "o", 1, 0.9, 0.5, 1)
end

-- the order buttons (with the gun LEDs and [Keys]) and the toggle buttons under the grid; L = layout from DrawScreen
-- (a separate function: DrawScreen is close to Lua 5.1's 60-upvalue limit)
local function DrawButtons(L)
	local activeID, fs, gap, gridBottom, mx, my, obH, obW, ocols, orows, pad, s, tbH, tbW, tcols, x1
		= L.activeID, L.fs, L.gap, L.gridBottom, L.mx, L.my, L.obH, L.obW, L.ocols, L.orows, L.pad, L.s, L.tbH, L.tbW, L.tcols, L.x1
	-- order buttons
	local oy = gridBottom - 4 * s
	for n, o in ipairs(orders) do
		local col, row = (n - 1) % ocols, math.floor((n - 1) / ocols)
		local bx, by = x1 + pad + col * (obW + gap), oy - (row + 1) * (obH + gap) + gap
		if o.keys then      -- [Keys]: shows the key bind on every button while it is on
			local r = { bx, by, bx + obW, by + obH, keys = true }
			rects[#rects + 1] = r
			DrawKeysButton(bx, by, obW, obH, Inside(mx, my, r), s, fs)
		else
		local r = { bx, by, bx + obW, by + obH, cmd = o }
		rects[#rects + 1] = r
		local over = Inside(mx, my, r); if over then hover = o end
		if o.c.id == activeID then Box(bx, by, bx + obW, by + obH, 0.5, 0.4, 0.1, 1)
		else
			local tn = OrderTint(o.c)
			local k = over and 0.32 or 0.20
			Box(bx, by, bx + obW, by + obH, (over and 0.14 or 0.10) + tn[1] * k, (over and 0.14 or 0.10) + tn[2] * k, (over and 0.18 or 0.12) + tn[3] * k, 1)
		end
		local tn = OrderTint(o.c)
		Box(bx, by, bx + 3 * s, by + obH, tn[1], tn[2], tn[3], o.c.disabled and 0.4 or 1)      -- colour bar on the left edge
		VBFont.Text(string.sub(o.c.name, 1, 13), bx + 7 * s, by + obH * 0.3, fs, "o", 1, 1, 1, o.c.disabled and 0.4 or 1)
		local hkRight = DrawGunLed(o.c, bx, by, obW, obH, s)      -- qgun / dgun: energy LED
		local hk = KeyHint(o.c)
		if hk then VBFont.Text(hk, hkRight - VBFont.Width(hk, fs * 0.85), by + obH * 0.3, fs * 0.85, "o", 1, 0.9, 0.5, 0.9) end
		end
	end
	-- toggle buttons (fire state, move state, repeat, on/off, land...) with state LEDs
	local ty = oy - (orows > 0 and (orows * (obH + gap)) or 0) - 4 * s
	for n, t in ipairs(toggles) do
		local col, row = (n - 1) % tcols, math.floor((n - 1) / tcols)
		local bx, by = x1 + pad + col * (tbW + gap), ty - (row + 1) * (tbH + gap) + gap
		local r = { bx, by, bx + tbW, by + tbH, cmd = t, toggle = true }
		rects[#rects + 1] = r
		local over = Inside(mx, my, r); if over then hover = t end
		Box(bx, by, bx + tbW, by + tbH, over and 0.25 or 0.15, over and 0.25 or 0.15, over and 0.35 or 0.22, 1)
		-- what kind of toggle is this?  c.params holds the plain state VALUES, so the
		-- kind has to be recognised from the command id / name, not from the params.
		local nm = string.lower(t.c.name or "")
		local kind = "generic"
		if nm:find("repeat") then kind = "repeat"
		elseif nm:find("move state") or nm:find("movestate") then kind = "move"
		elseif nm:find("fire state") or nm:find("firestate") then kind = "fire"
		elseif nm:find("land") then kind = "land"
		elseif nm:find("cloak") then kind = "cloak" end
		-- label + colour of one state: repeat ON=green / OFF=red, move AIR=green /
		-- LAND=blue, fire ALWAYS=red / HOLD=yellow / RETURN=cyan, land TAKEOFF=green
		local function StateStyle(k)
			if kind == "repeat" then
				if k == 0 then return "OFF", 0.95, 0.15, 0.15 end
				return "ON", 0.15, 0.90, 0.20
			elseif kind == "move" then
				if k == 0 then return "LAND", 0.25, 0.50, 1.00 end
				return "AIR", 0.15, 0.90, 0.20
			elseif kind == "fire" then
				if k == 0 then return "RETURN", 0.25, 0.75, 1.00 end
				if k == 1 then return "HOLD", 1.00, 0.85, 0.20 end
				return "ALWAYS", 1.00, 0.30, 0.15
			elseif kind == "land" then
				if k == 0 then return "LAND", 0.25, 0.50, 1.00 end
				return "TAKEOFF", 0.15, 0.90, 0.20
			elseif kind == "cloak" then
				if k == 0 then return "OFF", 0.65, 0.65, 0.75 end
				return "ON", 0.30, 0.85, 1.00
			end
			return tostring(k), 0.65, 0.65, 0.75
		end
		local nstates, cur = #t.c.params - 1, tonumber(t.c.params[1]) or 0
		if nstates < 1 then nstates = 1 end
		if cur < 0 then cur = 0 end
		if cur > nstates - 1 then cur = nstates - 1 end
		-- caption: "<NAME>: <STATE>", coloured by the state that is active
		local curLbl, cr, cg, cb = StateStyle(cur)
		local label = TOGGLE_LABEL[nm] or string.sub(t.c.name or "", 1, 12)
		VBFont.Text(label .. ": " .. curLbl,
			bx + 4 * s, by + tbH * 0.42, fs, "o", cr, cg, cb, 1)
		local hk = KeyHint(t.c)
		if hk then VBFont.Text(hk, bx + tbW - VBFont.Width(hk, fs * 0.85) - 4 * s, by + tbH * 0.42, fs * 0.85, "o", 1, 0.9, 0.5, 0.9) end
		-- one LED per state, coloured by what that state means; the active one is
		-- bright, the others are dimmed
		local lw = 7 * s
		for k = 0, nstates - 1 do
			local lx = bx + 4 * s + k * (lw + 2 * s)
			local _, r, g, b = StateStyle(k)
			if k == cur then Box(lx, by + 2 * s, lx + lw, by + 5 * s, r, g, b, 1)
			else Box(lx, by + 2 * s, lx + lw, by + 5 * s, r * 0.3, g * 0.3, b * 0.3, 1) end
		end
	end
end

-- the info box above the panel for whatever is under the mouse (a separate function: DrawScreen is at Lua 5.1's 60-upvalue limit)
local function DrawHoverInfo(F, queue, TplQ, x1, y2, w, s)
	-- hover info of the [+] tile: what it does, or why it is locked
	if hoverPlus then
		local tw, l1, l2, l3, cr, cg, cb
		if T2Locked() then
			local c, prog = UpgradeCost(), UpgradeProgress()
			l1 = "Unit forge - LOCKED"
			l2 = "Upgrade a factory to Tier 2 first: select your factory and press [Upgrade T2]."
			l3 = prog and string.format("Upgrade under way: %d%%   (%d metal + %d energy)", math.floor(prog * 100 + 0.5), c.metal, c.energy)
				or string.format("Cost: %d metal + %d energy.  Custom units and saved designs unlock when it is done.", c.metal, c.energy)
			cr, cg, cb = 1, 0.7, 0.3
		else
			l1 = "Unit forge"
			l2 = "Design a custom unit: shape, stats, weapons."
			l3 = "Saved designs appear as tiles here and are built through your factories' production lines."
			cr, cg, cb = 0.6, 1, 0.75
		end
		tw = math.max(w, VBFont.Width(l3, 9) + 14, VBFont.Width(l2, 10) + 14, VBFont.Width(l1, 11) + 14)
		Box(x1, y2 + 2, x1 + tw, y2 + 46, 0.06, 0.06, 0.09, 0.94)
		Frame(x1, y2 + 2, x1 + tw, y2 + 46, cr, cg, cb, 0.8)
		VBFont.Text(l1, x1 + 6, y2 + 32, 11, "o", cr, cg, cb, 1)
		VBFont.Text(l2, x1 + 6, y2 + 19, 10, "o", 1, 0.9, 0.6, 1)
		VBFont.Text(l3, x1 + 6, y2 + 7, 9, "o", 0.6, 0.65, 0.75, 1)
	-- hover info for a saved design: price, state of its production and the mouse controls
	elseif hoverTpl then
		local t = F.templates[hoverTpl] or {}
		local pr = F.Price and F.Price(t)
		local q = TplQ(hoverTpl)
		local l1 = hoverTpl .. "   (base: " .. tostring(t.base) .. ")"
		local l2 = pr and string.format("metal %d   energy %d   time %ds", math.floor(pr.metal + 0.5), math.floor(pr.energy + 0.5), math.floor(pr.build + 0.5)) or "price unknown"
		local st = q and ({ b = "building", s = "STALLED: not enough metal/energy", w = "waiting", h = "ON HOLD",
			p = "PENDING: the factory is still being built or upgraded" })[q.st] or nil
		if q then l2 = l2 .. "   |   " .. math.floor(q.prog * 100 + 0.5) .. "%  " .. (st or "") end
		local l3 = "click +1 (shift +5)   right-click -1   middle: hold   ctrl+click: edit   red x / ctrl+right: delete"
		if T2Locked() then l3 = "LOCKED: upgrade your factory to Tier 2 first (select it, press [Upgrade T2])" end
		local tw = math.max(w, VBFont.Width(l3, 9) + 14, VBFont.Width(l2, 10) + 14, VBFont.Width(l1, 11) + 14)
		Box(x1, y2 + 2, x1 + tw, y2 + 46, 0.06, 0.06, 0.09, 0.94)
		Frame(x1, y2 + 2, x1 + tw, y2 + 46, 0.35, 0.9, 1, 0.8)
		VBFont.Text(l1, x1 + 6, y2 + 32, 11, "o", 0.6, 0.95, 1, 1)
		VBFont.Text(l2, x1 + 6, y2 + 19, 10, "o", 1, 0.9, 0.6, 1)
		VBFont.Text(l3, x1 + 6, y2 + 7, 9, "o", 0.6, 0.65, 0.75, 1)
		-- the same hexagonal stats panel with the radar profile that the stock units get
		local bud = t.base and UnitDefNames[t.base]
		if bud and hoverTplRect then
			DrawHexPanel(bud, hoverTplRect, { key = "t:" .. hoverTpl .. "#" .. tostring(F.rev or 0),   -- rev changes when a design is edited
				spec = t, price = pr,
				name = (t.name and t.name ~= "" and t.name) or hoverTpl,
				sub = "custom design, base: " .. (bud.humanName or bud.name) })
		end
	elseif hoverRu then
		local rd = UnitDefs[hoverRu.def]
		local fac = RosterFactory(hoverRu)
		local pr = F.Price and F.Price({ base = rd.name })
		local q = fac and queue[PlainId(rd.name) .. "@" .. fac]
		local l1 = (rd.humanName or rd.name) .. "   (built by your " .. ((fac and FactoryDef(fac) and (FactoryDef(fac).humanName or FactoryDef(fac).name)) or "factory") .. ")"
		local l2 = pr and string.format("metal %d   energy %d   time %.1fs", math.floor(pr.metal + 0.5), math.floor(pr.energy + 0.5), pr.build) or "price unknown"
		local st = q and ({ b = "building", s = "STALLED: not enough metal/energy", w = "waiting", h = "ON HOLD",
			p = "PENDING: the factory is still being built or upgraded" })[q.st] or nil
		if q then l2 = l2 .. "   |   " .. math.floor(q.prog * 100 + 0.5) .. "%  " .. (st or "") end
		local l3 = "click +1 (shift +5)   right-click -1   middle: hold   ctrl+right: cancel line"
		local tw = math.max(w, VBFont.Width(l3, 9) + 14, VBFont.Width(l2, 10) + 14, VBFont.Width(l1, 11) + 14)
		Box(x1, y2 + 2, x1 + tw, y2 + 46, 0.06, 0.06, 0.09, 0.94)
		Frame(x1, y2 + 2, x1 + tw, y2 + 46, 0.85, 0.65, 0.2, 0.8)
		VBFont.Text(l1, x1 + 6, y2 + 32, 11, "o", 1, 0.92, 0.65, 1)
		VBFont.Text(l2, x1 + 6, y2 + 19, 10, "o", 1, 0.9, 0.6, 1)
		VBFont.Text(l3, x1 + 6, y2 + 7, 9, "o", 0.6, 0.65, 0.75, 1)
	elseif hover then
		local c = hover.c
		if c.id < 0 and UnitDefs[-c.id] and hoverRect then
			DrawHexPanel(UnitDefs[-c.id], hoverRect)
		else
			local line = c.tooltip ~= "" and c.tooltip or c.name
			if line then
				Box(x1, y2 + 2, x1 + math.max(w, VBFont.Width(line, 11) + 12), y2 + 20, 0.06, 0.06, 0.09, 0.9)
				VBFont.Text(line, x1 + 6, y2 + 7, 11, "o", 1, 1, 1, 1)
			end
		end
	end
end

function widget:DrawScreen()
	rects = {}
	if closed then DrawClosedTab() return end
	-- NB: the panel is ALWAYS shown (even with nothing selected): it holds the [+] tile that opens the forge
	-- and the tiles of the designs saved in it.
	local F = ForgeRef()
	local tplIds = F.TemplateIds()
	local queue = F.ReadQueue()

	local s = scale
	local tb = TextBoost()                                   -- 116 % on HD screens: bigger text and buttons, same panel width
	local icon, gap, pad, title = ICON * s, GAP * s, PAD * s, math.max(16, TITLE * s * tb)
	local fs = math.max(9, 10 * s * tb)
	local gridW = COLS * (icon + gap) - gap
	-- sort every tile into its category; the four sections are all shown at once
	local act = ActiveLab()
	designLab = DesignLab(act)
	local cats = { E = {}, C = {}, U = {}, B = {} }
	local actDef = act and FactoryDef(act)
	local anySel = (Spring.GetSelectedUnitsCount and Spring.GetSelectedUnitsCount() or #(Spring.GetSelectedUnits() or {})) > 0
	if anySel then
	for _, b in ipairs(builds) do
		local bd = UnitDefs[-b.c.id]
		-- with several labs selected the engine lists the units of all of them: keep the active lab's
		local keep = true
		if bd and bd.canMove and actDef and SelectedFactory() then keep = CanBuild(actDef, bd.id) end
		if keep then local c = cats[CatOf(bd)]; c[#c + 1] = { kind = "build", b = b } end
	end
	for _, ru in ipairs(roster) do local c = cats[CatOf(UnitDefs[ru.def])]; c[#c + 1] = { kind = "ru", ru = ru } end
	for _, tid in ipairs(tplIds) do
		local t = F.templates[tid] or {}
		local c = cats[CatOf(t.base and UnitDefNames[t.base])]
		c[#c + 1] = { kind = "tpl", tid = tid }
	end
	local combat = cats.C; combat[#combat + 1] = { kind = "plus" }          -- the [+] tile opens the forge: designs are fighters
	end   -- anySel: with nothing selected the grid only shows "Select a unit to load menu"
	local hintH = anySel and 0 or 22 * s * tb
	local LEG, chipH = 12 * s * tb, 17 * s * tb
	local labsH = #labs > 0 and (math.ceil(#labs / 3) * (chipH + gap) + 2 * s) or 0
	local nflat = 0
	for _, c in ipairs(CATS) do nflat = nflat + #cats[c.id] end
	local gridH = LEG + math.ceil(nflat / COLS) * (icon + gap) + 3 * s + hintH      -- ONE grid: a one-line legend + the tiles
	local tcols, ocols = 2, 3
	local trows, orows = math.ceil(#toggles / tcols), math.ceil(#orders / ocols)
	local tbW, tbH = (gridW - (tcols - 1) * gap) / tcols, 20 * s * tb
	local obW, obH = (gridW - (ocols - 1) * gap) / ocols, 18 * s * tb
	local w = gridW + pad * 2
	local h = title + pad + labsH + gridH
		+ (orows > 0 and (orows * (obH + gap) + 4 * s) or 0)
		+ (trows > 0 and (trows * (tbH + gap) + 4 * s) or 0) + pad + 8 * s
	if scaling then py = scaling.top - h end
	Clamp(w, h)
	panelBox, lastH = { w = w, h = h }, h
	local x1, y1, x2, y2 = px, py, px + w, py + h

	Box(x1, y1, x2, y2, 0.06, 0.06, 0.09, 0.88); Frame(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.9)
	-- title bar: drag handle + close button
	Box(x1, y2 - title, x2, y2, 0.14, 0.12, 0.2, 1)
	VBFont.Text("BUILD / ORDERS  " .. BUILD_TAG, x1 + pad, y2 - title + title * 0.28, fs, "o", 0.9, 0.85, 0.7, 1)
	rects[#rects + 1] = { x1, y2 - title, x2 - title, y2, drag = true }
	local mx, my = Spring.GetMouseState()
	local xr = { x2 - title, y2 - title, x2, y2, close = true }
	rects[#rects + 1] = xr
	Box(xr[1], xr[2], xr[3], xr[4], Inside(mx, my, xr) and 0.6 or 0.3, 0.1, 0.1, 1)
	VBFont.Text("x", xr[1] + title * 0.33, xr[2] + title * 0.25, fs + 2, "o", 1, 1, 1, 1)
	-- scale handle (bottom-right corner)
	local hs = 12 * s
	local hr = { x2 - hs, y1, x2, y1 + hs, scale = true }
	rects[#rects + 1] = hr
	gl.Color(0.85, 0.65, 0.2, Inside(mx, my, hr) and 1 or 0.7)
	for k = 1, 3 do gl.Rect(x2 - 2 - k * 3 * s, y1 + 2, x2 - 2, y1 + 2 + k * 3 * s - 2 * s) end

	local _, activeID = Spring.GetActiveCommand()
	hover, hoverRect = nil, nil
	hoverPlus, hoverPlusRect = false, nil
	hoverRu, hoverRuRect = nil, nil
	hoverTpl, hoverTplRect = nil, nil
	local top = y2 - title - pad
	local function TplQ(tid)      -- the queue entry of a design on the lab that builds designs
		if designLab then return queue[tid .. "@" .. designLab] end
		return queue[tid]
	end

	-- lab chips: each lab has its own roster and queue; the active one is shown below, click a chip to switch
	local cursor = top
	if #labs > 0 then
		local labInfo = LabInfo(queue)
		local lcols = math.min(#labs, 3)
		local cw = (gridW - (lcols - 1) * gap) / lcols
		for i, l in ipairs(labs) do
			local colI, row = (i - 1) % lcols, math.floor((i - 1) / lcols)
			local cx1, cy2 = x1 + pad + colI * (cw + gap), top - row * (chipH + gap)
			local r = { cx1, cy2 - chipH, cx1 + cw, cy2, lab = l.uid }
			rects[#rects + 1] = r
			local over, isAct = Inside(mx, my, r), (l.uid == act)
			local bc = l.tier >= 2 and { 0.35, 0.9, 1.0 } or { 0.85, 0.65, 0.2 }
			Box(r[1], r[2], r[3], r[4], isAct and 0.2 or (over and 0.17 or 0.1), isAct and 0.18 or (over and 0.17 or 0.1), isAct and 0.28 or (over and 0.24 or 0.15), 1)
			Frame(r[1], r[2], r[3], r[4], bc[1], bc[2], bc[3], isAct and 1 or 0.5)
			if isAct then Box(r[1], r[2], r[3], r[2] + 2 * s, bc[1], bc[2], bc[3], 1) end
			local li = labInfo[l.uid]
			local led = { 0.3, 0.3, 0.35 }
			if li and li.st == "s" then led = { 1, 0.3, 0.25 } elseif li and li.st == "b" then led = { 0.3, 1, 0.45 } elseif li and li.st == "p" then led = { 0.3, 0.85, 1 } end
			Box(r[1] + 3 * s, r[2] + chipH / 2 - 2 * s, r[1] + 7 * s, r[2] + chipH / 2 + 2 * s, led[1], led[2], led[3], 1)
			VBFont.Text("LAB " .. l.n .. " T" .. l.tier, r[1] + 10 * s, r[2] + chipH * 0.28, fs, "o", bc[1], bc[2], bc[3], isAct and 1 or 0.75)
			if li and li.n > 0 then VBFont.Text("x" .. li.n, r[3] - 3 * s, r[2] + chipH * 0.28, fs, "or", 1, 1, 1, 1) end
		end
		cursor = top - labsH
	end

	-- one compact grid, sorted by category (economy, combat, utility, build); a one-line legend with the counts,
	-- and every tile carries a small coloured tag of its category
	local flat = {}
	local cw4 = gridW / #CATS
	for k, c in ipairs(CATS) do
		local col, lx = c.col, x1 + pad + (k - 1) * cw4
		Box(lx, cursor - LEG + 2, lx + 5 * s, cursor - 2, col[1], col[2], col[3], 1)
		VBFont.Text(c.name, lx + 8 * s, cursor - LEG + 3 * s, math.max(8, 8 * s * tb), "o", col[1], col[2], col[3], 1)
		for _, t in ipairs(cats[c.id]) do t.cat = c; flat[#flat + 1] = t end
	end
	cursor = cursor - LEG
	for i, t in ipairs(flat) do
		local colI, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		t.ix = x1 + pad + colI * (icon + gap)
		t.iy = cursor - (row + 1) * (icon + gap) + gap
	end
	cursor = cursor - math.ceil(#flat / COLS) * (icon + gap) - 3 * s
	if not anySel then
		local msg, mfs = "Select unit to load menu", math.max(9, 11 * s * tb)
		local mx1, my1 = x1 + pad, cursor - hintH
		Box(mx1, my1, mx1 + gridW, cursor, 0.09, 0.09, 0.13, 1)
		Frame(mx1, my1, mx1 + gridW, cursor, 0.85, 0.65, 0.2, 0.45)
		VBFont.Text(msg, mx1 + gridW / 2 - VBFont.Width(msg, mfs) / 2, my1 + hintH / 2 - mfs * 0.35, mfs, "o", 0.9, 0.85, 0.7, 1)
		cursor = cursor - hintH
	end
	local gridBottom = cursor

	for _, t in ipairs(flat) do
		local ix, iy, cc = t.ix, t.iy, t.cat.col
		if t.kind == "build" then
			-- engine build tiles: structures, and the units of the selected lab
			local b = t.b
			local r = { ix, iy, ix + icon, iy + icon, cmd = b }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r); if over then hover, hoverRect = b, r end
			gl.Color(1, 1, 1, b.c.disabled and 0.35 or 1)
			gl.Texture("#" .. (-b.c.id)); gl.TexRect(ix, iy, ix + icon, iy + icon); gl.Texture(false)
			if b.c.id == activeID then Frame(ix, iy, ix + icon, iy + icon, 1, 0.9, 0.3, 1)
			elseif over then Frame(ix, iy, ix + icon, iy + icon, 1, 1, 1, 0.9)
			else Frame(ix, iy, ix + icon, iy + icon, cc[1], cc[2], cc[3], 0.8) end
			local keyed = DrawTileKey(UnitDefs[-b.c.id], b.c, ix, iy, icon, s)      -- [Keys] on: the key, bottom right
			local cnt = b.c.params and b.c.params[1]
			if cnt and tonumber(cnt) and tonumber(cnt) > 0 then VBFont.Text(cnt, ix + icon - 4 * s, iy + (keyed and 15 or 3) * s, 12 * s, "or", 1, 1, 1, 1) end
			-- production state of a stock unit that is going through the queue (of the active lab)
			local qd = UnitDefs[-b.c.id]
			local selFac = qd and qd.canMove and act
			local q = selFac and queue[PlainId(qd.name) .. "@" .. selFac]
			if q then
				DrawPie(ix + icon / 2, iy + icon / 2 + 3 * s, icon * 0.34, q.prog, q.st, s)
				VBFont.Text("x" .. q.n, ix + icon - 4 * s, iy + 13 * s, 12 * s, "or", 1, 1, 1, 1)
			end
			-- a structure (or unit) of this kind that is under construction right now: pie of the most advanced one
			local cs = qd and constr[qd.id]
			if cs and not q then
				DrawPie(ix + icon / 2, iy + icon / 2 + 3 * s, icon * 0.34, cs.prog, cs.active and "b" or "w", s)
				if cs.n > 1 then VBFont.Text("x" .. cs.n, ix + icon - 4 * s, iy + 13 * s, 12 * s, "or", 1, 1, 1, 1) end
			end
		elseif t.kind == "ru" then
			-- a stock unit the active lab can build: one tile each, with the pie chart of THIS lab's line
			local ru = t.ru
			local r = { ix, iy, ix + icon, iy + icon, ru = ru }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r)
			if over then hoverRu, hoverRuRect = ru, r end
			local rd = UnitDefs[ru.def]
			local fac = RosterFactory(ru)
			local q = fac and queue[PlainId(rd.name) .. "@" .. fac]
			gl.Color(1, 1, 1, (q and q.st == "h") and 0.45 or 1)
			gl.Texture("#" .. ru.def); gl.TexRect(ix, iy, ix + icon, iy + icon); gl.Texture(false)
			if over then Frame(ix, iy, ix + icon, iy + icon, 1, 1, 1, 0.9)
			else Frame(ix, iy, ix + icon, iy + icon, cc[1], cc[2], cc[3], 0.8) end
			local keyed = DrawTileKey(rd, nil, ix, iy, icon, s)      -- [Keys] on: the key, bottom right
			if q then
				DrawPie(ix + icon / 2, iy + icon / 2 + 3 * s, icon * 0.34, q.prog, q.st, s)
				VBFont.Text("x" .. q.n, ix + icon - 4 * s, iy + (keyed and 15 or 3) * s, 12 * s, "or", 1, 1, 1, 1)
			end
		elseif t.kind == "tpl" then
			-- saved designs of the forge: one tile each, with a pie chart for the production progress
			local tid = t.tid
			local dx = 14 * s
			local xrect = { ix + icon - dx, iy + icon - dx, ix + icon, iy + icon, tpl = tid, del = true }
			rects[#rects + 1] = xrect                  -- listed first so that it wins over the tile under it
			local r = { ix, iy, ix + icon, iy + icon, tpl = tid }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r)
			if over then hoverTpl, hoverTplRect = tid, r end
			local tp = F.templates[tid] or {}
			local q = TplQ(tid)
			local locked = T2Locked()
			Box(ix, iy, ix + icon, iy + icon, 0.07, 0.1, 0.14, 1)
			local tex
			if tp.png and tp.png ~= "" and F.PngPath and F.PngPath(tp.png) then tex = F.PngPath(tp.png)
			elseif tp.base and UnitDefNames[tp.base] then tex = "#" .. UnitDefNames[tp.base].id end
			if tex then
				gl.Color(1, 1, 1, (q and q.st == "h") and 0.45 or 1)
				gl.Texture(tex); gl.TexRect(ix, iy, ix + icon, iy + icon); gl.Texture(false)
			end
			if locked then      -- greyed out until the Tier 2 factory is up
				Box(ix, iy, ix + icon, iy + icon, 0.04, 0.04, 0.05, 0.72)
				Frame(ix, iy, ix + icon, iy + icon, 0.4, 0.4, 0.45, 0.9)
				VBFont.Text("T2", ix + icon / 2 - VBFont.Width("T2", 14 * s) / 2, iy + icon / 2 - 4 * s, 14 * s, "o", 0.75, 0.75, 0.8, 1)
			elseif over then Frame(ix, iy, ix + icon, iy + icon, 1, 1, 1, 0.9)
			else Frame(ix, iy, ix + icon, iy + icon, 0.35, 0.9, 1, 0.9) end
			if over then      -- red [x]: delete this design
				local onX = Inside(mx, my, xrect)
				Box(xrect[1], xrect[2], xrect[3], xrect[4], onX and 0.85 or 0.55, 0.1, 0.1, 0.95)
				VBFont.Text("x", xrect[1] + dx * 0.3, xrect[2] + dx * 0.2, 11 * s, "o", 1, 1, 1, 1)
			end
			-- name strip, so that custom units can be told apart
			Box(ix + 1, iy + 1, ix + icon - 1, iy + 11 * s, 0, 0, 0, 0.6)
			VBFont.Text(string.sub(tid, 1, 9), ix + 3 * s, iy + 2 * s, 8 * s, "o", 0.6, 0.95, 1, 1)
			if q then
				DrawPie(ix + icon / 2, iy + icon / 2 + 3 * s, icon * 0.34, q.prog, q.st, s)
				VBFont.Text("x" .. q.n, ix + icon - 4 * s, iy + 13 * s, 12 * s, "or", 1, 1, 1, 1)
			end
		elseif t.kind == "plus" then
			-- the [+] tile: it opens the unit forge
			local r = { ix, iy, ix + icon, iy + icon, plus = true }
			rects[#rects + 1] = r
			local over = Inside(mx, my, r)
			hoverPlus, hoverPlusRect = over, over and r or nil
			local half = icon / 2
			if T2Locked() then      -- greyed out: custom units need the Tier 2 factory first
				Box(ix, iy, ix + icon, iy + icon, 0.07, 0.07, 0.08, 1)
				Frame(ix, iy, ix + icon, iy + icon, over and 0.7 or 0.4, over and 0.55 or 0.4, over and 0.3 or 0.42, 0.9)
				gl.Color(0.32, 0.32, 0.36, 1)
				gl.Rect(ix + icon * 0.28, iy + half - 1.5 * s, ix + icon * 0.72, iy + half + 1.5 * s)
				gl.Rect(ix + half - 1.5 * s, iy + icon * 0.28, ix + half + 1.5 * s, iy + icon * 0.72)
				VBFont.Text("T2", ix + icon - VBFont.Width("T2", 10 * s) - 3 * s, iy + 3 * s, 10 * s, "o", 0.85, 0.65, 0.3, 1)
			else
				Box(ix, iy, ix + icon, iy + icon, over and 0.12 or 0.08, over and 0.22 or 0.16, over and 0.16 or 0.12, 1)
				Frame(ix, iy, ix + icon, iy + icon, over and 0.35 or 0.2, over and 0.95 or 0.55, over and 0.65 or 0.35, over and 0.95 or 0.55)
				gl.Color(over and 0.55 or 0.35, over and 1 or 0.75, over and 0.7 or 0.5, 1)
				gl.Rect(ix + icon * 0.28, iy + half - 1.5 * s, ix + icon * 0.72, iy + half + 1.5 * s)
				gl.Rect(ix + half - 1.5 * s, iy + icon * 0.28, ix + half + 1.5 * s, iy + icon * 0.72)
			end
		end
		if t.kind ~= "plus" then      -- category tag in the tile's top-left corner
			local tg = 9 * s
			Box(ix, iy + icon - tg, ix + tg, iy + icon, cc[1], cc[2], cc[3], 0.95)
			VBFont.Text(t.cat.id, ix + 2.2 * s, iy + icon - tg + 1.5 * s, 7 * s, "o", 0, 0, 0, 1)
		end
	end
	DrawButtons({ activeID = activeID, fs = fs, gap = gap, gridBottom = gridBottom, mx = mx, my = my, obH = obH, obW = obW, ocols = ocols, orows = orows, pad = pad, s = s, tbH = tbH, tbW = tbW, tcols = tcols, x1 = x1 })      -- order + toggle buttons
	-- Play the hover tick ONCE per button. Refresh() rebuilds the builds/orders/toggles
	-- tables every 6 frames, so comparing the table identity fired again and again while
	-- the mouse rested on a button. Compare the command id instead and rate-limit it.
	local hoverID = hover and hover.c and hover.c.id or (hoverTpl and ("t:" .. hoverTpl)) or (hoverRu and ("r:" .. hoverRu.def)) or (hoverPlus and "plus") or nil
	if hoverID ~= lastHoverID then
		lastHoverID = hoverID
		if hoverID ~= nil then
			local now = Spring.GetTimer()
			if not lastHoverSnd or Spring.DiffTimers(now, lastHoverSnd) > 0.08 then
				lastHoverSnd = now; Snd("ui_hover", 0.5)
			end
		end
	end
	DrawHoverInfo(F, queue, TplQ, x1, y2, w, s)      -- the info box above the panel for the tile under the mouse
end

function widget:IsAbove(x, y)
	return panelBox ~= nil and (closed and rects[1] and Inside(x, y, rects[1]) or
		(not closed and x >= px and x <= px + panelBox.w and y >= py and y <= py + panelBox.h)) or false
end

local function Activate(r, button)
	local c, i = r.cmd.c, r.cmd.i
	local alt, ctrl, meta, shift = Spring.GetModKeyState()
	if r.toggle then                                   -- cycle the option: left = next, right = previous
		local n, cur = #c.params - 1, tonumber(c.params[1]) or 0
		local nxt = (button == 3) and (cur - 1) % n or (cur + 1) % n
		Spring.GiveOrder(c.id, { nxt }, {})
	elseif c.type == CMDTYPE.ICON and c.id >= 0 then   -- instant orders: stop, wait, ...
		Spring.GiveOrder(c.id, {}, shift and { "shift" } or {})
	else
		-- Spring.SetActiveCommand takes the 1-BASED index into the same array GetActiveCmdDescs returns
		-- (the engine subtracts 1 itself; passing i-1 made every button trigger the one before it).
		-- Look the index up again by command id at click time, in case the list changed since Refresh().
		local idx = (Spring.GetCmdDescIndex and Spring.GetCmdDescIndex(c.id)) or i
		local ok, res = pcall(Spring.SetActiveCommand, idx, button, button == 1, button == 3, alt, ctrl, meta, shift)
		if (not ok or res == false) and c.id < 0 and UnitDefs[-c.id] then pcall(Spring.SetActiveCommand, "buildunit_" .. UnitDefs[-c.id].name) end
	end
end

function widget:MousePress(x, y, button)
	if not widget:IsAbove(x, y) then return false end
	for _, r in ipairs(rects) do
		if Inside(x, y, r) then
			if r.open then closed = false; Snd("ui_open") return true end
			if r.lab then      -- a lab chip: select that lab (its own roster and queue follow)
				labPick = r.lab
				if Spring.SelectUnitArray then Spring.SelectUnitArray({ r.lab }) end
				RefreshRoster(); Snd("ui_select")
				return true
			end
			if r.close then closed = true; Snd("ui_close") return true end
			if r.keys then showKeys = not showKeys; hintCache, buildKeyCache = {}, {}; Snd("ui_click") return true end
			if r.scale then UserTookOver(); scaling = { x0 = x, y0 = y, s0 = scale, top = py + (panelBox and panelBox.h or 0) } return true end
			if r.drag then UserTookOver(); drag = { x - px, y - py } return true end
			if r.plus and T2Locked() then      -- greyed out: say what to do instead of opening anything
				Snd("ui_error", 0.8)
				Spring.Echo("[VB] " .. (ForgeRef().T2_HINT or "Custom units need a Tier 2 factory: upgrade your factory first"))
				return true
			end
			if r.plus then
				-- open the unit forge; if its widget is not running yet, switch it on first
				local F = ForgeRef()
				if not (F.IsForgeReady and F.IsForgeReady()) and widgetHandler and widgetHandler.EnableWidget then
					pcall(widgetHandler.EnableWidget, widgetHandler, "Voidborn Unit Forge")
					F = ForgeRef()
				end
				if Forge0 then Forge0.openRequest = true end      -- picked up by the forge as soon as it is running
				if F.RequestOpen then F.RequestOpen() end
				Snd("ui_open")
				return true
			end
			if r.ru then
				local fac = RosterFactory(r.ru)
				if fac then QueueClick(UnitDefs[r.ru.def].name, fac, button) end
				return true
			end
			if r.tpl and r.del then
				ForgeRef().DeleteTemplate(r.tpl); Snd("ui_close", 0.6)
				Spring.Echo("[VB] deleted design '" .. r.tpl .. "'")
				return true
			end
			if r.tpl and T2Locked() and not (button == 3 and select(2, Spring.GetModKeyState())) then
				-- a saved design cannot be built (or edited) until the Tier 2 factory is up; ctrl+right still deletes it
				Snd("ui_error", 0.8)
				Spring.Echo("[VB] " .. (ForgeRef().T2_HINT or "Custom units need a Tier 2 factory: upgrade your factory first"))
				return true
			end
			if r.tpl then
				local F = ForgeRef()
				local alt, ctrl, meta, shift = Spring.GetModKeyState()
				if button == 1 then
					if ctrl then F.EditTemplate(r.tpl)
					else F.QueueAdd(r.tpl, shift and 5 or 1, designLab) end
					Snd("ui_select")
				elseif button == 2 then F.QueueHold(designLab and (r.tpl .. "@" .. designLab) or r.tpl); Snd("ui_click")
				elseif button == 3 then
					if ctrl then F.DeleteTemplate(r.tpl); Spring.Echo("[VB] deleted design '" .. r.tpl .. "'")
					else F.QueueRemove(designLab and (r.tpl .. "@" .. designLab) or r.tpl, shift and 5 or 1) end
					Snd("ui_close", 0.5)
				end
				return true
			end
			if r.cmd then
				local qd = (not r.toggle) and RoutedDef(r.cmd)
				if qd then QueueClick(qd.name, SelectedFactory(), button) return true end
				Snd((r.cmd.c.id < 0) and "ui_select" or "ui_click"); Activate(r, button) return true
			end
		end
	end
	return true  -- swallow clicks on empty panel area
end

function widget:MouseMove(x, y)
	if drag then px, py = x - drag[1], y - drag[2]
	elseif scaling then
		scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scaling.s0 + ((x - scaling.x0) - (y - scaling.y0)) / 350))
	end
end
function widget:MouseRelease() drag, scaling = nil, nil end

--------------------------------------------------------------------------------
-- Panel Snap: lets gui_panel_snap.lua dock this panel (drag it near an edge and let go)
--------------------------------------------------------------------------------
local panelSnapSeen
local function PanelSnapRegister()
	local PL = WG.PanelLayout
	if not PL or PL == panelSnapSeen then return end
	panelSnapSeen = PL
	PL.Register("vb_buildpanel", {
		dock = "left", order = 20, fixedSize = true,
		getRect = function()
			if not panelBox then return nil end
			return px, py, panelBox.w, panelBox.h
		end,
		setRect = function(x, y) px, py = x, y end,              -- px, py = bottom-left corner; the scale stays yours
		isVisible = function() return not closed and panelBox ~= nil end,
	})
end
do
	local prevUpdate = widget.Update
	function widget:Update(...)
		PanelSnapRegister()
		if prevUpdate then return prevUpdate(self, ...) end
	end
	local prevShutdown = widget.Shutdown
	function widget:Shutdown(...)
		if WG.PanelLayout then WG.PanelLayout.Unregister("vb_buildpanel") end
		WG.VBBuildPanel = nil
		if prevShutdown then return prevShutdown(self, ...) end
	end
end
