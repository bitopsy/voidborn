function widget:GetInfo()
	return { name = "Voidborn Health Bars", desc = "3D pill shaped health bars above units (and build progress above unfinished structures). /vbhealth cycles always / damaged / off",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

local spGetVisibleUnits = Spring.GetVisibleUnits
local spGetUnitHealth   = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitHeight   = Spring.GetUnitHeight
local spGetUnitRadius   = Spring.GetUnitRadius
local spGetUnitTeam     = Spring.GetUnitTeam
local spIsUnitSelected  = Spring.IsUnitSelected
local spGetMyTeamID     = Spring.GetMyTeamID
local spAreTeamsAllied  = Spring.AreTeamsAllied
local spGetUnitDefID    = Spring.GetUnitDefID

local MODES = { "always", "damaged", "off" }
local mode = "always"
local MAX_BARS = 500                 -- never draw more than this many bars in one frame

function widget:GetConfigData() return { mode = mode } end
function widget:SetConfigData(d) if d and d.mode then for _, m in ipairs(MODES) do if m == d.mode then mode = m end end end end

local function Cycle()
	for i, m in ipairs(MODES) do
		if m == mode then mode = MODES[i % #MODES + 1]; break end
	end
	Spring.Echo("[VB] health bars: " .. mode .. "   (/vbhealth changes it)")
	return true
end
function widget:Initialize()
	Spring.Echo("[VB] Health bars loaded (mode: " .. mode .. ")")
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbhealth", Cycle, nil, "t") end
end
function widget:TextCommand(cmd) if cmd == "vbhealth" then return Cycle() end end

-- green -> yellow -> red
local function HealthColor(f)
	if f > 0.5 then return (1 - f) * 2, 1, 0.1 end
	return 1, f * 2, 0.1
end

-- A pill (capsule): a rectangle with half circles at both ends, drawn as one triangle fan.
-- gl.BeginEnd passes the extra arguments to the emitter, so no table is allocated per bar.
local SEG = 6
local CS, SN = {}, {}
for i = 0, SEG do
	local a = math.pi * i / SEG
	CS[i], SN[i] = math.cos(a), math.sin(a)
end
local glVertex = gl.Vertex
local function EmitPill(x1, y1, x2, y2)
	local r = (y2 - y1) / 2
	local cy = y1 + r
	glVertex((x1 + x2) / 2, cy)
	for i = 0, SEG do                         -- right cap: from the bottom (-90 degrees) up to the top
		glVertex(x2 - r + r * SN[i], cy - r * CS[i])
	end
	for i = 0, SEG do                         -- left cap: from the top round to the bottom
		glVertex(x1 + r - r * SN[i], cy + r * CS[i])
	end
	glVertex(x2 - r, y1)
end
local function Pill(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.BeginEnd(GL.TRIANGLE_FAN, EmitPill, x1, y1, x2, y2)
end

-- One tube: dark glass, the liquid that shrinks from the right as health is lost, and highlights
-- so that it looks rounded.  x1..x2 is the full tube, y1..y2 its height, f the filled share 0..1.
local function Tube(x1, y1, x2, y2, f, r, g, b)
	local H = y2 - y1
	local pad = H * 0.14
	local o = math.max(0.35, H * 0.2)                                           -- outline, proportional to the thickness
	Pill(x1 - o, y1 - o, x2 + o, y2 + o, 0, 0, 0, 0.8)                         -- outline
	Pill(x1, y1, x2, y2, 0.10, 0.11, 0.16, 0.92)                                -- the empty tube
	if f > 0.01 then
		local fx2 = math.max(x1 + H - 2 * pad, x1 + (x2 - x1) * f)
		fx2 = math.min(fx2, x2)
		Pill(x1 + pad, y1 + pad, fx2 - pad, y2 - pad, r * 0.55, g * 0.55, b * 0.55, 0.98)                  -- shaded body
		Pill(x1 + pad, y1 + H * 0.32, fx2 - pad, y2 - pad, r, g, b, 1)                                      -- lit upper part
		local hl = H * 0.2
		Pill(x1 + H * 0.45, y2 - pad - hl - H * 0.06, math.max(x1 + H * 0.45 + hl, fx2 - H * 0.45), y2 - pad - H * 0.06,
			1, 1, 1, 0.42)                                                                                  -- glossy highlight
	end
	Pill(x1 + H * 0.3, y2 - H * 0.38, x2 - H * 0.3, y2 - H * 0.12, 1, 1, 1, 0.1)    -- glass gloss over the whole tube
end

function widget:DrawWorld()
	if mode == "off" then return end
	local units = spGetVisibleUnits(-1, nil, false)
	if not units or #units == 0 then return end
	local myTeam = spGetMyTeamID()
	gl.DepthTest(false)
	gl.Texture(false)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	local drawn = 0
	for i = 1, #units do
		local u = units[i]
		local hp, maxhp, _, _, build = spGetUnitHealth(u)
		if hp and maxhp and maxhp > 0 then
			local building = build and build < 1
			local f = math.max(0, math.min(1, hp / maxhp))
			local show = building or mode == "always" or f < 0.999 or spIsUnitSelected(u)
			if show then
				local x, y, z = spGetUnitPosition(u)
				if x then
					drawn = drawn + 1
					if drawn > MAX_BARS then break end
					local rad = spGetUnitRadius(u) or 20
					local w = math.max(10, math.min(80, rad * 0.95))       -- half width in elmos (narrow)
					-- thickness grows with the unit's max health on a log scale: ~2.4 at 230 hp, ~3.4 at 1000 hp, ~5.6 at 13000 hp
					local h = math.max(2.2, math.min(7, 1.8 + (math.log(maxhp) / math.log(10) - 2) * 1.6))
					local top = y + (spGetUnitHeight(u) or rad * 2) + 3 + h  -- sits low, right above the unit
					gl.PushMatrix()
					gl.Translate(x, top, z)
					gl.Billboard()
					-- green to red for your own and allied units, an orange-red liquid for enemies
					local r, g, b = HealthColor(f)
					local team = spGetUnitTeam(u)
					if team and team ~= myTeam and not (spAreTeamsAllied and spAreTeamsAllied(team, myTeam)) then r, g, b = 1, 0.25 + 0.4 * f, 0.2 end
					Tube(-w, 0, w, h, f, r, g, b)
					if building then
						-- an unfinished structure: a second, thinner tube with the build progress
						local h2 = h * 0.6
						Tube(-w * 0.8, -h2 - 2, w * 0.8, -2, build, 0.35, 0.8, 1)
					end
					gl.PopMatrix()
				end
			end
		end
	end
	gl.Color(1, 1, 1, 1)
end
