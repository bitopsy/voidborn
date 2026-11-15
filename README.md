![VOIDBORN](vb.webp)

# VOIDBORN
a 3D space RTS for the Spring/Recoil engine and openended unit creation

Two factions of surreal alien monsters fight over floating asteroids in deep space.

* **Choir of the Eye** — pale, many-eyed cyclopes. Long-range lasers, fragile at close quarters.
* **Maw Swarm** — chitinous, toothed, many-legged. Short reach, tougher, regenerating, cheaper.

## Files

| File | Where it goes |
|---|---|
| `voidborn.sdz` | the game → `games/` folder of your BAR / Spring data directory |
| `voidborn_rift.sd7` (+ `.md5.gz`) | the map "Voidborn Rift" → `maps/` folder |
| `Play_Choir_vs_Bot.txt`, `Play_Maw_vs_Bot.txt`, `Watch_Bot_vs_Bot.txt` | start scripts |

## How to run it

Voidborn is its own game (not a BAR mod), so you start it with an engine binary and a start script, not from the BAR lobby.

### How to run it directly from Spring

If you have the Spring engine installed (not BAR), you can launch Voidborn directly:

```
spring Voidborn 1.0.sdz Play_Choir_vs_Bot.txt
```

Or from the command line with the Spring binary. The game requires the `voidborn 1.0.sdz` archive in your Spring data `games/` folder (derived from `modinfo.lua name="Voidborn"` + `version="1.0"`).

For a Flatpak install of BAR the data directory is typically under `~/.var/app/info.beyondallreason.bar/` (look for the folder that already contains BAR's own `games/` and `maps/`). Copy the two archives there, then launch that install's `spring` binary with a start script (you may need to run it from a Flatpak shell).

When the game screen loads, press **Enter / the Start button** (you can also place your start spot first).
`Watch_Bot_vs_Bot.txt` starts two bots against each other so you can spectate.

## What "3D" means here

The Spring engine's terrain is a heightfield, so structures must sit on rock. Voidborn gets its third dimension from:

* **Every mobile unit flies.** Layers are real: scouts and raiders hover at 60–95 elmos, assaults ~80–95, snipers/artillery ~150, titans ~210–230. Expansion across the void is done by flying builders.
* **A tiered map** with 3 terrace heights on the home asteroids (285 / 195 / 115), a crater-ring "Eye" in the centre, and floating islands in a true void (no water; skybox with stars/nebula).
* Tall tower structures (Watcher, Pillar of Judgement) give vertical presence.

## Map: Voidborn Rift (5120 × 5120, 2–4 players)

Two symmetric home asteroids (west/east, 10 metal spots each), a central Eye ring (5), north/south islands (3 each), four corner islands (2 each) and floating debris (1 each): 43 metal spots. Teams 0/1 start west/east; teams 2/3 are the second players for 2v2.

## Units

### Choir of the Eye

| Unit | Role | Metal | HP | Altitude | Weapon (range) |
|---|---|---|---|---|---|
| Hierophant | Cyclopean Commander | 2500 | 4200 | 45 | Gaze (430), Cataract Stare (240) |
| Seer | Builder | 90 | 520 | 50 | — |
| Gazer | Scout | 38 | 230 | 95 | Pinprick (270) |
| Lashling | Raider | 55 | 330 | 65 | Lash Pulse (215) |
| Cyclops Hoplite | Assault | 195 | 1400 | 95 | Cyclops Gaze (380) |
| Basilisk | Long range | 250 | 560 | 150 | Petrifying Beam (740) |
| Weeper | Support | 150 | 700 | 105 | — |
| Argus Colossus | Heavy | 1650 | 9500 | 230 | Annihilating Gaze (650), Lesser Eyes (380) |

Structures: **Iris Womb** (factory), **Leech Eye** (metal extractor), **Sun Iris** (energy), **Singularity Heart** (advanced energy), **Tear Vault** (storage), **Watcher** (radar), **Stare Stalk** (light defence), **Pillar of Judgement** (heavy defence)

### Maw Swarm

| Unit | Role | Metal | HP | Altitude | Weapon (range) |
|---|---|---|---|---|---|
| Matriarch | Maw Commander | 2500 | 4400 | 45 | Acid Spit (420), Devour (240) |
| Weaver | Builder | 90 | 560 | 50 | — |
| Skitter | Scout | 32 | 240 | 90 | Acid Dart (235) |
| Gnasher | Raider | 52 | 560 | 60 | Maw Breath (130) |
| Ravager | Assault | 160 | 2100 | 80 | Corrosive Bolt (345) |
| Spitter | Artillery | 205 | 600 | 140 | Spores (820) |
| Nurse | Support | 150 | 760 | 100 | — |
| Leviathan | Heavy | 1450 | 13000 | 210 | Acid Cannon (620), Spore Barrage (520) |

Structures: **Brood Hive** (factory), **Root Drill** (metal extractor), **Sunbloom** (energy), **Heartfire Egg** (advanced energy), **Gut Cyst** (storage), **Listening Maw** (radar), **Tooth Spire** (light defence), **Maw Bastion** (heavy defence)

## Dev console & custom units

Open the console with the key left of `1` (``` ` ``` on QWERTY, `²` on AZERTY) or `/vbconsole`. Works in single-player games (the shipped start scripts) or with `/cheat` on.

Spring cannot register new unit *types* while a game runs, so `/vbcreate` clones any existing unit and overrides what you like on the spawned units. Recipes are remembered as templates (saved between games).

```
/vbcreate dread base=ch_hoplite name="Dread Lord" hp=6000 dmg=2.5 range=1.4 reload=0.6 count=3
/vbcreate mw_leviathan speed=2 hp=50000          (bare unit name = base)
/vbspawn dread 5            spawn more from a template, at the mouse cursor
/vbtemplates   /vbforget dread   /vbbases (list base unit names)
/vbexec vb.create{ id="x", base="mw_nurse", hp=99, lua="Spring.Echo(unitID)" }
```

Options: `name hp metal energy buildtime sight alt count team x z png pngsize shape fire move repeat`, and multipliers `speed range dmg reload`. `lua=` (last option) runs on every spawned unit with `unitID` set. `png=` floats an image above each spawned unit (a bare name means `unitpics/<name>.png`; `png=icons/x.png` is used as given, `pngsize=` is in elmos). Put the file in `game/unitpics/` or loose in `<data dir>/unitpics/` (no rebuild needed). `shape=` gives the unit a **new 3D body** (see the unit forge below). `fire=`, `move=` and `repeat=` set the starting stance. Units appear at the mouse cursor unless `x=`/`z=` are given. Results are echoed in the chat log.

The console autocompletes: type `/vbcre` and press `TAB` for `/vbcreate`, `base=ch_` and `TAB` for a unit name, and the whole line is syntax highlighted. The **unit forge** (`/vbforge`) is the graphical version of all of this.

### The price of a custom unit

A unit that is stronger than its base unit is not free. Every custom unit gets a price and a build time, worked out automatically from the changes you made:

| change | what it costs |
|---|---|
| `hp` | the extra hit points cost what the hit points they replace cost |
| `speed` `range` `dmg` | a share of the metal cost of the base unit per multiplier point (0.6 / 0.8 / 1.2) |
| `reload` | twice the share per point, and only for a *faster* reload |
| `sight` | the extra sight radius costs what the base sight radius costs |
| `alt` | energy, per elmo of extra altitude |
| `shape` | a share of the metal cost per primitive of the custom body |
| `lua` | a share of the metal cost for a custom script |
| `count` | every unit of the group is built and paid for on its own |

The premium also adds **build points**: the unit takes `(1 + 0.6 x premium / base metal)` times as long to build (capped at 9x). The rules are in `game/LuaRules/Headers/vb_cost.h.lua` and are used by both the gadget (which puts the price on the unit) and the forge panel (which shows it while you design), so the two always agree. The chat log repeats the price of every unit that is created.

The build panel has a **`[+]` tile at the end of the build row** (right after the commander): click it and the unit forge opens, ready to design a new unit.

## Sound

Every sound is generated by `tools/gen_sounds.py` (no samples, no licensing) into `game/sounds/`; `tools/add_sounds.py` wires them into the unit and weapon defs (rerun it if you regenerate defs with `tools/gen_defs.py`). Sound items live in `game/gamedata/sounds.lua`.

* Units: select / acknowledge voices per faction, "can't" buzz, builder zaps, structure activate / deactivate sounds, commander under-attack alarm.
* Weapons: a different shot and impact sound for light / medium / heavy lasers, acid spit, spore missiles, maw flame and the commanders' super weapon; three explosion sizes.
* UI: hover, click, build-select, open / close. Game events (`vb_sounds` widget): start jingle, structure placed, unit ready, structure finished, commander alarm, looping space ambience.
* `/vbsound on|off`, `/vbsound vol 0-100`, `/vbsound ambient on|off`.

## Experience, growth and splitting

`game/LuaRules/Gadgets/vb_experience.lua`: mobile non-commander units grow as they gain experience, up to **2x** their size at `xp = 0.14`. At 0.14 the unit **splits in two**: both halves are normal sized, keep the same health fraction, orders, stances, group and every `/vbcreate` modification (`png`, `name`, `hp`, `speed`, `shape`, ...; a `lua=` snippet is not re-run), and both start again at experience 0. Commanders and structures never split, and a team that is nearly at its unit cap does not split.

**Both numbers are editable by the host (or by anyone in a single player game):**

| | where | default | meaning |
|---|---|---|---|
| `split_xp` | `/vbsettings` panel, or the `split_xp` mod option | `0.14` | the experience at which a unit splits |
| `max_growth` | `/vbsettings` panel, or the `max_growth` mod option | `1.00` | how much bigger it gets first (`1.00` = double size) |

The `/vbsettings` panel is draggable and resizable like the other panels. It shows the values the game is really using; the sliders edit the pending values and `APPLY` sends them to the gadget, which re-scales the units that already grew. The host can also set the numbers in the lobby before the game starts (mod options).

To test quickly: `/vbcreate scout base=mw_skitter lua=Spring.SetUnitExperience(unitID,0.135)` and let it fight.

## Unit forge (`/vbforge`)

`game/LuaUI/Widgets/vb_forge.lua` widget: the unit creation panel. Drag the title bar to move it, drag the corner handle to resize it, `/vbforge` opens and closes it.

Four tabs:

* **BASE** - pick the unit to build on (every buildable unit, with its stats).
* **NUMBERS** - sliders for health, metal, energy, build time, sight, speed, range, damage, reload, altitude, count and team, plus toggle buttons for the starting stance (fire state, move state, repeat).
* **IMAGE** - pick one of the PNGs in `unitpics/` (or `icons/`); it is shown above the unit and can be mapped onto the 3D shape.
* **SHAPE** - build a **new 3D body** out of primitives (box, sphere, cylinder, cone). Per primitive: size, position, rotation, colour, which PNG is mapped onto it and the part of that PNG (the UV rectangle). A live 3D preview shows the result.

`CREATE` sends the design to the gadget, `SAVE` stores it as a template and `LOAD` reads a template back. The footer shows what the unit will cost (the same price the gadget charges). The forge and the console share one template store, so a unit built in the panel can be stamped out again with `/vbspawn <id>` and a recipe typed with `/vbcreate` shows up in the panel.

`game/LuaUI/Widgets/vb_shape3d.lua` widget: draws the custom body of every unit that has one (the shape travels in the unit's `vb_shape` rules parameter), with the PNG mapped onto it.

`game/LuaUI/Headers/vb_forge.h.lua` holds the shared parts: the template store, the shape codec, the mesh builders and the PNG list. The shape of a unit is a string, e.g.

```
box@40,30,50@0,15,0@0,0,0@0.8,0.7,0.6,1@0@0,0,1,1
```

(`kind@size@position@rotation@colour@texture@uv`, several primitives separated by `;`), so `/vbcreate x base=ch_hoplite shape="box@40,30,50@0,15,0@0,0,0@1,1,1,1@0@0,0,1,1"` works from the chat too.


## Unit census (`/vbstats`)

`game/LuaUI/Widgets/vb_unitstats.lua` widget: tracks every unit and shows totals (units, mobile / structures, health, metal value, average / max experience, splits so far), distributions (histograms) of health, speed, range, damage/s, experience and size, the unit types present, and the units closest to splitting.

Values are the live ones. Drag the title bar; click the scope tag to cycle MINE / ALLIES / ALL VISIBLE.

## UI

Hovering a build icon shows a hexagonal stats panel (metal, energy, build time, health, speed, sight, range, damage, DPS, reload, economy values) next to the build panel, with a six-axis radar profile (HP, speed, sight, range, DPS, cost; each axis scaled against the strongest Voidborn unit, square-root scale). Saved forge designs get the same panel, computed from the design's own numbers and price.

The engine's stock build panel is hidden; the Lua widget `game/LuaUI/Widgets/vb_buildpanel.lua` is the only build menu. Widget text uses the generated `game/fonts/VoidbornGlyph.ttf` (`python3 tools/gen_font.py` rebuilds it).

## Tested vs. not tested

I ran the game in the Recoil 2026.07.04 headless engine with two bots playing 20–30 minutes of game time: asteroids loaded, commanders spawned, builders built, mexes produced metal, factories produced units, armies fought, bases died, commander death ended the game. I also fixed the bugs that run exposed (builder/factory scripts, weapon loading, mex yield).

**Not tested (no GPU here):** how the models, textures, skybox, explosions and UI actually *look and feel* on screen, sounds (there are none), and human-driven play. Models/textures are generated procedurally (previews in the PNGs), so expect a "first pass" look.

Known simplifications: no sounds; unit icons use the engine default; the bot is simple; balance is a first pass (Choir is slightly stronger vs the bot).

## Regenerating / modding

`voidborn_source.zip` has the generators (Python: models, textures, unit/weapon defs, map) and the game folder. `python3 tools/gen_assets.py && python3 tools/gen_defs.py` rebuild the models and all unit/weapon/script files.

## Multiplayer & Community

* **SkyLobby**: https://github.com/skynet-gh/skylobby/releases/latest — the lobby client for Spring engine games (it is the successor to SpringLobby). Download the installer for your platform there, then use it to find and join multiplayer games of Voidborn. The manual is at https://github.com/skynet-gh/skylobby/wiki/User-Guide. Host your own server to keep a persistent 24/7 Voidborn world running.
* **Discord**: https://discord.com/channels/1481771055063502925 — Join the Voidborn community to find games, discuss strategies, and coordinate with other players.
* **Website**: https://f33.fr/vb/ — Official Voidborn website with downloads, changelog, and community posts.

We are looking for volunteer 24/7 hosts to keep a persistent Voidborn server running. If you have a server that can run the Spring engine 24/7, please join the Discord and let us know! Help grow the multiplayer community.

## Production queue (stock units and forge designs)

* The build panel always lists every mobile unit your factories can build (no selection needed); the title bar shows the panel version (`q3`). Clicking one queues it at the selected factory, or at the first factory that can build it.
* Select a factory (hive / womb) and click a mobile unit tile: the unit goes into that factory's own line. Every factory builds in parallel, each line shows a pie chart and `xN` on the tile. Middle-click = hold, right-click = take one out (shift = 5, ctrl+right = cancel the line and refund). Structures still use the engine's normal placement.
* Forge designs share one team line and appear at your start position. Hover a design tile and click the red **x** (or ctrl+right-click) to delete it.
* `buildTime` is in build points. The queue builds at `BUILD_POWER = 100` points per second (`game/LuaRules/Headers/vb_cost.h.lua`), the same as a factory with workerTime 100.
* Modoption `vb_forge` (default on) lets every player use the forge in a real match; forge units are paid for in the queue and `lua=` is only honoured with cheats or a single human. The free `/vbcreate` console stays cheat-gated.
* `python3 tools/test_queue.py` and `python3 tools/test_buildpanel.py` run the queue and the panel against a mock engine (`tools/test_healthbars.py` does the same for the health bars) (needs `pip install lupa`).

## Repository layout

Everything the game contains lives in `game/` — that is the folder `build_sdz.py` zips into `voidborn.sdz`. The old copies of those folders at the repo root are gone; there is one copy of everything.

```
game/                 the game itself (this is what ships)
  LuaRules/           the game logic
    Gadgets/          one file per feature (queue, forge, experience, icons, ...)
    Headers/          shared rules used by more than one gadget
  LuaUI/              the interface
    Widgets/          one file per widget (build panel, forge, health bars, ...)
    Headers/          shared helpers for the widgets
  units/ weapons/     the unit and weapon definitions
  gamedata/ scripts/  unit scripts, sounds, icon types
  icons/ unitpics/    the role icons and the unit pictures
  modinfo.lua modoptions.lua   the game description and the lobby options
  luaui.lua luaai.lua          the interface and AI entry points
  vb_build.txt        the build stamp (written by build_sdz.py, shown by the build panel)
tools/                the generators (models, textures, defs, icons, map) and the smoke tests
map/                  the map source
dist/                 the build output: voidborn.sdz, voidborn_rift.sd7
out/                  generated images that are not part of the game
vb/                   the website
docs/                 notes
```

`build_sdz.py` (repo root) is the one command that builds and installs; `install_and_build.py` unpacks a source zip over the repo first.

## Building and installing (`build_sdz.py`)

`python3 build_sdz.py` is the one command that builds the game and proves that the engine will run it (`pip install lupa` first). It stops with exit code 1 at the first failed step:

1. every Lua file in `game/` must compile (Lua 5.1, as in the engine)
2. the smoke tests `tools/test_*.py` must pass
3. `dist/voidborn.sdz` is built, with a build stamp `<date-time>-<content hash>` in `vb_build.txt`
4. the archive is re-opened and compared with `game/` file by file (names, sha256, CRCs, `modinfo.lua` at the root, Lua syntax of the archived copy)
5. it is copied atomically to `~/.spring/games/voidborn.sdz` (`--games-dir` or `SPRING_GAMES_DIR` to change it) and the copy is compared with the build; other archives of the same game in that folder are renamed `*.disabled-<stamp>` so that they cannot shadow it (copies in other data folders are reported)
6. `spring-headless` runs `Watch_Bot_vs_Bot.txt` and its log must contain `[VB] build <stamp>` (logged by `game/LuaRules/Gadgets/vb_buildinfo.lua` from the archive the engine really mounted). Without a headless engine the step is reported as NOT verified (`--engine PATH`, `--strict-engine`, `--no-engine-check`)

In game, the title bar of the build panel ends with the same stamp. Options: `--no-install`, `--no-tests`, `--keep-others`.

Everything the game contains lives in `game/` (that folder is what `build_sdz.py` zips). The old copies of those folders at the repo root were removed. `tools/` holds the generators (paths are relative to the repo), `map/` the map source, `dist/` the build output.

## Health bars

`game/LuaUI/Widgets/vb_healthbars.lua` draws a bar above every visible unit: green to red for your units and allies, a red bar for enemies, and a second blue bar for the build progress of an unfinished structure. `/vbhealth` cycles *always* / *damaged* (and selected) / *off*; the choice is remembered. Structure tiles of the build panel show a pie with the build progress of the most advanced one under construction (blue pie = a builder is working on it, `xN` = how many are being built).

### Zoomed-out icons

Every unit shows a **role icon** when the camera is far out. The icons are shared by both factions: one per role (commander, builder, scout, raider, assault, artillery, support, heavy, factory, metal extractor, energy, advanced energy, storage, radar, light defence, heavy defence), white glyphs that the engine tints with the team colour. Forge designs use the icon of their base unit. `tools/gen_icons.py` draws them (`game/icons/vb_<role>.png`) and writes `game/gamedata/icontypes.lua`; `tools/gen_defs.py` sets `iconType = "vb_<role>"` on every unit def, and `tools/test_icons.py` checks the wiring. How far out the camera must be before units turn into icons is the engine's own setting (`/disticon <n>`).

### Sensor ranges (`/vbranges`)

`game/LuaUI/Widgets/vb_ranges.lua` draws the **line of sight (green)** and **radar (blue)** circles on the ground for the selected units, using the live values (forge designs with extra sight, radars that are switched off). While you are placing a structure, its ranges are shown at the mouse. `/vbranges` cycles *selected* / *all your units* / *off*; the choice is remembered.
