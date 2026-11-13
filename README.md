# VOIDBORN — a 3D space RTS for the Spring/Recoil engine

Inspired by Beyond All Reason and zero-k startcraft: commander, metal extractors, solar + advanced energy, a factory, defences, radar, storage, armies of 6 unit types per side. **A key feature: players can create/code their own units via Lua scripts.**

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

Options: `name hp metal energy buildtime sight alt count team x z png pngsize`, and multipliers `speed range dmg reload`. `lua=` (last option) runs on every spawned unit with `unitID` set. `png=` floats an image above each spawned unit (a bare name means `unitpics/<name>.png`; `png=icons/x.png` is used as given, `pngsize=` is in elmos). Put the file in `game/unitpics/` or loose in `<data dir>/unitpics/` (no rebuild needed). Units appear at the mouse cursor unless `x=`/`z=` are given. Results are echoed in the chat log.

## Sound

Every sound is generated by `tools/gen_sounds.py` (no samples, no licensing) into `game/sounds/`; `tools/add_sounds.py` wires them into the unit and weapon defs (rerun it if you regenerate defs with `tools/gen_defs.py`). Sound items live in `game/gamedata/sounds.lua`.

* Units: select / acknowledge voices per faction, "can't" buzz, builder zaps, structure activate / deactivate sounds, commander under-attack alarm.
* Weapons: a different shot and impact sound for light / medium / heavy lasers, acid spit, spore missiles, maw flame and the commanders' super weapon; three explosion sizes.
* UI: hover, click, build-select, open / close. Game events (`vb_sounds` widget): start jingle, structure placed, unit ready, structure finished, commander alarm, looping space ambience.
* `/vbsound on|off`, `/vbsound vol 0-100`, `/vbsound ambient on|off`.

## Experience, growth and splitting

`LuaRules/Gadgets/vb_experience.lua`: mobile non-commander units grow as they gain experience, up to 1.45x their size at `xp = 0.07`. At 0.07 the unit **splits in two**: both halves are normal sized, keep the same health fraction, orders, stances, group and every `/vbcreate` modification (`png`, `name`, `hp`, `speed`, ...; a `lua=` snippet is not re-run), and both start again at experience 0. Commanders and structures never split, and a team that is nearly at its unit cap does not split. Tunables (`SPLIT_XP`, `MAX_GROWTH`, ...) are at the top of the file.

To test quickly: `/vbcreate scout base=mw_skitter lua=Spring.SetUnitExperience(unitID,0.065)` and let it fight.

## Unit census (`/vbstats`)

`vb_unitstats` widget: tracks every unit and shows totals (units, mobile / structures, health, metal value, average / max experience, splits so far), distributions (histograms) of health, speed, range, damage/s, experience and size, the unit types present, and the units closest to splitting.

Values are the live ones. Drag the title bar; click the scope tag to cycle MINE / ALLIES / ALL VISIBLE.

## UI

Hovering a build icon shows a hexagonal stats panel (metal, energy, build time, health, speed, sight, range, damage, DPS, reload, economy values) next to the build panel, with a six-axis radar profile (HP, speed, sight, range, DPS, cost; each axis scaled against the strongest Voidborn unit, square-root scale).

The engine's stock build panel is hidden; the Lua widget `vb_buildpanel.lua` is the only build menu. Widget text uses the generated `fonts/VoidbornGlyph.ttf` (`python3 tools/gen_font.py` rebuilds it).

## Tested vs. not tested

I ran the game in the Recoil 2026.07.04 headless engine with two bots playing 20–30 minutes of game time: asteroids loaded, commanders spawned, builders built, mexes produced metal, factories produced units, armies fought, bases died, commander death ended the game. I also fixed the bugs that run exposed (builder/factory scripts, weapon loading, mex yield).

**Not tested (no GPU here):** how the models, textures, skybox, explosions and UI actually *look and feel* on screen, sounds (there are none), and human-driven play. Models/textures are generated procedurally (previews in the PNGs), so expect a "first pass" look.

Known simplifications: no sounds; unit icons use the engine default; the bot is simple; balance is a first pass (Choir is slightly stronger vs the bot).

## Regenerating / modding

`voidborn_source.zip` has the generators (Python: models, textures, unit/weapon defs, map) and the game folder. `python3 tools/gen_assets.py && python3 tools/gen_defs.py` rebuild the models and all unit/weapon/script files.

## Multiplayer & Community

* **SpringLobby**: http://springlobby.org — The official lobby browser for Spring engine games. Use it to find and join multiplayer games of Voidborn. Host your own server to keep a persistent 24/7 Voidborn world running.
* **Discord**: https://discord.com/channels/1481771055063502925 — Join the Voidborn community to find games, discuss strategies, and coordinate with other players.
* **Website**: https://f33.fr/vb/ — Official Voidborn website with downloads, changelog, and community posts.

We are looking for volunteer 24/7 hosts to keep a persistent Voidborn server running. If you have a server that can run the Spring engine 24/7, please join the Discord and let us know! Help grow the multiplayer community.