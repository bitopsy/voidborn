--[[
  Voidborn unit forge: shared helpers.

  Used by:
    * LuaUI/Widgets/vb_forge.lua   - the forge panel (pick a base unit, tweak it, create it)
    * LuaUI/Widgets/vb_shape3d.lua  - draws the custom 3D shape of a unit in the world
    * LuaUI/Widgets/dev_console.lua  - shares the template store with the forge

  Contents:
    * the shared template store, so /vbcreate and /vbspawn see the same recipes
    * the shape codec (a shape becomes a string, so it can travel over LuaRulesMsg)
    * mesh builders (box, sphere, cylinder, cone) plus the drawing helpers
    * the list of PNG files that can be mapped onto a shape

  A shape is a list of primitives:
    { type = "box", size = {sx,sy,sz}, pos = {px,py,pz}, rot = {rx,ry,rz},
      color = {r,g,b,a}, tex = 0 or -1, uv = {u0,v0,u1,v1} }
  and is encoded as
    "box:40,30,50@0,15,0@0,0,0@0.8,0.75,0.7,1@0@0,0,1,1"
  (primitives separated by ";")
]]

local F = {}
if _G.VBForge then F = _G.VBForge end
_G.VBForge = F

--------------------------------------------------------------------------------
-- shared template store (id -> spec)
--------------------------------------------------------------------------------
-- Both the console and the forge use this table, so a unit created in one is
-- spawnable from the other.  The revision counter lets both widgets keep their
-- own saved copy in the widget config without one of them undoing the other's
-- changes on startup.
F.templates = F.templates or {}
F.rev      = F.rev or 0

function F.Bump() F.rev = F.rev + 1 end

-- sorted list of the stored template ids
function F.TemplateIds()
	local ids = {}
	for id in pairs(F.templates) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

function F.SetTemplate(id, spec)
	if not id or id == "" then return false end
	local keep = {}
	for k, v in pairs(spec) do
		if k ~= "x" and k ~= "z" then keep[k] = v end
	end
	F.templates[id] = keep
	F.Bump()
	return true
end

function F.DelTemplate(id)
	if F.templates[id] then F.templates[id] = nil; F.Bump(); return true end
	return false
end

--------------------------------------------------------------------------------
-- the wire format
--------------------------------------------------------------------------------
-- A spec table becomes a Lua table literal that the LuaRules gadget parses.
-- The keys are quoted so that Lua keywords ("repeat") survive the round trip.
function F.Ser(t)
	local parts = {}
	for k, v in pairs(t or {}) do
		if type(v) == "number" then parts[#parts + 1] = string.format("[%q]=%s", k, string.format("%.6g", v))
		elseif type(v) == "string" then parts[#parts + 1] = string.format("[%q]=%q", k, v) end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- --------------------------------------------------------------------------------
-- the primitive kinds
--------------------------------------------------------------------------------
F.KINDS = { "box", "sphere", "cylinder", "cone" }

local KIND_INDEX = {}
for i, k in ipairs(F.KINDS) do KIND_INDEX[k] = i end

--------------------------------------------------------------------------------
-- shape codec
--------------------------------------------------------------------------------
local function R(v) return string.format("%.4g", v) end

function F.EncodeShape(shape)
	if not shape or #shape == 0 then return "" end
	local parts = {}
	for _, p in ipairs(shape) do
		local s, po, ro, co = p.size or { 0, 0, 0 }, p.pos or { 0, 0, 0 }, p.rot or { 0, 0, 0 }, p.color or { 1, 1, 1, 1 }
		local uv = p.uv or { 0, 0, 1, 1 }
		parts[#parts + 1] = table.concat({
			p.type or "box",
			"@" .. table.concat({ R(s[1]), R(s[2]), R(s[3]) }, ","),
			"@" .. table.concat({ R(po[1]), R(po[2]), R(po[3]) }, ","),
			"@" .. table.concat({ R(ro[1]), R(ro[2]), R(ro[3]) }, ","),
			"@" .. table.concat({ R(co[1]), R(co[2]), R(co[3]), R(co[4] or 1) }, ","),
			"@" .. tostring(p.tex or -1),
			"@" .. table.concat({ R(uv[1]), R(uv[2]), R(uv[3]), R(uv[4]) }, ","),
		}, "")
	end
	return table.concat(parts, ";")
end

function F.DecodeShape(str)
	if type(str) ~= "string" or str == "" then return nil end
	local out = {}
	for part in str:gmatch("[^;]+") do
		local kind, rest = part:match("^(%a+)@(.*)$")
		if kind and KIND_INDEX[kind] then
			local fields = {}
			-- the leading "@" makes the first field match as well
			for f in ("@" .. rest):gmatch("@([^@]*)") do fields[#fields + 1] = f end
			local function Num(i, n)
				local f = fields[i]
				if not f then return n end
				return tonumber(f) or n
			end
			local function Vec(i, n)
				local f = fields[i] or ""
				local t = {}
				for k, x in ipairs({ f:match("^([^,]*),([^,]*),([^,]*),?([^,]*)$") }) do
					t[k] = tonumber(x) or 0
				end
				return { t[1] or n[1], t[2] or n[2], t[3] or n[3], t[4] or n[4] }
			end
			local size = Vec(1, { 40, 40, 40 })
			local pos  = Vec(2, { 0, 0, 0 })
			local rot  = Vec(3, { 0, 0, 0 })
			local col  = Vec(4, { 1, 1, 1, 1 })
			local tex  = Num(5, -1)
			local uv   = Vec(6, { 0, 0, 1, 1 })
			out[#out + 1] = {
				type = kind, size = { size[1], size[2], size[3] },
				pos = { pos[1], pos[2], pos[3] }, rot = { rot[1], rot[2], rot[3] },
				color = { col[1], col[2], col[3], col[4] }, tex = tex, uv = { uv[1], uv[2], uv[3], uv[4] },
			}
		end
	end
	if #out == 0 then return nil end
	return out
end

-- a copy that is safe to hand to the user interface (no shared tables)
function F.CopyShape(shape)
	if not shape then return nil end
	local out = {}
	for i, p in ipairs(shape) do
		local c = { type = p.type }
		for _, k in ipairs({ "size", "pos", "rot", "color", "uv" }) do
			local s = p[k]
			c[k] = s and { s[1], s[2], s[3], s[4] } or nil
		end
		c.tex = p.tex
		out[i] = c
	end
	return out
end

--------------------------------------------------------------------------------
-- mesh builders
--------------------------------------------------------------------------------
-- Returns { verts = { {x,y,z,nx,ny,nz,u,v}, ... }, tris = { {i,j,k}, ... } }
function F.Mesh(kind, sx, sy, sz, segs, rings)
	segs  = segs or 12
	rings = rings or 8
	local v, t = {}, {}
	local function V(x, y, z, nx, ny, nz, u, vv)
		v[#v + 1] = { x, y, z, nx, ny, nz, u, vv }
		return #v
	end
	local function T(a, b, c) t[#t + 1] = { a, b, c } end
	local function Quad(a, b, c, d) T(a, b, c); T(a, c, d) end

	if kind == "sphere" then
		local r = sx / 2
		for i = 0, rings do
			local phi = (i / rings) * math.pi
			local cy, sy2 = math.cos(phi), math.sin(phi)
			for j = 0, segs do
				local th = (j / segs) * 2 * math.pi
				local cx, cz = math.cos(th), math.sin(th)
				V(cx * sy2 * r, cy * r, cz * sy2 * r, cx * sy2, cy, cz * sy2, j / segs, i / rings)
			end
		end
		local row = segs + 1
		for i = 0, rings - 1 do
			for j = 0, segs - 1 do
				local a = i * row + j + 1
				Quad(a, a + 1, a + row + 1, a + row)
			end
		end
	elseif kind == "cylinder" or kind == "cone" then
		local r, h = sx / 2, sy
		local apex = (kind == "cone")
		local top = h / 2
		for j = 0, segs do
			local th = (j / segs) * 2 * math.pi
			local cx, cz = math.cos(th), math.sin(th)
			if apex then
				local len = math.sqrt(h * h + r * r)
				V(cx * r, -top, cz * r, h * cx / len, r / len, h * cz / len, j / segs, 1)
				V(0, top, 0, h * cx / len, r / len, h * cz / len, j / segs, 0)
			else
				V(cx * r, -top, cz * r, cx, 0, cz, j / segs, 1)
				V(cx * r, top, cz * r, cx, 0, cz, j / segs, 0)
			end
		end
		for j = 0, segs - 1 do
			local a = j * 2 + 1
			if apex then T(a, a + 1, a + 3); T(a, a + 3, a + 2)
			else Quad(a, a + 1, a + 3, a + 2) end
		end
		-- base cap
		local centre = V(0, -top, 0, 0, -1, 0, 0.5, 0.5)
		local first = #v + 1
		for j = 0, segs do
			local th = (j / segs) * 2 * math.pi
			local cx, cz = math.cos(th), math.sin(th)
			V(cx * r, -top, cz * r, 0, -1, 0, 0.5 + cx * 0.5, 0.5 + cz * 0.5)
		end
		for j = 0, segs - 1 do T(centre, first + j, first + j + 1) end
	else -- box
		local hx, hy, hz = sx / 2, sy / 2, sz / 2
		local function Face(pts, n)
			local idx = {}
			for _, p in ipairs(pts) do
				idx[#idx + 1] = V(p[1], p[2], p[3], n[1], n[2], n[3], p[4], p[5])
			end
			Quad(idx[1], idx[2], idx[3], idx[4])
		end
		Face({ { hx, -hy, -hz, 0, 0 }, { hx, hy, -hz, 1, 0 }, { hx, hy, hz, 1, 1 }, { hx, -hy, hz, 0, 1 } }, { 1, 0, 0 })
		Face({ { -hx, -hy, hz, 0, 0 }, { -hx, hy, hz, 1, 0 }, { -hx, hy, -hz, 1, 1 }, { -hx, -hy, -hz, 0, 1 } }, { -1, 0, 0 })
		Face({ { -hx, hy, -hz, 0, 0 }, { -hx, hy, hz, 1, 0 }, { hx, hy, hz, 1, 1 }, { hx, hy, -hz, 0, 1 } }, { 0, 1, 0 })
		Face({ { -hx, -hy, hz, 0, 0 }, { -hx, -hy, -hz, 1, 0 }, { hx, -hy, -hz, 1, 1 }, { hx, -hy, hz, 0, 1 } }, { 0, -1, 0 })
		Face({ { -hx, -hy, hz, 0, 0 }, { hx, -hy, hz, 1, 0 }, { hx, hy, hz, 1, 1 }, { -hx, hy, hz, 0, 1 } }, { 0, 0, 1 })
		Face({ { hx, -hy, -hz, 0, 0 }, { -hx, -hy, -hz, 1, 0 }, { -hx, hy, -hz, 1, 1 }, { hx, hy, -hz, 0, 1 } }, { 0, 0, -1 })
	end

	return { verts = v, tris = t }
end

-- rotated copies of the mesh vertices (rotation in degrees, around the own centre)
local function Rotated(verts, rot)
	local rx, ry, rz = (rot[1] or 0) * math.pi / 180, (rot[2] or 0) * math.pi / 180, (rot[3] or 0) * math.pi / 180
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local out = {}
	for i, v in ipairs(verts) do
		local x, y, z = v[1], v[2], v[3]
		-- X
		local y2, z2 = y * cx - z * sx, y * sx + z * cx
		y, z = y2, z2
		-- Y
		local x2, z3 = x * cy + z * sy, -x * sy + z * cy
		x, z = x2, z3
		-- Z
		local x3, y3 = x * cz - y * sz, x * sz + y * cz
		x, y = x3, y3
		local nx, ny, nz = v[4], v[5], v[6]
		local y4, z4 = ny * cx - nz * sx, ny * sx + nz * cx
		ny, nz = y4, z4
		local x4, z5 = nx * cy + nz * sy, -nx * sy + nz * cy
		nx, nz = x4, z5
		local x5, y5 = nx * cz - ny * sz, nx * sz + ny * cz
		nx, ny = x5, y5
		out[i] = { x, y, z, nx, ny, nz, v[7], v[8] }
	end
	return out
end

--------------------------------------------------------------------------------
-- drawing a shape in the world (3D, textured)
--------------------------------------------------------------------------------
-- texture = path of the PNG to map onto the primitives (or nil for no texture)
-- scale   = uniform scale (elmos)
-- light   = { x, y, z } direction of the light
function F.DrawShape(shape, texture, scale, light)
	scale = scale or 1
	light = light or { -0.4, 0.8, 0.45 }
	local lx, ly, lz = light[1], light[2], light[3]
	local llen = math.sqrt(lx * lx + ly * ly + lz * lz)
	if llen > 0 then lx, ly, lz = lx / llen, ly / llen, lz / llen end
	local texOn = false
	for _, p in ipairs(shape or {}) do
		local mesh = F.Mesh(p.type or "box", p.size[1], p.size[2], p.size[3])
		local verts = Rotated(mesh.verts, p.rot)
		local po = p.pos or { 0, 0, 0 }
		local co = p.color or { 1, 1, 1, 1 }
		local uvr = p.uv or { 0, 0, 1, 1 }
		local useTex = texture and p.tex ~= nil and p.tex >= 0
		if useTex and not texOn then gl.Texture(texture); texOn = true end
		gl.BeginEnd(GL.TRIANGLES, function()
			for _, tri in ipairs(mesh.tris) do
				for _, idx in ipairs(tri) do
					local v = verts[idx]
					local lam = 0.35 + 0.65 * math.max(0, v[4] * lx + v[5] * ly + v[6] * lz)
					gl.Color(co[1] * lam, co[2] * lam, co[3] * lam, co[4] or 1)
					gl.Normal(v[4], v[5], v[6])
					if useTex then
						gl.TexCoord(uvr[1] + (uvr[3] - uvr[1]) * v[7], uvr[2] + (uvr[4] - uvr[2]) * v[8])
					else
						gl.TexCoord(v[7], v[8])
					end
					gl.Vertex(v[1] * scale + po[1] * scale, v[2] * scale + po[2] * scale, v[3] * scale + po[3] * scale)
				end
			end
		end)
	end
	if texOn then gl.Texture(false) end
end

--------------------------------------------------------------------------------
-- drawing a shape as a flat 2D preview (no texture, shaded)
--------------------------------------------------------------------------------
-- Draws the shape into the rectangle (x, y, w, h) using an orthographic
-- projection.  yaw/pitch turn the model.
function F.DrawPreview(shape, x, y, w, h, yaw, pitch)
	yaw = yaw or 35
	pitch = pitch or 25
	local ya, pa = yaw * math.pi / 180, pitch * math.pi / 180
	local cy, sy = math.cos(ya), math.sin(ya)
	local cp, sp = math.cos(pa), math.sin(pa)
	local lx, ly, lz = -0.4, 0.8, 0.45
	local llen = math.sqrt(lx * lx + ly * ly + lz * lz)
	lx, ly, lz = lx / llen, ly / llen, lz / llen

	-- collect every triangle of every primitive in world space
	local tris = {}
	local minY, maxY, span = 1e9, -1e9, 1
	for _, p in ipairs(shape or {}) do
		local mesh = F.Mesh(p.type or "box", p.size[1], p.size[2], p.size[3])
		local verts = Rotated(mesh.verts, p.rot)
		local po = p.pos or { 0, 0, 0 }
		local co = p.color or { 1, 1, 1, 1 }
		for _, tri in ipairs(mesh.tris) do
			local pts, depth = {}, 0
			for _, idx in ipairs(tri) do
				local v = verts[idx]
				local wx, wy, wz = v[1] + po[1], v[2] + po[2], v[3] + po[3]
				-- yaw around Y
				local rx = wx * cy + wz * sy
				local rz = -wx * sy + wz * cy
				-- pitch around X
				local ry = wy * cp - rz * sp
				local rz2 = wy * sp + rz * cp
				pts[#pts + 1] = { rx, ry, rz2, v[4], v[5], v[6] }
				depth = depth + rz2
			end
			depth = depth / 3
			for _, q in ipairs(pts) do
				if q[2] < minY then minY = q[2] end
				if q[2] > maxY then maxY = q[2] end
			end
			tris[#tris + 1] = { pts = pts, depth = depth, color = co }
		end
	end
	if #tris == 0 then return end
	span = math.max(0.001, maxY - minY)
	-- fit the model into the box
	local scale = math.min(w, h) / math.max(span, 1) * 0.85
	local midY = (maxY + minY) / 2
	table.sort(tris, function(a, b) return a.depth > b.depth end)   -- far first
	for _, t in ipairs(tris) do
		local nx, ny, nz = t.pts[1][4], t.pts[1][5], t.pts[1][6]
		-- rotate the normal into view space as well
		local rx = nx * cy + nz * sy
		local rz = -nx * sy + nz * cy
		local ry = ny * cp - rz * sp
		local rz2 = ny * sp + rz * cp
		local lam = 0.3 + 0.7 * math.max(0, rx * lx + ry * ly + rz2 * lz)
		local co = t.color
		local pts = {}
		for _, q in ipairs(t.pts) do
			pts[#pts + 1] = { x + w / 2 + q[1] * scale, y + h / 2 - (q[2] - midY) * scale }
		end
		gl.Color(co[1] * lam, co[2] * lam, co[3] * lam, co[4] or 1)
		gl.Shape(GL.TRIANGLES, {
			{ v = { pts[1][1], pts[1][2] } }, { v = { pts[2][1], pts[2][2] } }, { v = { pts[3][1], pts[3][2] } },
		})
	end
end

--------------------------------------------------------------------------------
-- the PNG files that can be mapped onto a shape
--------------------------------------------------------------------------------
local pngCache
function F.PngList()
	if pngCache then return pngCache end
	local names, seen = {}, {}
	local function Add(dir)
		for _, mode in ipairs({ VFS.ZIP_ONLY, VFS.RAW_ONLY }) do
			local ok, list = pcall(VFS.DirList, dir, "*.png", mode)
			if ok and list then
				for _, f in ipairs(list) do
					local n = f:match("([^/]+)%.png$")
					if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
				end
			end
		end
	end
	Add("unitpics/")
	Add("icons/")
	table.sort(names)
	pngCache = names
	return names
end

-- turns a bare name into a VFS path ("dread" -> "unitpics/dread.png")
function F.PngPath(name)
	if not name or name == "" then return nil end
	local path = name
	if not path:find("/", 1, true) then path = "unitpics/" .. path end
	if not path:lower():find("%.%w+$") then path = path .. ".png" end
	if VFS.FileExists(path) then return path end
	return nil
end

return F
