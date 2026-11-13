local mapinfo = {
	name        = "Voidborn Rift",
	shortname   = "VoidRift",
	description = "Floating asteroids in deep space. Two tiered home asteroids, a central Eye, and islands of ore. Built for flying monsters: expand across the void.",
	author      = "goddot",
	version     = "1.0",
	modtype     = 3,
	mapfile     = "maps/voidrift.smf",

	maphardness = 100,
	notDeformable = true,
	gravity     = 130,
	tidalStrength = 0,
	maxMetal    = 0.02,
	extractorRadius = 60,
	voidWater   = true,
	autoShowMetal = true,

	smf = {
		minheight = -300,
		maxheight = 700,
		smtFileName0 = "voidrift.smt",
	},

	atmosphere = {
		minWind = 4, maxWind = 14,
		fogStart = 0.995, fogEnd = 1.0,
		fogColor = { 0.0, 0.0, 0.02 },
		sunColor = { 1.0, 0.95, 0.9 },
		skyColor = { 0.01, 0.01, 0.04 },
		skyAxisAngle = 0.0,
		skyBox   = "skybox.dds",
		cloudDensity = 0.0,
		cloudColor = { 0, 0, 0 },
	},

	lighting = {
		sunDir = { 0.35, 0.85, -0.45 },
		groundAmbientColor  = { 0.42, 0.44, 0.52 },
		groundDiffuseColor  = { 0.80, 0.78, 0.76 },
		groundSpecularColor = { 0.10, 0.10, 0.12 },
		unitAmbientColor    = { 0.55, 0.55, 0.62 },
		unitDiffuseColor    = { 0.95, 0.92, 0.90 },
		unitSpecularColor   = { 0.55, 0.55, 0.60 },
		specularExponent    = 100.0,
	},

	water = {
		damage = 0.0,
		planeColor = { 0, 0, 0 },
		absorb = { 0, 0, 0 },
		surfaceColor = { 0.0, 0.0, 0.05 },
	},

	teams = {
		[0] = { startPos = { x = 790,  z = 2230 } },
		[1] = { startPos = { x = 4330, z = 2230 } },
		[2] = { startPos = { x = 790,  z = 2890 } },
		[3] = { startPos = { x = 4330, z = 2890 } },
	},

	terrainTypes = {
		[0] = { name = "Rock", hardness = 1.0, receiveTracks = false, moveSpeeds = { tank = 1.0, kbot = 1.0, hover = 1.0, ship = 1.0 } },
	},
}
return mapinfo
