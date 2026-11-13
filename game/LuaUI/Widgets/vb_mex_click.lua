function widget:GetInfo()
	return { name = "Voidborn Mex Click", desc = "Right-click a metal spot with a builder selected to queue an extractor (shift = queue)",
		author = "Voidborn Dev", date = "2026", license = "GPL", layer = 1, enabled = true }
end

local SEARCH = 6  -- metal-map cells (16 elmos each) around the cursor
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

local function SpotNear(wx, wz)
	local cx, cz = math.floor(wx / 16), math.floor(wz / 16)
	local sx, sz, n = 0, 0, 0
	for dx = -SEARCH, SEARCH do for dz = -SEARCH, SEARCH do
		local ok, v = pcall(Spring.GetMetalAmount, cx + dx, cz + dz)
		if ok and v and v > 0 then sx = sx + (cx + dx); sz = sz + (cz + dz); n = n + 1 end
	end end
	if n == 0 then return nil end
	return (sx / n) * 16 + 8, (sz / n) * 16 + 8
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
