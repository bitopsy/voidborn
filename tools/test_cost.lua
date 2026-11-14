-- Standalone test for LuaRules/Headers/vb_cost.h.lua (no Spring needed).
-- Run: lua5.4 tools/test_cost.lua
--
-- The engine globals the rules need are stubbed with one made up unit.
_G.Game = { armorTypes = { default = 0 } }
_G.WeaponDefs = {
	[1] = { damages = { [0] = 100 }, salvoSize = 2, projectiles = 1, range = 300 },
	[2] = { damages = { [0] = 50 },  salvoSize = 1, projectiles = 3, range = 600 },
}

local C = dofile("game/LuaRules/Headers/vb_cost.h.lua")

-- a made up base unit: 900 hp, 100 metal, 50 energy, 3000 build time
local ud = {
	name = "test", health = 900, metalCost = 100, energyCost = 50, buildTime = 3000,
	speed = 182, losRadius = 300,
	weapons = { { weaponDef = 1 }, { weaponDef = 2 } },
}

local pass, fail = 0, 0
local function check(name, got, want)
	if got == want then pass = pass + 1
	else fail = fail + 1; print(("FAIL %-50s got %-22s want %s"):format(name, tostring(got), tostring(want))) end
end
local function near(name, got, want, eps)
	eps = eps or 0.5
	if type(got) == "number" and math.abs(got - want) <= eps then pass = pass + 1
	else fail = fail + 1; print(("FAIL %-50s got %-22s want %s"):format(name, tostring(got), tostring(want))) end
end

--------------------------------------------------------------------------------
-- the base unit is free of premiums
--------------------------------------------------------------------------------
local c = C.Cost({}, ud)
check("base: metal", c.metal, 100)
check("base: energy", c.energy, 50)
check("base: build", c.build, 3000)
check("base: no premium", c.premium, 0)

--------------------------------------------------------------------------------
-- health: the extra health costs what the health it replaces costs
--------------------------------------------------------------------------------
c = C.Cost({ hp = 1800 }, ud)          -- double the hit points
near("hp: metal", c.metal, 200)         -- 100 base + 100 for the extra 900 hp
near("hp: build penalty", c.build, 3000 * (1 + 0.6 * 1.0))
c = C.Cost({ hp = 900 }, ud)
check("hp: same as base is free", c.premium, 0)
c = C.Cost({ hp = 450 }, ud)            -- less than the base: no premium, no refund
check("hp: less than base is free", c.premium, 0)

--------------------------------------------------------------------------------
-- the multipliers
--------------------------------------------------------------------------------
c = C.Cost({ speed = 2 }, ud)
near("speed: metal", c.metal, 100 + 0.60 * 100)
c = C.Cost({ range = 1.5 }, ud)
near("range: metal", c.metal, 100 + 0.50 * 0.80 * 100)
c = C.Cost({ dmg = 2 }, ud)
near("damage: metal", c.metal, 100 + 1.20 * 100)
c = C.Cost({ reload = 0.5 }, ud)        -- twice as fast: that costs more
near("reload: metal", c.metal, 100 + 0.50 * 0.50 * 2 * 100)
c = C.Cost({ reload = 2 }, ud)          -- twice as slow: no premium, it is only weaker
check("reload slower: no premium", C.Cost({ reload = 2 }, ud).premium, 0)
c = C.Cost({ speed = 0.5 }, ud)         -- slower: no premium
check("speed slower: no premium", c.premium, 0)
c = C.Cost({ dmg = 0.5 }, ud)           -- weaker: no premium
check("damage lower: no premium", c.premium, 0)
c = C.Cost({ speed = 1 }, ud)
check("speed 1.0 is free", c.premium, 0)

--------------------------------------------------------------------------------
-- sight and altitude
--------------------------------------------------------------------------------
c = C.Cost({ sight = 600 }, ud)         -- double the sight radius
near("sight: metal", c.metal, 100 + 0.50 * 100)
c = C.Cost({ alt = 300 }, ud)
check("alt: energy", c.energy, 50 + 300 * 50 * 0.01)
check("alt: no metal premium", c.premium, 0)

--------------------------------------------------------------------------------
-- the custom body and the custom script
--------------------------------------------------------------------------------
c = C.Cost({ shape = "box@1,2,3@0,0,0@0,0,0@1,1,1,1@0@0,0,1,1" }, ud)
near("shape: one primitive", c.metal, 100 + 0.15 * 100)
c = C.Cost({ shape = "box@1,2,3@0,0,0@0,0,0@1,1,1,1@0@0,0,1,1;sphere@1,2,3@0,0,0@0,0,0@1,1,1,1@0@0,0,1,1" }, ud)
near("shape: two primitives", c.metal, 100 + 2 * 0.15 * 100)
c = C.Cost({ lua = "Spring.Echo(1)" }, ud)
near("lua: metal", c.metal, 100 + 0.50 * 100)

--------------------------------------------------------------------------------
-- the group
--------------------------------------------------------------------------------
c = C.Cost({ count = 3 }, ud)
check("count: metal x3", c.metal, 300)
check("count: build x3", c.build, 9000)
check("count: reported", c.count, 3)

--------------------------------------------------------------------------------
-- the explicit costs are the base, the premium still applies
--------------------------------------------------------------------------------
c = C.Cost({ metal = 500, hp = 1800 }, ud)
near("explicit metal + premium", c.metal, 500 + 100)
c = C.Cost({ buildtime = 1000, hp = 1800 }, ud)
near("explicit buildtime + penalty", c.build, 1000 + 3000 * 0.6 * 1.0)

--------------------------------------------------------------------------------
-- a cheap unit stays cheap, an expensive one stays expensive
--------------------------------------------------------------------------------
local cheap = { health = 900, metalCost = 40, energyCost = 10, buildTime = 1000, speed = 100, losRadius = 200 }
local dear  = { health = 900, metalCost = 400, energyCost = 200, buildTime = 9000, speed = 100, losRadius = 200 }
near("cheap unit: hp premium", C.Cost({ hp = 1800 }, cheap).metal, 80)
near("dear unit: hp premium", C.Cost({ hp = 1800 }, dear).metal, 800)

--------------------------------------------------------------------------------
-- the build time penalty is capped
--------------------------------------------------------------------------------
local huge = { health = 100, metalCost = 100, energyCost = 10, buildTime = 1000, speed = 100, losRadius = 200 }
c = C.Cost({ hp = 100000 }, huge)
check("build penalty is capped", c.build <= 1000 * (1 + 0.6 * 8) + 1, true)

--------------------------------------------------------------------------------
-- the helpers
--------------------------------------------------------------------------------
check("primitives: none", C.Primitives(""), 0)
check("primitives: one", C.Primitives("box@1,2,3"), 1)
check("primitives: three", C.Primitives("box@1,2,3;sphere@1,2,3;cone@1,2,3"), 3)
near("base damage: two weapons", C.BaseDamage(ud), 100 * 2 + 50 * 3)
check("base range: the longest", C.BaseRange(ud), 600)

print(("passed %d, failed %d"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
