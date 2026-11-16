function gadget:GetInfo()
	return {
		name    = "Voidborn gray matter + mushrooms",
		desc    = "A dead unit shrinks into gray matter; left alone, it sprouts 3D mushrooms that are reclaimable energy and grow toward a tanh cap",
		author  = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 3, enabled = true,
	}
end

--------------------------------------------------------------------------------
-- How it works
--
--  * When a finished unit dies, a "vb_graymatter" feature is created where it fell
--    (features/vb_graymatter.lua).  The engine's own reclaim logic does the rest: any builder
--    that can reclaim (Nurse, Weeper, ...) can eat it, and the energy goes to that team.
--  * The feature holds energy E.  The maximum is the dead unit's max health / HEALTH_DIV (15).  Fresh gray matter holds SEED_FRAC of it.  While nobody
--    reclaims it, E follows a tangent-hyperbolic curve toward the maximum:
--          E(t) = seed + (max - seed) * tanh(t / GROW_SECS)
--    so it grows fast at first, then flattens and never passes the cap.  Reclaiming takes energy
--    out, and the curve then continues from the lower value, so a half-eaten patch regrows.
--  * Size is drawn from the same number: growth G = tanh(t / GROW_SECS) in 0..1.  The unsynced
--    half draws the dying unit shrinking into a lump of gray matter, then several 3D mushrooms
--    (eight shapes) sprouting out of it in random directions, each when G passes its own threshold.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Tunables (the first two can also be set as mod options, see modoptions.lua)
--------------------------------------------------------------------------------
local FEATURE_NAME  = "vb_graymatter"
local GROW_SECS     = 150     -- time constant: 76% grown after this long abandoned, 96% after twice as long
local HEALTH_DIV    = 15      -- energy at full growth = the dead unit's max health / this (1500 health -> 100 energy)
local SEED_FRAC     = 0.20    -- fresh gray matter holds this fraction of the maximum
local MAX_ENERGY    = 19000   -- hard cap for one patch (the feature def holds 20000)
local MAX_FUNGI     = 250     -- most patches alive at once; a new one replaces the smallest
local VOID_HEIGHT   = 30      -- ground lower than this is the void: the patch then floats where the unit died
local MAX_ELMOS     = 220     -- hard ceiling on the mushroom size scale in elmos
local POLL_FRAMES   = 15      -- growth is updated twice a second
local RECLAIM_E_PER_SEC = 50  -- energy per second one reclaimer of the reference speed takes (a Nurse or Weeper, reclaimSpeed 30.4);
                                  -- faster reclaimers (Seer 56, Hierophant 76) and several at once take proportionally more
local REF_RECLAIM_SPEED = 30.4
local RECLAIM_PER_E   = REF_RECLAIM_SPEED / RECLAIM_E_PER_SEC   -- reclaim time per energy: time = energy * this, taken at reclaimSpeed per second
local SHRINK_SECS   = 1.8     -- how long the dead unit takes to collapse into gray matter

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function Tanh(x)
	if x > 20 then return 1 elseif x < -20 then return -1 end
	local e = math.exp(2 * x)
	return (e - 1) / (e + 1)
end
local function Atanh(y) return 0.5 * math.log((1 + y) / (1 - y)) end

-- the mushroom size scale (elmos) for a growth G in 0..1: it starts at 0.6 x the unit's radius and
-- ends at 3 x, never above MAX_ELMOS
local function SizeScale(baseR, G) return math.min(MAX_ELMOS, baseR * (0.6 + 2.4 * G)) end

--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
--------------------------------------------------------------------------------
	local spGetFeatureResources, spSetFeatureResources = Spring.GetFeatureResources, Spring.SetFeatureResources
	local fungi, count = {}, 0         -- featureID -> state
	local enabled = true
	local resourceMode = nil           -- "live" | "fixed", found out the first time (see PushEnergy)

	local function ReadModOptions()
		local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
		if mo.mush_enabled == "0" or mo.mush_enabled == "false" then enabled = false end
		local v = tonumber(mo.mush_grow_secs)
		if v then GROW_SECS = Clamp(v, 10, 1800) end
		v = tonumber(mo.mush_health_div)
		if v then HEALTH_DIV = Clamp(v, 1, 200) end
	end

	-- growth state <-> energy.  G < 0 is "eaten below the seed": it continues the curve linearly
	-- (tanh is almost linear around 0, so the two halves join smoothly).
	local function Gof(age)  if age >= 0 then return Tanh(age / GROW_SECS) end return age / GROW_SECS end
	local function AgeOf(G)  if G >= 0 then return GROW_SECS * Atanh(math.min(G, 0.995)) end return GROW_SECS * G end
	local function EnergyOf(f, age) return math.max(0, f.seed + (f.cap - f.seed) * Gof(age)) end
	local function GrowthOf(f, E) return (E - f.seed) / (f.cap - f.seed) end

	-- How much energy is left in a feature.  Engines differ a little in what Spring.SetFeatureResources
	-- changes, so PushEnergy checks once whether the "default" amount follows what we set ("live") or
	-- stays at the feature def's value ("fixed"); in the second case the energy is carried by reclaimLeft.
	local function ReadEnergy(fid)
		local _, _, e, defE, left = spGetFeatureResources(fid)
		if not e then return nil end
		-- reclaiming lowers reclaimLeft, so what is left is always (full amount) x reclaimLeft
		if defE and left then return defE * left end
		return e
	end

	local function PushEnergy(fid, f, E)
		E = math.max(E, 0.01)
		local rt = math.max(2, E * RECLAIM_PER_E)
		spSetFeatureResources(fid, 0, E, rt, 1)
		if not resourceMode then
			local _, _, _, defE = spGetFeatureResources(fid)
			resourceMode = (defE and math.abs(defE - E) > math.max(1, E * 0.02)) and "fixed" or "live"
			Spring.Echo("[VB] mushrooms: feature resources are '" .. resourceMode .. "'")
		end
		if resourceMode == "fixed" then
			local _, _, _, defE = spGetFeatureResources(fid)
			-- here the engine takes defE * reclaimLeft, so the reclaim time has to be for the full defE
			if defE and defE > 0 then spSetFeatureResources(fid, 0, E, math.max(2, defE * RECLAIM_PER_E), math.min(1, E / defE)) end
		end
		f.lastE = E
		if E > (f.peak or 0) then f.peak = E end
	end

	-- the hitbox (for right-click reclaim) follows the visible size
	local function Fit(fid, f, G)
		local S = SizeScale(f.baseR, G)
		local rb = f.baseR * 0.5
		local h = math.max(24, rb * 0.8 + S * 1.1 * math.min(1, G * 4))
		local w = math.max(30, rb * 2 + S * 0.9 * math.min(1, G * 3))
		if f.fitH and math.abs(h - f.fitH) < 0.1 * f.fitH then return end
		f.fitH = h
		pcall(Spring.SetFeatureCollisionVolumeData, fid, w, h, w, 0, f.floating and 0 or h * 0.5, 0, 0, 1, 1)
		if Spring.SetFeatureRadiusAndHeight then pcall(Spring.SetFeatureRadiusAndHeight, fid, w * 0.5, h) end
	end

	local function Publish(fid, f, E)
		local G = GrowthOf(f, E)
		Spring.SetFeatureRulesParam(fid, "vb_g", math.max(G, 0), { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_b", math.min(1, E / f.seed), { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_w", f.wilt or 0, { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_rate", f.rate or 0, { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_e", E, { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_c", f.cap, { public = true })
		Fit(fid, f, math.max(G, 0))
	end

	local function Update(fid, f)
		local E = ReadEnergy(fid)
		if not E then return end
		if f.lastE and E < f.lastE - math.max(0.05, f.lastE * 0.0005) then
			local raw = (f.lastE - E) / (POLL_FRAMES / 30)
			f.rate = f.rate and (f.rate * 0.5 + raw * 0.5) or raw       -- energy per second being taken, smoothed
			-- somebody is reclaiming: no growth, and the curve continues from what is left
			f.age = AgeOf(GrowthOf(f, E))
			f.lastE = E
			f.wilt = Clamp(1 - E / math.max(f.peak or E, 0.01), 0, 1)    -- the more is eaten, the more it droops
		else
			f.wilt, f.rate = 0, 0
			f.age = f.age + POLL_FRAMES / 30
			E = EnergyOf(f, f.age)
			PushEnergy(fid, f, E)
			f.peak = E                                                   -- the next reclaim starts its progress bar from here
		end
		Publish(fid, f, E)
	end

	local function DropSmallest()
		local worst, worstE
		for fid, f in pairs(fungi) do
			if not worstE or (f.lastE or 0) < worstE then worst, worstE = fid, f.lastE or 0 end
		end
		if worst then Spring.DestroyFeature(worst) end   -- FeatureDestroyed does the bookkeeping
	end

	function gadget:Initialize()
		ReadModOptions()
		if not FeatureDefNames or not FeatureDefNames[FEATURE_NAME] then
			Spring.Echo("[VB] mushrooms: feature def '" .. FEATURE_NAME .. "' is missing, gadget disabled")
			gadgetHandler:RemoveGadget(self)
		end
	end

	function gadget:UnitDestroyed(unitID, unitDefID, teamID)
		if not enabled then return end
		local ud = UnitDefs[unitDefID]
		if not ud then return end
		if ud.customParams and ud.customParams.nomushroom then return end
		-- unfinished units and units that were reclaimed (their build progress is eaten away) leave nothing
		local _, maxHealth, _, _, build = Spring.GetUnitHealth(unitID)
		if build and build < 1 then return end
		local x, y, z = Spring.GetUnitPosition(unitID)
		if not x then return end

		local gh = Spring.GetGroundHeight(x, z) or 0
		local floating = (gh < VOID_HEIGHT) or (y - gh > 600)
		local fy = floating and y or gh

		local cap = Clamp((maxHealth or ud.health or 100) / HEALTH_DIV, 2, MAX_ENERGY)
		local seed = math.max(cap * SEED_FRAC, 0.5)
		local baseR = Clamp(Spring.GetUnitRadius(unitID) or 20, 14, 120)

		if count >= MAX_FUNGI then DropSmallest() end
		local heading = Spring.GetUnitHeading(unitID) or 0
		local fid = Spring.CreateFeature(FEATURE_NAME, x, fy, z, heading, Spring.GetUnitAllyTeam(unitID))
		if not fid then return end

		if Spring.SetFeatureNoSelect then pcall(Spring.SetFeatureNoSelect, fid, false) end
		if Spring.SetFeatureReclaimable then pcall(Spring.SetFeatureReclaimable, fid, true) end                  -- the unsynced half draws the gray matter and mushrooms
		if floating then pcall(Spring.SetFeatureMoveCtrl, fid, true) end   -- stays where it is instead of falling into the void

		local f = { cap = cap, seed = seed, age = 0, baseR = baseR, floating = floating }
		fungi[fid] = f
		count = count + 1
		PushEnergy(fid, f, seed)

		local dx, _, dz = Spring.GetUnitDirection(unitID)
		Spring.SetFeatureRulesParam(fid, "vb_r", baseR, { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_fl", floating and 1 or 0, { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_dx", dx or 0, { public = true })
		Spring.SetFeatureRulesParam(fid, "vb_dz", dz or 1, { public = true })
		Publish(fid, f, seed)
		-- the unsynced half plays the collapse of the dead unit's own model
		SendToUnsynced("vbgm", fid, unitDefID, teamID, y)
	end

	function gadget:FeatureDestroyed(fid)
		if fungi[fid] then fungi[fid] = nil; count = count - 1 end
	end

	function gadget:GameFrame(n)
		if n % POLL_FRAMES ~= 0 then return end
		for fid, f in pairs(fungi) do Update(fid, f) end
	end

--------------------------------------------------------------------------------
else  -- UNSYNCED: the gray matter, the shrinking unit and the 3D mushrooms
--------------------------------------------------------------------------------
	local glPushMatrix, glPopMatrix, glTranslate, glRotate, glScale = gl.PushMatrix, gl.PopMatrix, gl.Translate, gl.Rotate, gl.Scale
	local glCallList, glColor = gl.CallList, gl.Color
	local sin, cos, sqrt, floor, min, max, pi = math.sin, math.cos, math.sqrt, math.floor, math.min, math.max, math.pi

	local function Hash(seed, k)
		local s = sin(seed * 12.9898 + k * 78.233) * 43758.5453
		return s - floor(s)
	end

	----------------------------------------------------------------------------
	-- Meshes.  Everything is generated here (no model files): surfaces of revolution for the
	-- mushrooms, a bumpy sphere for the gray matter.  Lighting is baked into the vertex colors.
	----------------------------------------------------------------------------
	local LX, LY, LZ = 0.35, 0.80, 0.48
	do local l = sqrt(LX * LX + LY * LY + LZ * LZ); LX, LY, LZ = LX / l, LY / l, LZ / l end
	local SEG = 24

	local function P(r, y, col, o)
		o = o or {}
		return { r = r, y = y, c = col, em = o.em or 0, gill = o.gill, pit = o.pit or 0, ruf = o.ruf or 0, spot = o.spot }
	end

	-- A profile is traced from the middle of the base, up the outside of the stalk, out along the
	-- underside of the cap, round the rim and back over the top to the apex; that keeps every normal pointing out.
	local function Lathe(acc, glows, profile, o)
		o = o or {}
		local sc, ox, oz, lean, ph = o.sc or 1, o.ox or 0, o.oz or 0, o.lean or 0, o.ph or 0
		local glowCol = o.glow
		local n = #profile
		local ring = {}
		for i = 1, n do
			local p = profile[i]
			local a, b = profile[max(1, i - 1)], profile[min(n, i + 1)]
			local tr, ty = b.r - a.r, b.y - a.y
			local len = sqrt(tr * tr + ty * ty)
			if len < 1e-6 then tr, ty, len = 0, 1, 1 end
			local nr, ny = ty / len, -tr / len
			local row = {}
			for s = 0, SEG - 1 do
				local th = s * 2 * pi / SEG
				local c, sn = cos(th), sin(th)
				local pitWave = sin(8 * th + p.y * 14 + ph)
				local w = 1 + p.pit * pitWave + p.ruf * sin(9 * th + ph * 2)
				local r, y = p.r * w * sc, p.y * sc
				local x, z = ox + r * c + lean * y * y, oz + r * sn
				local shade = 0.42 + 0.58 * max(0, nr * c * LX + ny * LY + nr * sn * LZ)
				if p.gill then shade = shade * ((s % 2 == 0) and 1.0 or 0.72) end
				if p.pit ~= 0 then shade = shade * (0.78 + 0.22 * pitWave) end
				local k = shade * (1 - p.em) + 1.2 * p.em
				row[s] = { x, y, z, p.c[1] * k, p.c[2] * k, p.c[3] * k }
				if p.spot and s % p.spot == 0 then glows[#glows + 1] = { x, y, z, 0.05 * sc } end
			end
			ring[i] = row
		end
		for i = 1, n - 1 do
			for s = 0, SEG - 1 do
				local s2 = (s + 1) % SEG
				local v1, v2, v3, v4 = ring[i][s], ring[i][s2], ring[i + 1][s2], ring[i + 1][s]
				acc[#acc + 1] = v1; acc[#acc + 1] = v2; acc[#acc + 1] = v3
				acc[#acc + 1] = v1; acc[#acc + 1] = v3; acc[#acc + 1] = v4
			end
		end
	end

	local function EmitTriangles(acc)
		gl.BeginEnd(GL.TRIANGLES, function()
			for i = 1, #acc do
				local v = acc[i]
				glColor(v[4], v[5], v[6], 1)
				gl.Vertex(v[1], v[2], v[3])
			end
		end)
	end

	local function EmitGlows(glows)
		gl.BeginEnd(GL.TRIANGLES, function()
			for i = 1, #glows do
				local g = glows[i]
				local x, y, z, s = g[1], g[2], g[3], g[4]
				local px, nx, py, ny, pz, nz = { x + s, y, z }, { x - s, y, z }, { x, y + s, z }, { x, y - s, z }, { x, y, z + s }, { x, y, z - s }
				local tri = { { py, px, pz }, { py, pz, nx }, { py, nx, nz }, { py, nz, px }, { ny, pz, px }, { ny, nx, pz }, { ny, nz, nx }, { ny, px, nz } }
				for t = 1, 8 do
					for k = 1, 3 do local v = tri[t][k]; gl.Vertex(v[1], v[2], v[3]) end
				end
			end
		end)
	end

	-- palettes: stalk, underside, cap, rim, glow
	local PAL = {
		ash      = { stalk = { 0.80, 0.79, 0.76 }, gill = { 0.28, 0.27, 0.26 }, cap = { 0.45, 0.44, 0.42 }, rim = { 0.60, 0.58, 0.55 }, glow = { 0.75, 0.80, 0.78 } },
		slate    = { stalk = { 0.76, 0.78, 0.80 }, gill = { 0.22, 0.25, 0.28 }, cap = { 0.38, 0.42, 0.46 }, rim = { 0.55, 0.60, 0.65 }, glow = { 0.70, 0.80, 0.85 } },
		mauve    = { stalk = { 0.80, 0.76, 0.77 }, gill = { 0.28, 0.22, 0.25 }, cap = { 0.48, 0.40, 0.45 }, rim = { 0.62, 0.55, 0.58 }, glow = { 0.80, 0.75, 0.80 } },
		bone     = { stalk = { 0.88, 0.85, 0.78 }, gill = { 0.35, 0.33, 0.28 }, cap = { 0.62, 0.58, 0.50 }, rim = { 0.75, 0.72, 0.62 }, glow = { 0.85, 0.85, 0.70 } },
		moss     = { stalk = { 0.78, 0.80, 0.72 }, gill = { 0.22, 0.25, 0.20 }, cap = { 0.36, 0.40, 0.32 }, rim = { 0.52, 0.56, 0.46 }, glow = { 0.75, 0.82, 0.70 } },
		umber    = { stalk = { 0.82, 0.78, 0.70 }, gill = { 0.27, 0.22, 0.18 }, cap = { 0.46, 0.38, 0.30 }, rim = { 0.62, 0.55, 0.45 }, glow = { 0.85, 0.80, 0.70 } },
		fog      = { stalk = { 0.84, 0.86, 0.88 }, gill = { 0.25, 0.28, 0.32 }, cap = { 0.50, 0.54, 0.58 }, rim = { 0.68, 0.72, 0.76 }, glow = { 0.80, 0.85, 0.90 } },
		charcoal = { stalk = { 0.70, 0.70, 0.68 }, gill = { 0.18, 0.18, 0.20 }, cap = { 0.30, 0.30, 0.32 }, rim = { 0.50, 0.50, 0.52 }, glow = { 0.70, 0.75, 0.75 } },
	}

	-- the shapes: each returns a profile; heights are about 1.0 to 1.7 and radii about 0.4 to 1.2
	local SHAPES = {}
	function SHAPES.dome(p)
		return {
			P(0, 0, p.stalk), P(0.20, 0, p.stalk), P(0.15, 0.08, p.stalk), P(0.105, 0.30, p.stalk), P(0.09, 0.55, p.stalk),
			P(0.11, 0.60, p.gill, { gill = true }), P(0.36, 0.58, p.gill, { gill = true }), P(0.64, 0.60, p.gill, { gill = true }),
			P(0.82, 0.68, p.rim, { em = 0.6, spot = 6 }),
			P(0.80, 0.80, p.cap), P(0.64, 0.94, p.cap), P(0.42, 1.03, p.cap), P(0.17, 1.08, p.cap), P(0, 1.095, p.cap),
		}
	end
	function SHAPES.bell(p)
		return {
			P(0, 0, p.stalk), P(0.14, 0, p.stalk), P(0.09, 0.12, p.stalk), P(0.06, 0.50, p.stalk), P(0.05, 0.95, p.stalk),
			P(0.07, 1.00, p.gill, { gill = true }), P(0.28, 0.97, p.gill, { gill = true }),
			P(0.44, 1.00, p.rim, { em = 0.5, spot = 8 }),
			P(0.42, 1.10, p.cap), P(0.33, 1.28, p.cap), P(0.20, 1.46, p.cap), P(0.08, 1.58, p.cap), P(0, 1.62, p.cap),
		}
	end
	function SHAPES.parasol(p)
		return {
			P(0, 0, p.stalk), P(0.10, 0, p.stalk), P(0.05, 0.20, p.stalk), P(0.04, 0.90, p.stalk),
			P(0.05, 0.95, p.gill, { gill = true }), P(0.50, 0.92, p.gill, { gill = true }), P(1.00, 0.97, p.gill, { gill = true, ruf = 0.07 }),
			P(1.15, 1.03, p.rim, { em = 0.7, spot = 4, ruf = 0.10 }),
			P(1.05, 1.10, p.cap, { ruf = 0.07 }), P(0.70, 1.17, p.cap), P(0.35, 1.22, p.cap), P(0.10, 1.25, p.cap), P(0, 1.26, p.cap),
		}
	end
	function SHAPES.morel(p)
		return {
			P(0, 0, p.stalk), P(0.22, 0, p.stalk), P(0.16, 0.10, p.stalk), P(0.13, 0.35, p.stalk), P(0.15, 0.45, p.stalk),
			P(0.32, 0.50, p.cap, { pit = 0.06 }), P(0.50, 0.75, p.cap, { pit = 0.09 }), P(0.52, 1.05, p.cap, { pit = 0.10 }),
			P(0.42, 1.35, p.cap, { pit = 0.10 }), P(0.25, 1.55, p.cap, { pit = 0.08, em = 0.15 }), P(0.08, 1.65, p.cap), P(0, 1.67, p.cap),
		}
	end
	function SHAPES.stinkhorn(p)
		return {
			P(0, 0, p.stalk), P(0.20, 0, p.stalk), P(0.22, 0.10, p.gill), P(0.12, 0.25, p.stalk), P(0.085, 0.50, p.stalk), P(0.09, 1.00, p.stalk),
			P(0.16, 1.08, p.cap), P(0.18, 1.28, p.cap, { em = 0.2, spot = 6 }), P(0.13, 1.50, p.cap),
			P(0.05, 1.62, p.rim, { em = 0.9 }), P(0, 1.66, p.rim, { em = 0.9 }),
		}
	end

	local FORMS = {                         -- 8 looks: shape x palette
		{ shape = "dome", pal = "ash" }, { shape = "dome", pal = "mauve" }, { shape = "bell", pal = "slate" },
		{ shape = "parasol", pal = "bone" }, { shape = "morel", pal = "umber" }, { shape = "stinkhorn", pal = "moss" },
		{ shape = "cluster", pal = "fog" }, { shape = "bell", pal = "charcoal" },
	}
	local CLUSTER = {                       -- ox, oz, scale, lean
		{ 0, 0, 0.55, 0.05 }, { 0.42, 0.10, 0.38, -0.18 }, { -0.35, 0.30, 0.42, 0.15 }, { 0.10, -0.45, 0.30, 0.10 }, { -0.20, -0.40, 0.26, -0.12 },
	}

	local lists = {}                        -- built in Initialize: lists.forms[i] = { solid, glow, col }, lists.blobs[i]
	local function BuildForm(form, idx)
		local pal = PAL[form.pal]
		local acc, glows = {}, {}
		if form.shape == "cluster" then
			for i, c in ipairs(CLUSTER) do
				Lathe(acc, glows, SHAPES.dome(pal), { ox = c[1], oz = c[2], sc = c[3], lean = c[4], ph = i })
			end
		else
			Lathe(acc, glows, SHAPES[form.shape](pal), { ph = idx })
		end
		return {
			solid = gl.CreateList(function() EmitTriangles(acc) end),
			glow  = gl.CreateList(function() EmitGlows(glows) end),
			col   = pal.glow,
		}
	end

	-- the gray matter: a bumpy, folded lump (a sphere of radius ~1, squashed when drawn)
	local function BuildBlob(seed)
		local rings, segs = 9, 14
		local grid = {}
		for i = 0, rings do
			grid[i] = {}
			for s = 0, segs - 1 do
				local ph, th = pi * i / rings, 2 * pi * s / segs
				local lump = 1 + 0.10 * sin(3 * th + seed) * sin(2 * ph) + 0.07 * sin(5 * ph + 2 * th + seed * 2) + 0.05 * sin(7 * th + 3 * ph)
				local fold = 0.82 + 0.18 * sin(9 * th + 5 * sin(3 * ph + seed))
				local dx, dy, dz = sin(ph) * cos(th), cos(ph), sin(ph) * sin(th)
				local shade = 0.40 + 0.60 * max(0, dx * LX + dy * LY + dz * LZ)
				local g = 0.50 * fold * shade
				grid[i][s] = { dx * lump, dy * lump, dz * lump, g * 1.02 + 0.06 * (1 - fold), g * 0.98, g * 1.05 }
			end
		end
		local acc = {}
		for i = 0, rings - 1 do
			for s = 0, segs - 1 do
				local s2 = (s + 1) % segs
				local v1, v2, v3, v4 = grid[i][s], grid[i][s2], grid[i + 1][s2], grid[i + 1][s]
				acc[#acc + 1] = v1; acc[#acc + 1] = v2; acc[#acc + 1] = v3
				acc[#acc + 1] = v1; acc[#acc + 1] = v3; acc[#acc + 1] = v4
			end
		end
		return gl.CreateList(function() EmitTriangles(acc) end)
	end

	----------------------------------------------------------------------------
	-- Patches (one per feature)
	----------------------------------------------------------------------------
	local patches = {}                      -- featureID -> state
	local pendingAnim = {}                  -- featureID -> { defID, team, y0 } (event arrived before the patch was scanned)
	local lastScan = -1000
	local unitShapeOK = true
	local NSLOTS_MAX = 9
	local SQUASH = 0.78

	local function MakeSlots(fid, baseR, floating)
		local n = Clamp(3 + floor(baseR / 12), 3, NSLOTS_MAX)
		local slots = {}
		for j = 1, n do
			local az = 2 * pi * Hash(fid, j * 7 + 1)
			local up = floating and (-0.6 + 1.6 * Hash(fid, j * 7 + 2)) or (0.30 + 0.70 * Hash(fid, j * 7 + 2))
			local hz = sqrt(max(0, 1 - up * up))
			local dx, dy, dz = hz * cos(az), up, hz * sin(az)            -- where on the lump it sprouts
			-- the mushroom leans a little toward "up"
			local ax, ay, az2 = dx, dy + 0.3, dz
			local al = sqrt(ax * ax + ay * ay + az2 * az2); ax, ay, az2 = ax / al, ay / al, az2 / al
			local angle, rx, ry, rz = 0, 1, 0, 0
			if ay < -0.999 then angle, rx, ry, rz = 180, 1, 0, 0
			elseif ay < 0.999 then angle, rx, ry, rz = math.deg(math.acos(ay)), az2, 0, -ax end
			slots[j] = {
				dx = dx, dy = dy, dz = dz,
				angle = angle, rx = rx, ry = ry, rz = rz,
				form = 1 + floor(Hash(fid, j * 7 + 3) * #FORMS),
				size = 0.5 + 0.8 * Hash(fid, j * 7 + 4),
				th = (j - 1) / n * 0.6,                                -- growth at which this one starts to sprout
				spin = 360 * Hash(fid, j * 7 + 5),
				ph = 2 * pi * Hash(fid, j * 7 + 6),
			}
		end
		return slots
	end

	local function NewPatch(fid, t0)
		local defID = Spring.GetFeatureDefID(fid)
		if not defID or FeatureDefs[defID].name ~= "vb_graymatter" then return nil end
		local x, y, z = Spring.GetFeaturePosition(fid)
		if not x then return nil end
		local baseR = Spring.GetFeatureRulesParam(fid, "vb_r") or 24
		local floating = (Spring.GetFeatureRulesParam(fid, "vb_fl") or 0) == 1
		local dx, dz = Spring.GetFeatureRulesParam(fid, "vb_dx") or 0, Spring.GetFeatureRulesParam(fid, "vb_dz") or 1
		local p = {
			x = x, y = y, z = z, baseR = baseR, floating = floating,
			yaw = math.deg(atan2(dx, dz)),
			g = Spring.GetFeatureRulesParam(fid, "vb_g") or 0,
			b = Spring.GetFeatureRulesParam(fid, "vb_b") or 1,
			t0 = t0, y0 = y, blob = 1 + floor(Hash(fid, 99) * 3),
			slots = MakeSlots(fid, baseR, floating),
		}
		local a = pendingAnim[fid]
		if a then p.defID, p.team, p.y0 = a.defID, a.team, a.y0; pendingAnim[fid] = nil end
		patches[fid] = p
		return p
	end

	local function Now()
		return (Spring.GetGameFrame() + (Spring.GetFrameTimeOffset and Spring.GetFrameTimeOffset() or 0)) / 30
	end

	local function Scan()
		for fid, p in pairs(patches) do
			if not Spring.ValidFeatureID(fid) then patches[fid] = nil end
		end
		local features = Spring.GetAllFeatures()
		for i = 1, #features do
			local fid = features[i]
			if not patches[fid] then NewPatch(fid, -1e9) end      -- one we did not see die (late join): no collapse animation
		end
	end

	function gadget:Initialize()
		lists.forms, lists.blobs = {}, {}
		for i, form in ipairs(FORMS) do lists.forms[i] = BuildForm(form, i) end
		for i = 1, 3 do lists.blobs[i] = BuildBlob(i * 1.7) end
		gadgetHandler:AddSyncAction("vbgm", function(_, fid, defID, team, y0)
			local p = patches[fid] or NewPatch(fid, Now())
			if p then p.defID, p.team, p.y0, p.t0 = defID, team, y0, Now()
			else pendingAnim[fid] = { defID = defID, team = team, y0 = y0 } end
		end)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("vbgm")
		if lists.forms then
			for _, f in ipairs(lists.forms) do gl.DeleteList(f.solid); gl.DeleteList(f.glow) end
			for _, b in ipairs(lists.blobs) do gl.DeleteList(b) end
		end
	end

	local function Ease(u) return 1 - (1 - u) * (1 - u) end       -- ease-out, no overshoot: sizes never exceed their cap

	-- put the origin on the lump's surface in direction (dx,dy,dz), z axis along the mushroom
	local function Place(p, s, m, t, rb, w)
		local k = 1 / sqrt((s.dx * s.dx + s.dz * s.dz) + (s.dy / SQUASH) ^ 2)     -- lump radius along that direction
		local r = rb * k * 0.9                                                       -- sunk a little into the lump
		glTranslate(s.dx * r, s.dy * r * SQUASH, s.dz * r)
		glRotate(s.angle, s.rx, s.ry, s.rz)
		glRotate(s.spin, 0, 1, 0)
		glRotate(2.5 * sin(t * 0.9 + s.ph), 1, 0, 0)                                -- gentle sway
		if w > 0.01 then glRotate(w * 75, cos(s.ph), 0, sin(s.ph)) end              -- wilting: it droops over as it is eaten
		glScale(m, m, m)
	end

	local visible = {}
	local function CollectVisible(t, dt)
		local spec, fullview = Spring.GetSpectatingState()
		local ally = Spring.GetMyAllyTeamID()
		local n = 0
		for fid, p in pairs(patches) do
			local S = SizeScale(p.baseR, 1)
			if Spring.IsSphereInView(p.x, p.y, p.z, S * 2 + p.baseR)
				and (fullview or Spring.IsPosInLos(p.x, p.y, p.z, ally)) then
				-- follow the real values smoothly (they are only published twice a second)
				local tg, tb = Spring.GetFeatureRulesParam(fid, "vb_g"), Spring.GetFeatureRulesParam(fid, "vb_b")
				local k = min(1, dt * 3)
				if tg then p.g = p.g + (tg - p.g) * k end
				if tb then p.b = p.b + (tb - p.b) * k end
				p.w = (p.w or 0) + ((Spring.GetFeatureRulesParam(fid, "vb_w") or 0) - (p.w or 0)) * min(1, dt * 4)
				n = n + 1
				visible[n] = p
			end
		end
		for i = n + 1, #visible do visible[i] = nil end
		return n
	end

	function gadget:DrawWorld()
		local frame = Spring.GetGameFrame()
		if frame - lastScan >= 30 or frame < lastScan then lastScan = frame; Scan() end
		if not next(patches) then return end
		local t = Now()
		local n = CollectVisible(t, Spring.GetLastUpdateSeconds and Spring.GetLastUpdateSeconds() or 0.03)
		if n == 0 then return end

		gl.DepthTest(true)
		gl.DepthMask(true)
		gl.Culling(false)
		gl.Texture(false)

		-- 1. gray matter, and the dying unit while it collapses
		for i = 1, n do
			local p = visible[i]
			local u = Clamp((t - p.t0) / SHRINK_SECS, 0, 1)
			local gy = p.y
			local cy = (u < 1) and (p.y0 + (gy - p.y0) * u * u) or gy           -- the collapsing unit sinks to the ground
			local feed = 1 - 0.30 * p.g                                          -- the lump is slowly eaten by what grows from it
			local rb = p.baseR * 0.5 * (0.35 + 0.65 * sqrt(Clamp(p.b, 0, 1))) * feed
			if u < 1 then rb = rb * (0.25 + 0.75 * Ease(u)) end
			-- lump (resting on the ground, or floating)
			glColor(1, 1, 1, 1)
			glPushMatrix()
			glTranslate(p.x, (p.floating and cy or gy) + (p.floating and 0 or rb * SQUASH * 0.8), p.z)
			glRotate(p.yaw, 0, 1, 0)
			glScale(rb, rb * SQUASH, rb)
			glCallList(lists.blobs[p.blob])
			glPopMatrix()
			-- the dead unit's model, shrinking away into it
			if u < 1 and p.defID and unitShapeOK then
				local s = max(0.05, 1 - Ease(u))
				glPushMatrix()
				glTranslate(p.x, cy, p.z)
				glRotate(p.yaw, 0, 1, 0)
				glScale(s, s * (0.5 + 0.5 * s), s)
				local ok = pcall(gl.UnitShape, p.defID, p.team or 0, false)
				if not ok then unitShapeOK = false end
				glPopMatrix()
			end
		end

		-- 2. the mushrooms
		for i = 1, n do
			local p = visible[i]
			local G = Clamp(p.g, 0, 1)
			if G > 0.002 then
				local S = SizeScale(p.baseR, G)
				local rb = p.baseR * 0.5 * (0.35 + 0.65 * sqrt(Clamp(p.b, 0, 1))) * (1 - 0.30 * G)
				local cy = p.y + (p.floating and 0 or rb * SQUASH * 0.8)
				for j = 1, #p.slots do
					local s = p.slots[j]
					local gj = Clamp((G - s.th) / (1 - s.th), 0, 1)
					if gj > 0 then
						local m = S * s.size * 0.55 * Ease(gj) * (1 - 0.35 * (p.w or 0))
						if m > 0.3 then
							glPushMatrix()
							glTranslate(p.x, cy, p.z)
							glRotate(p.yaw, 0, 1, 0)
							Place(p, s, m, t, rb, p.w or 0)
							glCallList(lists.forms[s.form].solid)
							glPopMatrix()
						end
					end
				end
			end
		end

		-- 3. glowing spots on the rims and tips, additive and pulsing
		gl.DepthMask(false)
		gl.Blending(GL.SRC_ALPHA, GL.ONE)
		for i = 1, n do
			local p = visible[i]
			local G = Clamp(p.g, 0, 1)
			if G > 0.002 then
				local S = SizeScale(p.baseR, G)
				local rb = p.baseR * 0.5 * (0.35 + 0.65 * sqrt(Clamp(p.b, 0, 1))) * (1 - 0.30 * G)
				local cy = p.y + (p.floating and 0 or rb * SQUASH * 0.8)
				for j = 1, #p.slots do
					local s = p.slots[j]
					local gj = Clamp((G - s.th) / (1 - s.th), 0, 1)
					local m = S * s.size * 0.55 * Ease(gj) * (1 - 0.35 * (p.w or 0))
					if gj > 0 and m > 0.3 then
						local col = lists.forms[s.form].col
						glColor(col[1], col[2], col[3], 0.30 + 0.20 * sin(t * 2.2 + s.ph))
						glPushMatrix()
						glTranslate(p.x, cy, p.z)
						glRotate(p.yaw, 0, 1, 0)
						Place(p, s, m, t, rb, p.w or 0)
						glCallList(lists.forms[s.form].glow)
						glPopMatrix()
					end
				end
			end
		end
		gl.Blending(false)
		gl.DepthMask(true)
		gl.DepthTest(true)
		glColor(1, 1, 1, 1)
	end
end
