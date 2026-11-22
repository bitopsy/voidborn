function widget:GetInfo()
	return { name = "Voidborn Faction Menu", desc = "Pick Choir, Maw, Tympan, Miasma or Haptic before the game starts, when the faction was not chosen in the lobby",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 60, enabled = true }
end

-- Shown while the game has not started (frame 0), to a player (not a spectator) whose side is empty: the lobby and the
-- start script did not choose one.  Five cards, one per faction; click one (or press 1 - 5, or type /vbfaction tympan)
-- and the choice goes to the rules (game_spawn.lua: "vbfaction:<Side>"), which spawn that faction's commander at the
-- start.  The choice can be changed until the game starts.  A player who does not choose gets the old default
-- (the factions in turn by team number).  The lobby option faction_menu = off hides the menu.
--
--   game/LuaUI/Widgets/vb_faction_menu.lua

local SIDES = {
	{ side = "Choir",  title = "CHOIR OF THE EYE",  organ = "THE EYE",   col = { 0.44, 0.70, 1.00 },
	  lines = { "Pale, many-eyed cyclopes.", "Long-range lasers, sees far,", "fragile up close." } },
	{ side = "Maw",    title = "MAW SWARM",         organ = "THE MOUTH", col = { 1.00, 0.60, 0.24 },
	  lines = { "Chitinous, toothed, many-legged.", "Short reach, tough, regenerating", "and cheap." } },
	{ side = "Tympan", title = "TYMPAN CONCLAVE",   organ = "THE EAR",   col = { 1.00, 0.78, 0.29 },
	  lines = { "Floating ears, horns and drums.", "Sound that hits harder when many", "hit one target; radar and ears." } },
	{ side = "Miasma", title = "MIASMA BLOOM",      organ = "THE NOSE",  col = { 0.89, 0.38, 1.00 },
	  lines = { "Drifting snouts and flowers.", "Slow and tough; every hit poisons", "and scents its target." } },
	{ side = "Haptic", title = "HAPTIC GRASP",      organ = "THE HAND",  col = { 0.38, 0.69, 1.00 },
	  lines = { "Hands and tentacles. Short sight,", "short reach, hits much harder up", "close; its raiders burst on touch." } },
}

local spGetTeamInfo, spGetMyTeamID, spGetGameFrame = Spring.GetTeamInfo, Spring.GetMyTeamID, Spring.GetGameFrame
local glColor, glRect, glTexture, glTexRect, glText = gl.Color, gl.Rect, gl.Texture, gl.TexRect, gl.Text
local min, max, floor = math.min, math.max, math.floor

local vsx, vsy = Spring.GetViewGeometry()
local chosen, mx, my
local rects = {}                 -- card rectangles { x1, y1, x2, y2, i = index }
local panel                      -- { x1, y1, x2, y2 }
widget.vbRects = rects           -- for the smoke test

local function Menu() return (Spring.GetModOptions() or {}).faction_menu ~= "0" end

-- the menu is for a player of a team without a side, before the game starts
local function Wanted()
	if not Menu() or spGetGameFrame() > 0 then return false end
	if Spring.IsReplay and Spring.IsReplay() then return false end
	if (Spring.GetSpectatingState()) then return false end
	local side = select(5, spGetTeamInfo(spGetMyTeamID()))
	return side == nil or side == ""
end

local function Choose(i)
	local s = SIDES[i]
	if not s then return end
	chosen = i
	Spring.SendLuaRulesMsg("vbfaction:" .. s.side)
	Spring.Echo("[VB] Faction: " .. s.title .. " (you can change it until the game starts)")
end

local function Layout()
	local sc = max(0.75, min(1.7, vsy / 1080))
	local gap = 14 * sc
	local n = #SIDES
	local cw = min(270 * sc, (vsx * 0.94 - gap * (n + 1)) / n)
	local ch = cw * 1.12
	local w = cw * n + gap * (n + 1)
	local x0 = floor((vsx - w) / 2)
	local y2 = floor(vsy * 0.88)
	local titleH = 74 * sc
	local y1 = floor(y2 - ch - titleH - gap)
	panel = { x1 = x0, y1 = y1, x2 = x0 + w, y2 = y2, sc = sc, titleH = titleH }
	for i = 1, #SIDES do
		local cx = x0 + gap + (i - 1) * (cw + gap)
		rects[i] = { x1 = cx, y1 = y1 + gap, x2 = cx + cw, y2 = y1 + gap + ch, i = i }
	end
	for i = #SIDES + 1, #rects do rects[i] = nil end
end

local function Hit(r, x, y) return r and x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 end
local function CardAt(x, y) for i = 1, #SIDES do if Hit(rects[i], x, y) then return i end end end

function widget:Initialize()
	vsx, vsy = Spring.GetViewGeometry(); Layout()
end

function widget:ViewResize(x, y) vsx, vsy = x, y; Layout() end

function widget:TextCommand(cmd)
	local name = cmd:match("^vbfaction%s+(%a+)")
	if not name or not Wanted() then return end
	for i, s in ipairs(SIDES) do
		if string.lower(s.side) == string.lower(name) then Choose(i) return true end
	end
	Spring.Echo("[VB] /vbfaction choir | maw | tympan | miasma | haptic")
	return true
end

function widget:IsAbove(x, y)
	return Wanted() and panel and x >= panel.x1 and x <= panel.x2 and y >= panel.y1 and y <= panel.y2
end

function widget:MousePress(x, y, button)
	if not Wanted() or not panel then return false end
	if x < panel.x1 or x > panel.x2 or y < panel.y1 or y > panel.y2 then return false end
	if button == 1 then
		local i = CardAt(x, y)
		if i then Choose(i) end
	end
	return true                                     -- the click is the menu's, not the map's
end

local KEYS = { [49] = 1, [50] = 2, [51] = 3, [52] = 4, [53] = 5, [257] = 1, [258] = 2, [259] = 3, [260] = 4, [261] = 5 }
function widget:KeyPress(key, mods, isRepeat)
	if isRepeat or not Wanted() then return false end
	local i = KEYS[key]
	if i then Choose(i) return true end
	return false
end

function widget:Update()
	mx, my = Spring.GetMouseState()
end

local function Txt(str, x, y, size, opts, r, g, b, a)
	glColor(r or 1, g or 1, b or 1, a or 1)
	glText(str, x, y, size, opts or "o")
end

function widget:DrawScreen()
	if not Wanted() or not panel then return end
	local sc = panel.sc
	-- the panel
	glColor(0.04, 0.03, 0.09, 0.88); glRect(panel.x1, panel.y1, panel.x2, panel.y2)
	glColor(0.55, 0.50, 0.85, 0.8)
	glRect(panel.x1, panel.y2 - 2, panel.x2, panel.y2); glRect(panel.x1, panel.y1, panel.x2, panel.y1 + 2)
	Txt("CHOOSE YOUR FACTION", (panel.x1 + panel.x2) / 2, panel.y2 - 34 * sc, 26 * sc, "co", 0.95, 0.93, 1.0)
	Txt(chosen and ("You play the " .. SIDES[chosen].title .. ". Press Start when ready, or pick another.")
	    or "Click a faction, or press 1 - 5, then press Start. No choice: the factions are handed out in turn.",
	    (panel.x1 + panel.x2) / 2, panel.y2 - 60 * sc, 14 * sc, "co", 0.75, 0.74, 0.9)
	-- the cards
	local over = CardAt(mx or -1, my or -1)
	for i, s in ipairs(SIDES) do
		local r = rects[i]; local c = s.col
		local on = (chosen == i)
		glColor(c[1] * (on and 0.30 or over == i and 0.22 or 0.12), c[2] * (on and 0.30 or over == i and 0.22 or 0.12), c[3] * (on and 0.30 or over == i and 0.22 or 0.12), 0.95)
		glRect(r.x1, r.y1, r.x2, r.y2)
		glColor(c[1], c[2], c[3], on and 1 or over == i and 0.9 or 0.55)
		local t = on and 4 or 2
		glRect(r.x1, r.y2 - t, r.x2, r.y2); glRect(r.x1, r.y1, r.x2, r.y1 + t); glRect(r.x1, r.y1, r.x1 + t, r.y2); glRect(r.x2 - t, r.y1, r.x2, r.y2)
		-- emblem
		local e = (r.x2 - r.x1) * 0.52
		local ex, ey = (r.x1 + r.x2) / 2 - e / 2, r.y2 - e - 12 * sc
		glColor(1, 1, 1, 1); glTexture("sidepics/" .. string.lower(s.side) .. ".png"); glTexRect(ex, ey, ex + e, ey + e); glTexture(false)
		local cx = (r.x1 + r.x2) / 2
		Txt(s.title, cx, ey - 24 * sc, 17 * sc, "co", c[1], c[2], c[3])
		Txt(s.organ, cx, ey - 42 * sc, 12 * sc, "co", 0.8, 0.8, 0.9, 0.8)
		for k, line in ipairs(s.lines) do Txt(line, cx, ey - (64 + (k - 1) * 17) * sc, 13 * sc, "co", 0.88, 0.88, 0.95) end
		if on then Txt("SELECTED", cx, r.y1 + 10 * sc, 13 * sc, "co", c[1], c[2], c[3]) end
	end
	glColor(1, 1, 1, 1)
end

function widget:GameStart()
	if chosen then Spring.Echo("[VB] You play the " .. SIDES[chosen].title .. ".") end
end
