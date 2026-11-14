-- Standalone test for LuaUI/Headers/vb_forge.h.lua (no Spring needed).
-- Run: lua5.4 tools/test_forge.lua
--
-- Stubs the few engine globals the header touches.
_G.VFS = {
	ZIP_ONLY = 1, RAW_ONLY = 2,
	DirList = function(dir, pat, mode)
		if dir == "unitpics/" then return { "unitpics/ch_hoplite.png", "unitpics/mw_ravager.png" } end
		return {}
	end,
	FileExists = function(path) return path == "unitpics/ch_hoplite.png" end,
}
_G.gl = {
	Color = function() end, Texture = function() end, TexRect = function() end,
	BeginEnd = function() end, Shape = function() end, Vertex = function() end,
	Normal = function() end, TexCoord = function() end, PushMatrix = function() end,
	PopMatrix = function() end, Translate = function() end, Rotate = function() end,
}

local F = dofile("game/LuaUI/Headers/vb_forge.h.lua")

local pass, fail = 0, 0
local function check(name, got, want)
	if got == want then pass = pass + 1
	else fail = fail + 1; print(("FAIL %-52s got %-24s want %s"):format(name, tostring(got), tostring(want))) end
end
local function near(name, got, want, eps)
	eps = eps or 0.001
	if type(got) == "number" and math.abs(got - want) <= eps then pass = pass + 1
	else fail = fail + 1; print(("FAIL %-52s got %-24s want %s"):format(name, tostring(got), tostring(want))) end
end

--------------------------------------------------------------------------------
-- the shape codec
--------------------------------------------------------------------------------
local shape = {
	{ type = "box", size = { 40, 30, 50 }, pos = { 0, 15, 0 }, rot = { 0, 45, 0 },
	  color = { 0.8, 0.7, 0.6, 1 }, tex = 0, uv = { 0, 0, 1, 1 } },
	{ type = "sphere", size = { 20, 20, 20 }, pos = { 0, 30, 0 }, rot = { 0, 0, 0 },
	  color = { 1, 1, 1, 0.5 }, tex = 1, uv = { 0.1, 0.2, 0.8, 0.9 } },
}
local enc = F.EncodeShape(shape)
check("encode: not empty", enc ~= "", true)
check("encode: primitive count", select(2, enc:gsub(";", "")) + 1, 2)

local dec = F.DecodeShape(enc)
check("decode: returns a table", type(dec), "table")
check("decode: primitive count", #dec, 2)
check("decode: kind 1", dec[1].type, "box")
check("decode: kind 2", dec[2].type, "sphere")
near("decode: size x", dec[1].size[1], 40)
near("decode: size z", dec[1].size[3], 50)
near("decode: pos y", dec[1].pos[2], 15)
near("decode: rot y", dec[1].rot[2], 45)
near("decode: colour r", dec[1].color[1], 0.8)
near("decode: colour a", dec[1].color[3], 0.6)
near("decode: texture index", dec[2].tex, 1)
near("decode: uv x0", dec[2].uv[1], 0.1)
near("decode: uv y1", dec[2].uv[4], 0.9)

check("decode: empty string", F.DecodeShape(""), nil)
check("decode: garbage", F.DecodeShape("nonsense"), nil)

--------------------------------------------------------------------------------
-- the mesh builders
--------------------------------------------------------------------------------
local box = F.Mesh("box", 40, 30, 50)
check("mesh box: triangles", #box.tris, 12)
check("mesh box: vertices", #box.verts, 24)
-- the box spans its full size
local minx, maxx, miny, maxy, minz, maxz = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
for _, v in ipairs(box.verts) do
	minx = math.min(minx, v[1]); maxx = math.max(maxx, v[1])
	miny = math.min(miny, v[2]); maxy = math.max(maxy, v[2])
	minz = math.min(minz, v[3]); maxz = math.max(maxz, v[3])
end
near("mesh box: width", maxx - minx, 40)
near("mesh box: height", maxy - miny, 30)
near("mesh box: depth", maxz - minz, 50)
near("mesh box: centred", (minx + maxx) / 2, 0)
-- the normals are unit length
local nlen = math.sqrt(box.verts[1][4]^2 + box.verts[1][5]^2 + box.verts[1][6]^2)
near("mesh box: normal length", nlen, 1)

local sph = F.Mesh("sphere", 20, 20, 20)
check("mesh sphere: has triangles", #sph.tris > 0, true)
local rmax = 0
for _, v in ipairs(sph.verts) do rmax = math.max(rmax, math.sqrt(v[1]^2 + v[2]^2 + v[3]^2)) end
near("mesh sphere: radius", rmax, 10, 0.01)

local cyl = F.Mesh("cylinder", 20, 40, 20)
check("mesh cylinder: has triangles", #cyl.tris > 0, true)
local cmaxy = -1e9
for _, v in ipairs(cyl.verts) do cmaxy = math.max(cmaxy, math.abs(v[2])) end
near("mesh cylinder: half height", cmaxy, 20)

local cone = F.Mesh("cone", 20, 40, 20)
check("mesh cone: has triangles", #cone.tris > 0, true)

--------------------------------------------------------------------------------
-- the wire format
--------------------------------------------------------------------------------
local spec = { id = "dread", base = "ch_hoplite", hp = 5000, speed = 1.5, count = 3,
	["repeat"] = 1, shape = enc, png = "dread" }
local payload = F.Ser(spec)
-- it must be valid Lua that the gadget can parse
local chunk, err = load("return " .. payload)
check("ser: parses as Lua", chunk ~= nil, true)
if chunk then
	local t = chunk()
	check("ser: id survives", t.id, "dread")
	check("ser: base survives", t.base, "ch_hoplite")
	near("ser: hp survives", t.hp, 5000)
	near("ser: speed survives", t.speed, 1.5)
	near("ser: count survives", t.count, 3)
	check("ser: repeat survives", t["repeat"], 1)
	check("ser: shape survives", t.shape, enc)
	check("ser: png survives", t.png, "dread")
end

--------------------------------------------------------------------------------
-- the shared template store
--------------------------------------------------------------------------------
F.SetTemplate("alpha", { base = "ch_hoplite", hp = 100 })
check("templates: alpha is stored", F.templates["alpha"] ~= nil, true)
check("templates: id list", F.TemplateIds()[1], "alpha")
F.Bump()
check("templates: revision moved on", F.rev > 0, true)
F.DelTemplate("alpha")
check("templates: alpha is gone", F.templates["alpha"], nil)

--------------------------------------------------------------------------------
-- the png helper
--------------------------------------------------------------------------------
check("png path: bare name", F.PngPath("ch_hoplite"), "unitpics/ch_hoplite.png")
check("png path: unknown", F.PngPath("does_not_exist"), nil)

print(("passed %d, failed %d"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
