return {
	{ key = "vb_section", name = "Voidborn", desc = "Voidborn options", type = "section" },
	{ key = "commander_ends", name = "Commander death ends the game", desc = "A team that loses its commander is eliminated.", type = "bool", def = true, section = "vb_section" },
	{ key = "startmetal", name = "Starting metal", type = "number", def = 1000, min = 0, max = 10000, step = 100, section = "vb_section" },
	{ key = "startenergy", name = "Starting energy", type = "number", def = 1000, min = 0, max = 10000, step = 100, section = "vb_section" },
	{ key = "bot_skill", name = "VoidBot skill (1 easy - 3 hard)", type = "number", def = 2, min = 1, max = 3, step = 1, section = "vb_section" },
}
