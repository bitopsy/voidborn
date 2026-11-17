# Voidborn 0.1 — the first release

What is in the first public version of Voidborn, in one list.

* **A 3D space RTS for the Spring / Recoil engine.** Its own game, not a mod:
  `voidborn.sdz` in the `games/` folder, `voidborn_rift.sd7` in `maps/`, and a
  start script to launch it. Tested on Recoil 2026.07.04.
* **A full RTS economy lifted off the ground.** A commander, metal extractors,
  energy, factories, defences, radar and storage — and every mobile unit flies,
  each at its own altitude. Layers are real: a scout at 60 elmos and a heavy at
  230 are in different places, and that decides fights.
* **Sixteen mobile units in two factions.**
  * *Choir of the Eye* — pale, many-eyed cyclopes, long-range lasers, fragile
    up close: Hierophant (commander, 2500 metal / 4200 HP), Seer (builder),
    Gazer (scout), Lashling (raider), Cyclops Hoplite (assault), Basilisk (long
    range), Weeper (support), Argus Colossus (heavy, 9500 HP).
  * *Maw Swarm* — chitinous, toothed, many-legged, cheap, tough and short
    reaching: Matriarch (commander, 2500 metal / 4400 HP), Weaver (builder),
    Skitter (scout), Gnasher (raider), Ravager (assault), Spitter (artillery),
    Nurse (support), Leviathan (heavy, 13000 HP).
* **Eight structures per faction**, in its own image: factory, metal extractor,
  energy, advanced energy, storage, radar, light defence and heavy defence.
* **Commander super weapons**, fired by hand: the Cataract Stare and the
  Devour. Losing your commander ends the game (switchable in the lobby).
* **A bot that plays the game** at three skill levels, so a match needs no
  second player. `Watch_Bot_vs_Bot.txt` sends two bots at each other.
* **Three start scripts**: `Play_Choir_vs_Bot.txt`, `Play_Maw_vs_Bot.txt` and
  `Watch_Bot_vs_Bot.txt`.
* **The unit forge — create a unit while the game runs.** Pick any unit as the
  base; change its health, metal, energy, build time, sight, speed, range,
  damage, reload, altitude, count, team and image size with sliders and
  toggles; give it a **new 3D body** built from box, sphere, cylinder and cone
  primitives with size, position, rotation, colour and the part of a picture
  mapped onto it; a live 3D preview shows the result. `CREATE`, `SAVE` and
  `LOAD` work on it, and the forge and the chat console share one template
  store.
* **A price for every custom unit, worked out automatically.** The stronger
  the design, the more metal and the more build time it costs, relative to the
  cost of the base unit: health, speed, range, damage, reload, sight, altitude,
  the 3D body and the group size each add a share of it, and the build time
  follows (up to nine times the base).
* **A production queue.** The build panel always lists every mobile unit your
  factories can build; clicking one queues it at the selected factory. Every
  factory has its own line and they build in parallel, with a pie chart and a
  count on the tile. Middle click holds, right click takes one out, ctrl+right
  cancels the line and refunds.
* **A factory that is not finished yet cannot build.** Order from a hive that
  is still under construction and the unit waits for it (a cyan clock on the
  tile); nothing is paid until the hive is done.
* **Experience, growth and splitting.** Mobile units grow as they gain
  experience and split in two at 0.14 — by then they have doubled in size. Both
  halves keep the health fraction, the orders, the stances and the whole
  design. The host sets both numbers in the settings panel or in the lobby.
* **A dev console** (`~` or `/vbconsole`) with **autocomplete, syntax
  highlighting and autofill**: tab completes commands, option names and unit
  names, and the whole line is coloured as you type. `/vbcreate`, `/vbspawn`,
  `/vbtemplates`, `/vbforget`, `/vbbases`, `/vbexec`.
* **A unit census** (`/vbstats`): totals, histograms of health, speed, range,
  damage and experience, the units present and the ones closest to splitting.
* **Health bars** above every visible unit, and a second bar for the build
  progress of an unfinished structure.
* **Sensor ranges** (`/vbranges`): line of sight and radar circles for the
  units you select and for the structure you are placing.
* **Role icons when the camera is far out**: seventeen white glyphs, one per
  role, tinted by the engine with the team colour.
* **A build panel that replaces the engine's own**: draggable, resizable, with
  colour-coded toggle states (fire / move / repeat), hover statistics and a
  radar profile, and a `[+]` tile at the end of the build row that opens the
  forge.
* **Eleven arenas**: Voidborn Rift (the official one, 5120 × 5120, 43 metal
  spots, 2–4 players) plus ten more in the map repository, from a two-player
  duel to a twenty-player free-for-all.
* **Lobby options**: commander death ends the game, starting metal and energy,
  the bot's skill, the forge in multiplayer, the split threshold and the growth.
* **No sounds to speak of yet** — the sound system is in place (39 generated
  files, no samples) but the game ships silent.
* **Free and open source.** No accounts, no ads, no launcher, no in-game store.
  Every model, texture, unit, weapon, sound and map is generated by the scripts
  in the repository.
* **One command builds and proves it**: `python3 build_sdz.py` compiles every
  Lua file, runs the smoke tests, builds the archive, compares it with the
  sources file by file, installs it and finally starts the engine to check that
  it loads the build it just made.
* **A website** with a page per subject — home, play & download, maps, the unit
  forge and the roadmap — and nothing loaded from the network.

## Known limitations of 0.1

* The balance is a first pass, and the Choir is slightly stronger than the bot.
* The bot is simple.
* The look and feel has not been polished on real hardware.
* No sounds.
* There is no matchmaking: matches are started with a script or hosted by
  hand.

The roadmap (<https://f33.fr/vb/roadmap.html>) has what comes next: custom unit
balancing and taxation, factory upgrades from tier 1 to tier 2, unit evolution
with proliferation control, a third faction, hosted games and replays, and
Steam.
