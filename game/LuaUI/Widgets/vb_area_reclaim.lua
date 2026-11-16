function widget:GetInfo()
	return { name = "Voidborn Area Reclaim", desc = "Area reclaim (drag a circle with the reclaim command) sends each builder through every reclaimable in the circle, nearest first and then on to the next closest, so it also picks up mushrooms. /vbareclaim turns it on or off",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 0, enabled = true }
end

-- The engine's own area reclaim picks targets itself and, here, does not see the mushroom patches (and takes
-- rocks and wrecks in no useful order).  This widget takes over an area-reclaim command: it looks up the
-- reclaimable features inside the circle and gives each selected reclaimer a queue of single reclaim orders along a
-- nearest-neighbour path (the closest one first, then always the closest one to where it just was), and queues
-- the original area command last so that anything the lookup could not see (units, targets beyond the queue
-- limit) is still handled by the engine.  Shift keeps the builder's current queue, as with any order.
local MAX_QUEUE = 120          -- orders queued per builder in one go
local enabled = true

function widget:GetConfigData() return { enabled = enabled } end
function widget:SetConfigData(d) if d and d.enabled ~= nil then enabled = d.enabled end end

local function Toggle()
	enabled = not enabled
	Spring.Echo("[VB] area reclaim path: " .. (enabled and "on (nearest to furthest)" or "off (engine default)") .. "   (/vbareclaim changes it)")
	return true
end
function widget:Initialize()
	if widgetHandler and widgetHandler.AddAction then widgetHandler:AddAction("vbareclaim", Toggle, nil, "t") end
end
function widget:Shutdown() if widgetHandler and widgetHandler.RemoveAction then widgetHandler:RemoveAction("vbareclaim") end end
function widget:TextCommand(cmd) if cmd == "vbareclaim" then return Toggle() end end

local function Reclaimable(fid)
	local defID = Spring.GetFeatureDefID(fid)
	local fd = defID and FeatureDefs[defID]
	if not fd or not fd.reclaimable then return false end
	local m, _, e = Spring.GetFeatureResources(fid)
	return ((m or 0) + (e or 0)) > 0
end

-- nearest-neighbour path through the features, starting from (x, z); entries are { fid, x, z }
local function Path(x, z, feats)
	local rest, n = {}, #feats
	for i = 1, n do rest[i] = feats[i] end
	local out = {}
	while n > 0 and #out < MAX_QUEUE do
		local best, bestD = 1, math.huge
		for i = 1, n do
			local f = rest[i]
			local d = (f[2] - x) ^ 2 + (f[3] - z) ^ 2
			if d < bestD then best, bestD = i, d end
		end
		local f = rest[best]
		out[#out + 1] = f[1]
		x, z = f[2], f[3]
		rest[best] = rest[n]; rest[n] = nil; n = n - 1
	end
	return out
end

function widget:CommandNotify(cmdID, params, opts)
	if not enabled or cmdID ~= CMD.RECLAIM or not params or #params ~= 4 then return false end
	if opts and (opts.ctrl or opts.alt or opts.meta) then return false end   -- the engine's special area modes stay as they are
	local radius = params[4]
	if not radius or radius < 1 then return false end

	local reclaimers = {}
	for _, u in ipairs(Spring.GetSelectedUnits() or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(u)]
		if ud and ud.canReclaim then reclaimers[#reclaimers + 1] = u end
	end
	if #reclaimers == 0 then return false end

	local feats = {}
	for _, fid in ipairs(Spring.GetFeaturesInCylinder(params[1], params[3], radius) or {}) do
		if Reclaimable(fid) then
			local fx, _, fz = Spring.GetFeaturePosition(fid)
			if fx then feats[#feats + 1] = { fid, fx, fz } end
		end
	end
	if #feats == 0 then return false end                                   -- nothing in the circle that we know of: the engine decides

	local keepQueue = opts and opts.shift
	for _, u in ipairs(reclaimers) do
		local ux, _, uz = Spring.GetUnitPosition(u)
		if ux then
			local orders = {}
			for i, fid in ipairs(Path(ux, uz, feats)) do
				orders[#orders + 1] = { CMD.RECLAIM, { fid + Game.maxUnits }, (i == 1 and not keepQueue) and {} or { "shift" } }
			end
			orders[#orders + 1] = { CMD.RECLAIM, { params[1], params[2], params[3], params[4] }, { "shift" } }
			Spring.GiveOrderArrayToUnit(u, orders)
		end
	end
	return true
end
