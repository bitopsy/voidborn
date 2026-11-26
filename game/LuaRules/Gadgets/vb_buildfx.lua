-- Voidborn: BUILD and REPAIR visuals for the commander and the builders.
--
-- The constructors and the assistants of every faction already show a beam when they BUILD (that comes from their unit scripts / the
-- engine's nano particles).  The commander had none, and nobody had a separate look for REPAIR.  This gadget adds both, drawn in the world
-- with plain GL, so it needs no effect files, textures or unit scripts:
--
--   BUILD   (commander only)    a shimmering beam in the faction's colour from the commander's nano point to the unit under
--                               construction, glowing packets streaming along it, and a scan ring sweeping up and down the new unit.
--   REPAIR  (commander + every  a pale mint double helix that winds around the beam and tapers into both ends, sparkles rising round the
--           other builder)      repaired unit, a pulse ring spreading on the ground below it and a small "+" floating above it.
--
-- Which one is shown comes from what the builder is working on: Spring.GetUnitIsBuilding() is the unit it builds OR repairs; if that
-- unit is still under construction it is a build, otherwise a repair.  Reclaim and resurrect are not touched.
--
-- The nano point is a piece of the builder's model whose name contains one of PIECE_HINTS (first hint that matches wins, the result is
-- cached per unit type); if the model has none, the beam leaves from just above the middle of the unit.
--
--   game/LuaRules/Gadgets/vb_buildfx.lua      (unsynced only, nothing is sent from the rules)
--   tune the look in the CONFIG block right below.

function gadget:GetInfo()
	return {
		name = "Voidborn Build FX", desc = "Commander build beam + repair visual for the commander and all builders",
		author = "added for the Voidborn mod", date = "2026", license = "GPL", layer = 5, enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then return false end

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

-- Who gets the BUILD visual from this gadget (customParams.kind).  Everybody else already has one from their unit script.
-- Add  con = true  (or any other kind) here if you ever want this beam on those too.
local BUILD_KINDS = { com = true }

-- Everyone who builds (any non-factory unit with buildSpeed > 0) gets the REPAIR visual.
local REPAIR_ENABLED = true

local MAX_BUILDERS = 40          -- at most this many builders are drawn per frame
local MAX_DISTANCE = 3500        -- elmos from the camera; further away nothing is drawn
local FADE_IN = 0.25             -- seconds for a beam to reach full strength

-- customParams.faction (lower case) -> build beam colour
local FACTION_COLOR = {
	choir   = { 0.85, 0.70, 1.00 },
	maw     = { 1.00, 0.45, 0.25 },
	tympan  = { 0.35, 0.70, 1.00 },
	miasma  = { 0.60, 1.00, 0.35 },
	haptic  = { 1.00, 0.85, 0.35 },
}
local DEFAULT_COLOR = { 0.30, 0.90, 0.40 }      -- the engine's own nano green
local REPAIR_COLOR  = { 0.45, 1.00, 0.78 }      -- the same for every faction, so a repair is recognised at a glance

-- model piece names to leave the beam from, best first (matched as lower-case substrings)
local PIECE_HINTS = { "nano", "beam", "emit", "muzzle", "flare", "laser", "weld", "gun", "hand", "arm", "head" }

--------------------------------------------------------------------------------

local spGetVisibleUnits   = Spring.GetVisibleUnits
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetUnitIsBuilding = Spring.GetUnitIsBuilding
local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitRadius     = Spring.GetUnitRadius
local spGetUnitHeight     = Spring.GetUnitHeight
local spGetUnitPieceMap   = Spring.GetUnitPieceMap
local spGetUnitPiecePosDir = Spring.GetUnitPiecePosDir
local spGetCameraPosition = Spring.GetCameraPosition
local spGetCameraVectors  = Spring.GetCameraVectors
local spIsSphereInView    = Spring.IsSphereInView
local spValidUnitID       = Spring.ValidUnitID

local glColor, glVertex, glBeginEnd = gl.Color, gl.Vertex, gl.BeginEnd
local GL_LINES, GL_LINE_STRIP, GL_LINE_LOOP, GL_POINTS = GL.LINES, GL.LINE_STRIP, GL.LINE_LOOP, GL.POINTS

local sin, cos, sqrt, floor, min, max, pi = math.sin, math.cos, math.sqrt, math.floor, math.min, math.max, math.pi
local lower, find = string.lower, string.find

local info = {}          -- unitDefID -> { build = bool, repair = bool, col = {r,g,b} }
local pieceOf = {}       -- unitDefID -> piece number, or false when the model has no fitting piece
local since = {}         -- unitID -> { kind, target, t0, last }: when this beam started (for the fade-in)

function gadget:Initialize()
	for defID, ud in pairs(UnitDefs) do
		if ud.isBuilder and (ud.buildSpeed or 0) > 0 and not ud.isFactory then
			local cp = ud.customParams or {}
			local kind = cp.kind
			if cp.iscommander == "true" then kind = "com" end
			local build = BUILD_KINDS[kind] == true
			if build or REPAIR_ENABLED then
				info[defID] = { build = build, repair = REPAIR_ENABLED, col = FACTION_COLOR[lower(cp.faction or "")] or DEFAULT_COLOR }
			end
		end
	end
	if next(info) == nil then gadgetHandler:RemoveGadget(self) end
end

--------------------------------------------------------------------------------
-- geometry helpers
--------------------------------------------------------------------------------

local function NanoPiece(uid, defID)
	local p = pieceOf[defID]
	if p ~= nil then return p end
	p = false
	local map = spGetUnitPieceMap and spGetUnitPieceMap(uid)
	if map then
		for _, hint in ipairs(PIECE_HINTS) do
			local bestName
			for name in pairs(map) do
				local n = lower(name)
				if find(n, hint, 1, true) and (not bestName or n < bestName) then bestName = n; p = map[name] end   -- alphabetical: stable
			end
			if bestName then break end
		end
	end
	pieceOf[defID] = p
	return p
end

local function SourcePoint(uid, defID)
	local piece = NanoPiece(uid, defID)
	if piece then
		local x, y, z = spGetUnitPiecePosDir(uid, piece)
		if x then return x, y, z end
	end
	local x, y, z = spGetUnitPosition(uid, true)
	if not x then return end
	return x, y + (spGetUnitRadius(uid) or 16) * 0.4, z
end

local function Ring(cx, cy, cz, r, n)
	glBeginEnd(GL_LINE_LOOP, function()
		for i = 0, n - 1 do
			local a = i / n * 2 * pi
			glVertex(cx + cos(a) * r, cy, cz + sin(a) * r)
		end
	end)
end

local function Points(list)          -- list of { x, y, z, alpha }, colour already set by the caller through the 5th..7th numbers
	glBeginEnd(GL_POINTS, function()
		for i = 1, #list do
			local p = list[i]
			glColor(p[5], p[6], p[7], p[4])
			glVertex(p[1], p[2], p[3])
		end
	end)
end

--------------------------------------------------------------------------------
-- BUILD: shimmering beam, streaming packets, scan ring
--------------------------------------------------------------------------------

local function DrawBuild(ax, ay, az, bx, by, bz, len, col, a, now, tx, ty, tz, tr, th)
	local r, g, b = col[1], col[2], col[3]
	local segs = max(4, min(16, floor(len / 25)))
	local dx, dy, dz = (bx - ax) / len, (by - ay) / len, (bz - az) / len
	-- two sideways axes for the shimmer
	local ux, uy, uz = -dz, 0, dx
	local ul = sqrt(ux * ux + uz * uz)
	if ul < 0.001 then ux, uz, ul = 1, 0, 1 end
	ux, uz = ux / ul, uz / ul

	local function Beam()
		for i = 0, segs do
			local u = i / segs
			local w = (i == 0 or i == segs) and 0 or 1.4 * sin(now * 28 + i * 1.7)
			glVertex(ax + (bx - ax) * u + ux * w, ay + (by - ay) * u + w * 0.5, az + (bz - az) * u + uz * w)
		end
	end
	gl.LineWidth(8); glColor(r, g, b, 0.16 * a); glBeginEnd(GL_LINE_STRIP, Beam)         -- halo
	gl.LineWidth(3); glColor(r, g, b, 0.60 * a); glBeginEnd(GL_LINE_STRIP, Beam)         -- body
	gl.LineWidth(1.2); glColor(1, 1, 1, 0.85 * a); glBeginEnd(GL_LINE_STRIP, Beam)       -- hot core

	-- packets of material flowing from the builder into the new unit
	local pts, n = {}, 7
	for i = 0, n - 1 do
		local u = (now * 1.5 + i / n) % 1
		local f = sin(pi * u)
		pts[#pts + 1] = { ax + (bx - ax) * u, ay + (by - ay) * u, az + (bz - az) * u, a * (0.25 + 0.75 * f), r * 0.5 + 0.5, g * 0.5 + 0.5, b * 0.5 + 0.5 }
	end
	gl.PointSize(7); Points(pts)

	-- scan ring sweeping up and down the unit under construction
	local s = (now * 0.8) % 1
	local tri = s < 0.5 and s * 2 or (1 - s) * 2
	local rr = tr * 0.9
	gl.LineWidth(2); glColor(r, g, b, 0.75 * a); Ring(tx, ty + th * tri, tz, rr, 28)
	gl.LineWidth(1); glColor(r, g, b, 0.25 * a); Ring(tx, ty + th * max(0, tri - 0.08), tz, rr, 28)
	-- glow where the beam lands
	gl.PointSize(11); Points({ { bx, by, bz, 0.5 * a, 1, 1, 1 } })
end

--------------------------------------------------------------------------------
-- REPAIR: mint double helix, rising sparkles, pulse ring, floating "+"
--------------------------------------------------------------------------------

local camRight, camUp = { 1, 0, 0 }, { 0, 1, 0 }

local function DrawRepair(ax, ay, az, bx, by, bz, len, a, now, tx, ty, tz, tr, th)
	local r, g, b = REPAIR_COLOR[1], REPAIR_COLOR[2], REPAIR_COLOR[3]
	local dx, dy, dz = (bx - ax) / len, (by - ay) / len, (bz - az) / len
	-- axes perpendicular to the beam
	local hx, hy, hz = 0, 1, 0
	if math.abs(dy) > 0.95 then hx, hy, hz = 1, 0, 0 end
	local ux, uy, uz = dy * hz - dz * hy, dz * hx - dx * hz, dx * hy - dy * hx
	local ul = sqrt(ux * ux + uy * uy + uz * uz)
	ux, uy, uz = ux / ul, uy / ul, uz / ul
	local vx, vy, vz = dy * uz - dz * uy, dz * ux - dx * uz, dx * uy - dy * ux

	-- thin straight core
	gl.LineWidth(1.5); glColor(r, g, b, 0.30 * a)
	glBeginEnd(GL_LINES, function() glVertex(ax, ay, az); glVertex(bx, by, bz) end)

	-- the helix: two strands half a turn apart, tapering into both ends
	local segs = max(10, min(40, floor(len / 8)))
	local amp = 4 + min(len, 300) * 0.02
	local turns = max(1.5, len / 45)
	local phase = now * 6
	for strand = 0, 1 do
		local off = strand * pi
		local function Strand()
			for i = 0, segs do
				local u = i / segs
				local w = amp * sin(pi * u)
				local ang = u * turns * 2 * pi - phase + off
				local c, s = cos(ang) * w, sin(ang) * w
				glVertex(ax + (bx - ax) * u + ux * c + vx * s, ay + (by - ay) * u + uy * c + vy * s, az + (bz - az) * u + uz * c + vz * s)
			end
		end
		gl.LineWidth(5); glColor(r, g, b, 0.14 * a); glBeginEnd(GL_LINE_STRIP, Strand)
		gl.LineWidth(2); glColor(r, g, b, 0.80 * a); glBeginEnd(GL_LINE_STRIP, Strand)
	end

	-- sparkles rising round the repaired unit
	local pts, n = {}, 12
	for i = 0, n - 1 do
		local t = (now * 0.65 + i / n) % 1
		local ang = i * 2.4 + now * 1.6
		local rr = tr * (0.55 + 0.25 * sin(i * 1.3))
		pts[#pts + 1] = { tx + cos(ang) * rr, ty + th * t, tz + sin(ang) * rr, a * sin(pi * t), 0.8, 1, 0.9 }
	end
	gl.PointSize(5); Points(pts)

	-- pulse ring spreading on the ground below the unit
	local p = (now * 1.0) % 1
	gl.LineWidth(2); glColor(r, g, b, 0.7 * (1 - p) * a)
	Ring(tx, ty + 3, tz, tr * (0.4 + 0.9 * p), 28)

	-- the "+" floating above the unit, always facing the camera
	local cy = ty + th + 10 + 3 * sin(now * 3)
	local k = max(5, min(14, tr * 0.25))
	local rx, ry, rz = camRight[1], camRight[2], camRight[3]
	local px, py, pz = camUp[1], camUp[2], camUp[3]
	gl.LineWidth(3); glColor(0.9, 1, 0.95, 0.9 * a)
	glBeginEnd(GL_LINES, function()
		glVertex(tx - rx * k, cy - ry * k, tz - rz * k); glVertex(tx + rx * k, cy + ry * k, tz + rz * k)
		glVertex(tx - px * k, cy - py * k, tz - pz * k); glVertex(tx + px * k, cy + py * k, tz + pz * k)
	end)
	gl.LineWidth(7); glColor(r, g, b, 0.22 * a)
	glBeginEnd(GL_LINES, function()
		glVertex(tx - rx * k, cy - ry * k, tz - rz * k); glVertex(tx + rx * k, cy + ry * k, tz + rz * k)
		glVertex(tx - px * k, cy - py * k, tz - pz * k); glVertex(tx + px * k, cy + py * k, tz + pz * k)
	end)
	gl.PointSize(10); Points({ { bx, by, bz, 0.45 * a, 0.9, 1, 0.95 } })
end

--------------------------------------------------------------------------------

function gadget:DrawWorld()
	local now = os.clock()
	local units = spGetVisibleUnits(-1, nil, false)
	if not units then return end

	local cx, cy, cz = spGetCameraPosition()
	local maxD2 = MAX_DISTANCE * MAX_DISTANCE
	local cv = spGetCameraVectors and spGetCameraVectors()
	if cv then camRight, camUp = cv.right or camRight, cv.up or camUp end

	local drawn, started = 0, false
	for i = 1, #units do
		local uid = units[i]
		local inf = info[spGetUnitDefID(uid)]
		local tid = inf and spGetUnitIsBuilding(uid)
		if tid and spValidUnitID(tid) then
			local kind = spGetUnitIsBeingBuilt(tid) and "build" or "repair"
			if (kind == "build" and inf.build) or (kind == "repair" and inf.repair) then
				local ax, ay, az = SourcePoint(uid, spGetUnitDefID(uid))
				local bx, by, bz = spGetUnitPosition(tid, true)
				if ax and bx then
					local dx, dy, dz = bx - ax, by - ay, bz - az
					local len = sqrt(dx * dx + dy * dy + dz * dz)
					local d2 = (ax - cx) ^ 2 + (ay - cy) ^ 2 + (az - cz) ^ 2
					if len > 1 and d2 < maxD2 and spIsSphereInView((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, len / 2 + 60) then
						local st = since[uid]
						if not st or st.kind ~= kind or st.target ~= tid or now - st.last > 0.5 then
							st = { kind = kind, target = tid, t0 = now }
							since[uid] = st
						end
						st.last = now
						local a = min(1, (now - st.t0) / FADE_IN)

						if not started then
							started = true
							gl.Texture(false)
							gl.DepthTest(true)
							gl.DepthMask(false)
							gl.Blending(GL.SRC_ALPHA, GL.ONE)
						end
						local _, ty = spGetUnitPosition(tid)                    -- base height of the target
						local tx, _, tz = bx, 0, bz
						local tr = max(12, (spGetUnitRadius(tid) or 16) * 0.9)
						local th = max(14, spGetUnitHeight(tid) or (tr * 1.5))
						if kind == "build" then
							DrawBuild(ax, ay, az, bx, by, bz, len, inf.col, a, now, tx, ty or by, tz, tr, th)
						else
							DrawRepair(ax, ay, az, bx, by, bz, len, a, now, tx, ty or by, tz, tr, th)
						end
						drawn = drawn + 1
						if drawn >= MAX_BUILDERS then break end
					end
				end
			end
		end
	end

	if started then
		gl.LineWidth(1)
		gl.PointSize(1)
		gl.Color(1, 1, 1, 1)
		gl.Blending(true)
		gl.DepthMask(true)
		gl.DepthTest(true)
	end

	for uid, st in pairs(since) do                                  -- forget beams that ended
		if now - st.last > 1 then since[uid] = nil end
	end
end

function gadget:UnitDestroyed(uid) since[uid] = nil end
