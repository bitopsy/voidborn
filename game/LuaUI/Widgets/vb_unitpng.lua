function widget:GetInfo()
	return { name = "Voidborn Unit PNG", desc = "Draws the png= image of /vbcreate units as a billboard above them",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = 0, enabled = true }
end

-- /vbcreate dread base=ch_hoplite png=dread          -> unitpics/dread.png
-- /vbcreate dread base=ch_hoplite png=icons/dread.png pngsize=120
-- The file is looked up through the VFS, so it can live inside the game archive (game/unitpics/...)
-- OR loose in the engine data directory (<data dir>/unitpics/dread.png) with no rebuild needed.

local spGetVisibleUnits   = Spring.GetVisibleUnits
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitHeight     = Spring.GetUnitHeight
local spGetUnitRadius     = Spring.GetUnitRadius

local resolved, warned = {}, {}   -- raw name -> resolved path (or false)

local function Resolve(raw)
	local r = resolved[raw]
	if r ~= nil then return r end
	local path = raw
	if not path:find("/", 1, true) then path = "unitpics/" .. path end
	if not path:lower():find("%.%w+$") then path = path .. ".png" end
	if VFS.FileExists(path) then r = path
	else
		r = false
		if not warned[raw] then warned[raw] = true; Spring.Echo("[VB] unit png not found: " .. path .. "  (put it in game/unitpics/ or <data dir>/unitpics/)") end
	end
	resolved[raw] = r
	return r
end

function widget:DrawWorld()
	local units = spGetVisibleUnits(-1, nil, false)
	if not units then return end
	local started = false
	for i = 1, #units do
		local u = units[i]
		local raw = spGetUnitRulesParam(u, "vb_png")
		if raw then
			local path = Resolve(raw)
			if path then
				if not started then
					started = true
					gl.Color(1, 1, 1, 1)
					gl.DepthTest(true)
					gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
				end
				local x, y, z = spGetUnitPosition(u)
				if x then
					local size = spGetUnitRulesParam(u, "vb_pngsize") or math.max(48, (spGetUnitRadius(u) or 24) * 2.2)
					local h = spGetUnitHeight(u) or 30
					gl.PushMatrix()
					gl.Translate(x, y + h + size * 0.6, z)
					gl.Billboard()
					gl.Texture(path)
					gl.TexRect(-size / 2, -size / 2, size / 2, size / 2)
					gl.Texture(false)
					gl.PopMatrix()
				end
			end
		end
	end
	if started then gl.DepthTest(false); gl.Color(1, 1, 1, 1) end
end
