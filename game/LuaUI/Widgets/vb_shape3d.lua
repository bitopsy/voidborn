-- Voidborn 3D shapes: draws the custom body of a unit in the world.
--
-- A unit created with a "shape=" (see the unit forge, LuaUI/Widgets/vb_forge.lua)
-- carries the encoded shape in its "vb_shape" rules parameter.  This widget reads
-- that parameter for every visible unit and draws the primitives in its place,
-- with the unit's PNG mapped onto them.
--
-- The shape is drawn on top of the base model (depth test off), so the new body
-- is what you see; the base unit model is only the shadow underneath.
function widget:GetInfo()
	return { name = "Voidborn 3D Shapes", desc = "Draws the custom 3D body of units that were created with a shape",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -5, enabled = true }
end

local okG, Forge = pcall(VFS.Include, "LuaUI/Headers/vb_forge.h.lua")
if not okG or type(Forge) ~= "table" then
	Forge = { DecodeShape = function() end, PngList = function() return {} end, PngPath = function() end,
		DrawShape = function() end }
end

local spGetVisibleUnits   = Spring.GetVisibleUnits
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitDirection  = Spring.GetUnitDirection
local spGetUnitRadius     = Spring.GetUnitRadius

local decoded = {}          -- raw shape string -> decoded shape (cache)
local pngCache = {}         -- name -> path

-- the texture of a primitive: index 0 is the unit's own png, 1..n are the
-- pictures in unitpics/ and icons/
local function TexPath(prim, unitPng, list)
	local idx = prim.tex or -1
	if idx < 0 then return nil end
	if idx == 0 then
		if not unitPng then return nil end
		if pngCache[unitPng] == nil then pngCache[unitPng] = Forge.PngPath(unitPng) end
		return pngCache[unitPng]
	end
	local name = list[idx]
	if not name then return nil end
	if pngCache[name] == nil then pngCache[name] = Forge.PngPath(name) end
	return pngCache[name]
end

function widget:DrawWorld()
	local units = spGetVisibleUnits(-1, nil, false)
	if not units then return end
	local list = Forge.PngList()
	local started = false
	for i = 1, #units do
		local u = units[i]
		local raw = spGetUnitRulesParam(u, "vb_shape")
		if raw and raw ~= "" then
			local shape = decoded[raw]
			if not shape then
				shape = Forge.DecodeShape(raw) or {}
				decoded[raw] = shape
			end
			if #shape > 0 then
				local x, y, z = spGetUnitPosition(u)
				if x then
					local dirx, _, dirz = spGetUnitDirection(u)
					local yaw = dirx and math.atan(dirx, dirz) or 0
					if not started then
						started = true
						gl.Color(1, 1, 1, 1)
						gl.DepthTest(false)
					end
					gl.PushMatrix()
					gl.Translate(x, y, z)
					gl.Rotate(yaw * 180 / math.pi, 0, 1, 0)
					-- the shape is drawn in elmos; the unit radius sets how big it is
					local r = spGetUnitRadius(u) or 24
					local scale = r / 24
					for _, p in ipairs(shape) do
						local tex = TexPath(p, spGetUnitRulesParam(u, "vb_png"), list)
						Forge.DrawShape({ p }, tex, scale)
					end
					gl.PopMatrix()
				end
			end
		end
	end
	if started then
		gl.DepthTest(true)
		gl.Color(1, 1, 1, 1)
	end
end

function widget:Shutdown() decoded = {} end
