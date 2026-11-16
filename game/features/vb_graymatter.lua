-- Voidborn: the gray matter a dead unit leaves behind (see LuaRules/Gadgets/vb_mushrooms.lua).
--
-- The feature itself is only the reclaimable handle (its model is a speck, vb_hidden.s3o); the gadget
-- draws the gray matter and the 3D mushrooms instead.  The energy it holds is set per feature
-- by the gadget (it depends on the dead unit and on how long the corpse was left alone), so
-- the numbers here are only placeholders; the gadget never lets a feature hold more than
-- `energy` below.
return {
	vb_graymatter = {
		description     = "Gray matter and mushrooms (reclaim for energy)",
		object          = "vb_hidden.s3o",   -- a speck of a model: the gadget draws the gray matter and mushrooms itself
		reclaimable     = true,
		autoreclaimable = false,
		blocking        = false,
		indestructible  = true,              -- splash damage does not clear them away; reclaiming does
		noSelect        = false,
		metal           = 0,
		energy          = 20000,
		reclaimTime     = 100,
		damage          = 1000000,
		-- what the mouse hits (hover and reclaim clicks); the gadget resizes it as the mushrooms grow
		collisionVolumeType    = "ellipsoid",
		collisionVolumeScales  = "40 40 40",
		collisionVolumeOffsets = "0 20 0",
		customParams    = { vb_mushroom = "1" },
	},
}
