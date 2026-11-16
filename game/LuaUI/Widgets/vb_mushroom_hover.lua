function widget:GetInfo()
	return { name = "Voidborn Mushroom Hover", desc = "Hover a mushroom patch to see its energy; right-click it with a reclaimer selected to eat it (shift = queue)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 1, enabled = true }
end

-- The patches themselves are features made by LuaRules/Gadgets/vb_mushrooms.lua.  The engine's own hover and
-- reclaim click work on them too; this widget makes sure of both, by picking the patch from what is drawn
-- (its size follows the same numbers as the gadget's drawing) and ordering the reclaim itself when the engine
-- did not pick it.
local MAX_ELMOS = 220
local SQUASH = 0.78
local patches, lastScan = {}, -100

local function Scan(frame)
	lastScan = frame
	patches = {}
	for _, fid in ipairs(Spring.GetAllFeatures()) do
		local defID = Spring.GetFeatureDefID(fid)
		if defID and FeatureDefs[defID] and FeatureDefs[defID].name == "vb_graymatter" then patches[#patches + 1] = fid end
	end
end

-- screen position and pixel radius of a patch's visible body
local function Body(fid, right)
	local x, y, z = Spring.GetFeaturePosition(fid)
	if not x then return nil end
	local baseR = Spring.GetFeatureRulesParam(fid, "vb_r") or 24
	local G = math.max(0, math.min(1, Spring.GetFeatureRulesParam(fid, "vb_g") or 0))
	local b = math.max(0, math.min(1, Spring.GetFeatureRulesParam(fid, "vb_b") or 1))
	local floating = (Spring.GetFeatureRulesParam(fid, "vb_fl") or 0) == 1
	local S = math.min(MAX_ELMOS, baseR * (0.6 + 2.4 * G))
	local rb = baseR * 0.5 * (0.35 + 0.65 * math.sqrt(b)) * (1 - 0.30 * G)
	local H = rb * SQUASH * 1.6 + S * 1.1 * math.min(1, G * 4) * (1 - 0.35 * (Spring.GetFeatureRulesParam(fid, "vb_w") or 0))
	local R = math.max(rb * 1.2, H * 0.5, S * 0.5 * math.min(1, G * 3), 8)
	local cy = floating and y or (y + H * 0.5)
	local sx, sy, sz = Spring.WorldToScreenCoords(x, cy, z)
	local ex = Spring.WorldToScreenCoords(x + right[1] * R, cy + right[2] * R, z + right[3] * R)
	if not sx or not ex then return nil end
	return sx, sy, math.max(16, math.abs(ex - sx)), x, y, z
end

-- the patch under the mouse, nearest to its centre first
local function HoverAt(mx, my)
	local cv = Spring.GetCameraVectors()
	if not cv or not cv.right then return nil end
	local best, bestScore
	for i = 1, #patches do
		local fid = patches[i]
		local sx, sy, rpx, x, y, z = Body(fid, cv.right)
		if sx then
			local d = math.sqrt((mx - sx) ^ 2 + (my - sy) ^ 2)
			if d <= rpx and (not bestScore or d / rpx < bestScore) then best, bestScore = fid, d / rpx end
		end
	end
	return best
end

function widget:Update()
	local frame = Spring.GetGameFrame()
	if frame - lastScan >= 10 or frame < lastScan then Scan(frame) end
end

-- a progress bar over every patch that is being reclaimed: it fills as the energy is taken
local function DrawBars()
	local cv = Spring.GetCameraVectors()
	if not cv or not cv.right then return end
	for i = 1, #patches do
		local fid = patches[i]
		local w = Spring.GetFeatureRulesParam(fid, "vb_w") or 0
		if w > 0.005 then
			local sx, sy, rpx, x, y, z = Body(fid, cv.right)
			if sx and Spring.IsSphereInView(x, y, z, 60) then
				local rate = Spring.GetFeatureRulesParam(fid, "vb_rate") or 0
				local left = Spring.GetFeatureRulesParam(fid, "vb_e") or 0
				local bw, bh = 70, 7
				local x1, y1 = sx - bw, sy + rpx + 10
				gl.Color(0, 0, 0, 0.75);        gl.Rect(x1 - 2, y1 - 2, sx + bw + 2, y1 + bh + 2)
				gl.Color(0.16, 0.16, 0.18, 0.95); gl.Rect(x1, y1, sx + bw, y1 + bh)
				gl.Color(0.85, 0.80, 0.45, 1);  gl.Rect(x1, y1, x1 + 2 * bw * math.min(1, w), y1 + bh)
				gl.Color(1, 1, 1, 1)
				gl.Text(string.format("reclaiming  %d E/s  -  %d E left", math.floor(rate + 0.5), math.floor(left + 0.5)), sx, y1 + bh + 6, 12, "oc")
			end
		end
	end
	gl.Color(1, 1, 1, 1)
end

function widget:DrawScreen()
	if #patches == 0 then return end
	DrawBars()
	local mx, my = Spring.GetMouseState()
	if Spring.IsAboveMiniMap and Spring.IsAboveMiniMap(mx, my) then return end
	local fid = HoverAt(mx, my)
	if not fid then return end
	local e, cap = Spring.GetFeatureRulesParam(fid, "vb_e") or 0, Spring.GetFeatureRulesParam(fid, "vb_c") or 0
	local w = Spring.GetFeatureRulesParam(fid, "vb_w") or 0
	local rate = Spring.GetFeatureRulesParam(fid, "vb_rate") or 0
	local line1 = string.format("Mushrooms: %d / %d energy", math.floor(e + 0.5), math.floor(cap + 0.5))
	local line2 = (w > 0.02) and string.format("being reclaimed: %d E/s", math.floor(rate + 0.5)) or "reclaim to collect"
	gl.Color(1, 1, 1, 1)
	gl.Text(line1, mx + 18, my - 22, 15, "o")
	gl.Color(0.8, 0.8, 0.8, 1)
	gl.Text(line2, mx + 18, my - 40, 12, "o")
	gl.Color(1, 1, 1, 1)
end

function widget:MousePress(mx, my, button)
	if #patches == 0 then return false end
	local _, cmdID = Spring.GetActiveCommand()
	if button == 3 then
		if cmdID then return false end                                   -- right-click cancels a command, leave it alone
	elseif button == 1 then
		if cmdID ~= CMD.RECLAIM then return false end                    -- left-click only while the reclaim command is armed
	else
		return false
	end
	local reclaimers = {}
	for _, u in ipairs(Spring.GetSelectedUnits() or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u)]
		if ud and ud.canReclaim then reclaimers[#reclaimers + 1] = u end
	end
	if #reclaimers == 0 then return false end
	local fid = HoverAt(mx, my)
	if not fid then return false end
	local kind = Spring.TraceScreenRay(mx, my)
	if kind == "feature" then return false end                           -- the engine picked it itself: let it do the order
	local opts = {}
	local _, _, _, shift = Spring.GetModKeyState()
	if shift then opts[#opts + 1] = "shift" end
	Spring.GiveOrderToUnitArray(reclaimers, CMD.RECLAIM, { fid + Game.maxUnits }, opts)
	return true
end
