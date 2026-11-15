return {
	{ key = "vb_section", name = "Voidborn", desc = "Voidborn options", type = "section" },
	{ key = "commander_ends", name = "Commander death ends the game", desc = "A team that loses its commander is eliminated.", type = "bool", def = true, section = "vb_section" },
	{ key = "startmetal", name = "Starting metal", type = "number", def = 1000, min = 0, max = 10000, step = 100, section = "vb_section" },
	{ key = "startenergy", name = "Starting energy", type = "number", def = 1000, min = 0, max = 10000, step = 100, section = "vb_section" },
	{ key = "bot_skill", name = "VoidBot skill (1 easy - 3 hard)", type = "number", def = 2, min = 1, max = 3, step = 1, section = "vb_section" },
	{ key = "vb_forge", name = "Unit forge in multiplayer", desc = "Lets every player build forge designs through the production queue (they pay metal, energy and build time). Off: the forge needs cheats or a single human player.",
		type = "bool", def = true, section = "vb_section" },
	{ key = "vb_growth_section", name = "Experience and growth", desc = "How units grow and when they split", type = "section" },
	{ key = "split_xp", name = "Split at (experience)", desc = "The experience at which a unit splits into two. 0.14 is the default; units grow up to the split size in the meantime.",
		type = "number", def = 0.14, min = 0.01, max = 2.0, step = 0.01, section = "vb_growth_section" },
	{ key = "max_growth", name = "Growth before the split", desc = "How much bigger a unit gets before it splits. 1.0 means it has doubled in size; 0.45 means it grew by 45%.",
		type = "number", def = 1.0, min = 0.0, max = 4.0, step = 0.05, section = "vb_growth_section" },
}
