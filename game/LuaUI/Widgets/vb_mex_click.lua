function widget:GetInfo()
	return { name = "Voidborn Mex Click", desc = "Right-click a metal spot with a builder selected to queue an extractor (shift = queue)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true }
end

-- Snapping is tight on purpose: the cursor has to be ON a metal cell of the spot, or at most SNAP_MARGIN elmos
-- outside one; a click that is only near a spot is an ordinary right-click.
local CELL = 16              -- metal-map cell size in elmos
local SNAP_MARGIN = 8        -- elmos outside the edge of a metal cell that still snap (half a cell)
local CLUSTER_CELLS = 4      -- the spot is the connected metal cells within this many cells of the one that was hit
local mexCache = {}  -- builderDefID -> mex unitDefID or false

local function MexFor(builderDefID)
	if mexCache[builderDefID] ~= nil then return mexCache[builderDefID] end
	local found = false
	local bd = UnitDefs[builderDefID]
	for _, optID in ipairs(bd and bd.buildOptions or {}) do
		local ud = UnitDefs[optID]
		if ud and ud.customParams and ud.customParams.kind == "mex" then found = optID break end
	end
	mexCache[builderDefID] = found
	return found
end

local function Metal(cx, cz)
	local ok, v = pcall(Spring.GetMetalAmount, cx, cz)
	return (ok and v and v > 0) and v or 0
end

local function SpotNear(wx, wz)
	local floor, max, sqrt = math.floor, math.max, math.sqrt
	local cx, cz = floor(wx / CELL), floor(wz / CELL)
	-- 1. the metal cell nearest to the cursor, measured to the edge of its square (0 when the cursor is on it)
	local bestD, bx, bz
	for dx = -1, 1 do
		for dz = -1, 1 do
			local x, z = cx + dx, cz + dz
			if Metal(x, z) > 0 then
				local ex = max(x * CELL - wx, 0, wx - (x + 1) * CELL)
				local ez = max(z * CELL - wz, 0, wz - (z + 1) * CELL)
				local d = sqrt(ex * ex + ez * ez)
				if not bestD or d < bestD then bestD, bx, bz = d, x, z end
			end
		end
	end
	if not bestD or bestD > SNAP_MARGIN then return nil end        -- not on a spot (or only slightly beside it): no snap
	-- 2. the spot: the connected metal cells around that one, centre weighted by the amount of metal
	local seen, stack = { [bx .. ":" .. bz] = true }, { { bx, bz } }
	local sx, sz, sw = 0, 0, 0
	while #stack > 0 do
		local c = table.remove(stack)
		local v = Metal(c[1], c[2])
		sx, sz, sw = sx + (c[1] * CELL + CELL / 2) * v, sz + (c[2] * CELL + CELL / 2) * v, sw + v
		for dx = -1, 1 do
			for dz = -1, 1 do
				local x, z = c[1] + dx, c[2] + dz
				local key = x .. ":" .. z
				if not seen[key] and math.abs(x - bx) <= CLUSTER_CELLS and math.abs(z - bz) <= CLUSTER_CELLS and Metal(x, z) > 0 then
					seen[key] = true
					stack[#stack + 1] = { x, z }
				end
			end
		end
	end
	return sx / sw, sz / sw
end

function widget:MousePress(mx, my, button)
	if button ~= 3 then return false end
	local sel = Spring.GetSelectedUnits()
	if not sel or #sel == 0 then return false end
	local builders, mexDef = {}, nil
	for _, u in ipairs(sel) do
		local m = MexFor(Spring.GetUnitDefID(u))
		if m then builders[#builders + 1] = u; mexDef = mexDef or m end
	end
	if not mexDef then return false end
	local kind, pos = Spring.TraceScreenRay(mx, my, true)
	if kind ~= "ground" or not pos then return false end
	local x, z = SpotNear(pos[1], pos[3])
	if not x then return false end                    -- not on a metal spot: normal right-click
	local y = Spring.GetGroundHeight(x, z)
	local opts = {}; local _, _, _, shift = Spring.GetModKeyState()
	if shift then opts[#opts + 1] = "shift" end
	Spring.GiveOrderToUnitArray(builders, -mexDef, { x, y, z, 0 }, opts)
	return true
end
