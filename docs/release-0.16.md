# voidborn 0.16

## 🎉 What's New

* **Two new factions, one for each of two more senses.** The Choir has the eye and the Maw has the mouth; 0.16 adds the **Tympan Conclave** (the Ear) and the **Miasma Bloom** (the Nose). Each has the full roster of the older two: a commander, builder, scout, raider, assault unit, artillery, support unit and heavy, eight structures, and a Tier 2 factory with five more units. That is 22 units per faction, 44 new unit definitions in all, each with its own model, texture, unit picture, script and sounds.
* **Tympan Conclave — sound.** Pressure waves with a wide splash, pulses of high tones, radar carried by the units themselves, and **Resonance**: damage that grows when the conclave focuses fire. Their ears also **blow the cloak** of enemy commanders and constructors.
* **Miasma Bloom — gas.** Shells, darts and jets of poison. Every hit adds a **poison** stack and **scents** the target, which then stays visible to the Bloom through the fog. The Censer eats mushrooms faster.
* **A faction menu** before the start for players who have not chosen a faction, and a fix that keeps the **commanders' D-gun and Q-gun manual-only** (see below).
* **Four sides in the lobby** (`Choir`, `Maw`, `Tympan`, `Miasma`), four emblems, five new lobby options, and two new start scripts: `Play_Tympan_vs_Bot.txt`, `Play_Miasma_vs_Bot.txt`, plus `Watch_4Factions_FFA.txt`, four bots, one of each faction, on the four start spots of Voidborn Rift.
* **The bot plays both new factions without any change**: it picks what to build by role (`customParams.kind`), and the new factions have all the roles.

## Tympan Conclave (the Ear)

Flying ears: pinnae for wings, conch spirals for bodies, drum membranes for faces, horns for guns, a fringe of hair-cell cilia below. Gold, bronze and flesh, with an amber and violet glow.

| Unit | Role | Metal | HP | Altitude | Weapon (range) |
|---|---|---|---|---|---|
| Auditor | Ear Commander | 2500 | 4300 | 45 | Crescendo (520), Perforate (240), Destabilisation Gun (700) |
| Tuner | Builder | 90 | 540 | 50 | — |
| Whisper | Scout | 40 | 220 | 92 | Tick (250) |
| Tinnitus | Raider | 54 | 360 | 65 | Whine (210) |
| Drummer | Assault | 190 | 1500 | 90 | Bass Wave (360) |
| Trumpeter | Long range | 235 | 620 | 145 | Sonic Boom (800) |
| Lullaby | Support | 150 | 720 | 105 | — |
| Cacophon | Heavy | 1600 | 9800 | 225 | Shockwave (600), Lesser Voices (380) |

Structures: **Echo Chamber** (factory, 460 metal), **Cilia Tap** (metal extractor), **Sun Pinna** (energy), **Harmonic Spiral** (advanced energy), **Wax Vault** (storage), **Auricle Array** (radar, range 2800), **Tuning Fork** (light defence), **Great Gong** (heavy defence). The factory upgrades to the **Grand Echo Chamber**, which builds:

| Unit | Role | Metal | HP | Altitude | Weapon (range) |
|---|---|---|---|---|---|
| Banshee | Raider | 140 | 640 | 70 | Shriek (290) |
| Malleus | Assault | 520 | 4300 | 100 | Hammer Blow (430), Anvil Chorus (330) |
| Foghorn | Artillery | 650 | 1050 | 170 | Foghorn Blast (1150) |
| Siren | Support (fast builder) | 380 | 1800 | 115 | — |
| Organon | Heavy | 4200 | 35000 | 300 | Requiem (780), Hundred Voices (470) |

### Resonance (`vb_resonance.lua`)

* Every weapon with `customParams.vb_resonance` (all Tympan guns except the commander's D-gun and Q-gun) gets **+12% damage for every OTHER Tympan unit that hit the same target in the last 1.5 s**, up to four others (**+48%**). One unit firing alone gets nothing; the same unit in a pack of five gets +48%.
* A hit from a unit of the target's own side, and paralysing damage, never count. The bonus is applied in `UnitPreDamaged`; the number of attackers ringing on a target is written to the unit rules param `vb_resonance` for the interface.
* Lobby options: `resonance_step` (0.12; 0 switches Resonance off), `resonance_max` (4).

### Hearing (`vb_cloak.lua`, `customParams.hear`)

* A unit with `customParams.hear` (distance in elmos) blows the cloak of every **enemy** cloaked unit within that distance, checked ten times a second. The unit cannot cloak again for **5 seconds** and is told "heard by an enemy ear".
* Ears: Whisper 450, Siren 400, Auditor 350, Lullaby 300, **Auricle Array 800**. Lobby option `hear_cloak` switches it off.
* **Radar on units.** Whisper 1500, Foghorn 1200, Auditor 1000, Banshee / Trumpeter / Siren 900, Lullaby 800 (the field is `radar_m` in `tools/gen_defs.py`; the older factions have none). Their line of sight is short (400–560), so they see by radar what they then shoot: the radar blips are targetable at the weapon's range, with the engine's usual inaccuracy.

## Miasma Bloom (the Nose)

Drifting snouts and flowers: nostril faces, trunks that end in a flared bell, gas bladders on tethers, petals. Moss green, aubergine and magenta, with a sulphur glow.

| Unit | Role | Metal | HP | Altitude | Weapon (range) |
|---|---|---|---|---|---|
| Rhinarch | Nose Commander | 2500 | 4700 | 45 | Noxious Breath (520), Asphyxiate (240), Destabilisation Gun (700) |
| Pollinator | Builder | 88 | 600 | 50 | — |
| Sniffer | Scout | 34 | 260 | 90 | Spore Dart (240) |
| Sneezer | Raider | 52 | 620 | 60 | Gas Jet (150) |
| Bellows | Assault | 170 | 2300 | 80 | Fume Bolt (340) |
| Stinkhorn | Long range | 215 | 700 | 140 | Reek Canister (800) |
| Censer | Support | 150 | 820 | 100 | — |
| Proboscis | Heavy | 1500 | 13500 | 215 | Putrid Cannon (620), Spore Cloud (520) |

Structures: **Nostril Pit** (factory, 410 metal), **Truffle Snout** (metal extractor), **Sunlily** (energy), **Ambergris Core** (advanced energy), **Musk Sac** (storage), **Scent Stalk** (radar, range 2300), **Reek Pod** (light defence), **Stench Tower** (heavy defence). The factory upgrades to the **Great Nostril**, which builds:

| Unit | Role | Metal | HP | Altitude | Weapon (range) |
|---|---|---|---|---|---|
| Pollenwing | Raider | 128 | 1150 | 65 | Gas Jet (160) |
| Bloomguard | Assault | 470 | 5400 | 85 | Siege Fume (410), Spore Pod (380) |
| Fumigator | Artillery | 610 | 1350 | 150 | Fumigation (1180) |
| Perfumer | Support (fast builder) | 350 | 2100 | 110 | — |
| Titan Arum | Heavy | 3800 | 48000 | 290 | Putrefaction (700), Corpse Cloud (600) |

### Poison and scent (`vb_miasma.lua`)

* A weapon with `customParams.vb_poison_dps` / `vb_poison_secs` adds one **poison stack** per hit. A stack is worth **8% of the weapon's damage per second** (5% for the flame jets, which hit ten times a second); at most **five stacks** per unit, the oldest drops out; all of them last **6 s after the last hit**. The damage is applied twice a second as plain damage credited to the poisoner (so it counts for experience) and never poisons again by itself. Friendly fire does not poison.
* **Scent.** The same hit marks the target for the poisoner's ally team for **10 s**: `Spring.SetUnitLosState` plus `Spring.SetUnitLosMask` keep its position and type visible through the fog; the mask is released when the scent runs out or the unit dies. The calls are wrapped in `pcall`, so a different engine build cannot crash the game with them.
* Lobby options: `poison_scale` (damage multiplier, 1.0; 0 = no poison damage), `scent_secs` (10; 0 = no mark).
* **Foraging.** The **Censer** has reclaim speed 41.6 against 30.4 for the other tier 1 supports, so it eats the mushrooms of fallen units about 37% faster.

## Not changed

Choir and Maw: no unit, weapon, sound, model or texture of the first two factions was touched (their textures were regenerated and compared pixel for pixel; their unit and weapon files were regenerated in a scratch copy and compared). The one rule of theirs that moves is that **the cloak gadget now also reads `hear`**, which only the new Tympan units carry.

## Commander guns: manual only (fix)

* **The bug:** a commander ordered to attack fired its D-gun (seen with the Hierophant). The cause was in the unit scripts: `AimWeapon2` of the Hierophant (the D-gun) and `AimWeapon3` of the Matriarch (the Q-gun) returned `true`, so the engine was told the gun was aimed whenever it had a target, and the Hierophant had no `AimWeapon3` at all.
* **The fix, in layers.** (1) In the scripts of **all four commanders** (Hierophant, Matriarch, Auditor, Rhinarch) `AimWeapon2` and `AimWeapon3` now return `false` and never turn the head: the engine can never fire the D-gun or the Q-gun, whatever the order, the fire state or the target. The generator writes them like this. (2) The eight weapondefs also carry `noAutoTarget = true` next to `commandFire = true`. (3) `vb_manualfire.lua` implements `AllowWeaponTarget` and refuses any target the engine picks for those weapons.
* The only shot they make is the projectile `vb_manualfire.lua` spawns when you click the D-Gun / Q-Gun button or press **D** / **Q** and click a point; that path does not use the weapon's aim and is unchanged. The bot never fires them. Checked by `tools/test_factions.py` (scripts, weapondefs and the gadget against a mock engine); not played in the engine.

## Faction menu

* A player whose team has **no side** (not chosen in the lobby or the start script) gets a **faction menu** before the game starts: four cards with the emblems, Choir, Maw, Tympan, Miasma. Click a card, press 1 – 4 or type `/vbfaction <name>`; the choice can be changed until the start and the commander of that faction is spawned. No choice: the old default (sides in turn by team number). A side set by the lobby or the start script is final; spectators and replays see no menu.
* `game/LuaUI/Widgets/vb_faction_menu.lua` (the menu) and `game/LuaRules/Gadgets/game_spawn.lua` (`vbfaction:<Side>` is accepted from the team's own player, before the start, for a side that exists, only for a team without a side). Lobby option `faction_menu` (default on) hides the menu. New start script `Play_Choose_Faction_vs_Bot.txt` (no `Side=`) shows it.
* Menu logic and spawning are tested against a mock engine; how the panel *looks* and where it sits next to the engine's Start button is not.

## Other changes

* **Tools.** `tools/designs_c.py` (Tympan), `designs_d.py` (Miasma) and `designs_t2b.py` (their tier 2) hold the models. `tools/gen_assets.py tympan miasma` writes only their models, textures and unit pictures and merges `out/meta.json`; `tools/preview_factions.py` renders a contact sheet of one faction. `tools/textures.py` has two new palettes and a fourth atlas tile that is an eye for the first two factions, a **drum membrane** for the Tympan and a **nostril** for the Miasma; the old textures come out identical.
* **`tools/gen_defs.py` now writes only the new factions by default** (units, scripts, `weapons/vb_weapons_016.lua`, `effects/vb_effects_016.lua`). The old behaviour is `--all`: Choir and Maw carry hand edits since 0.15 (the Q-gun, the Gaze beam, the Acid Spit glob, the cloak flags), so a full run overwrites them; review the diff after it. The Q-gun is now a builder (`qgun()`) the new commanders use.
* **Sounds.** 20 new sounds: a select and an acknowledge for each faction, a structure select for each, a sonic ping / pulse / wave / boom and its hit, a gas dart / lob / heavy lob / hiss and its hit, and a D-gun and a Q-gun for each new faction (`gen_sounds.py`, function `new_factions`, drawn after the older recipes). `tools/add_sounds.py` picks a weapon's faction from its name instead of guessing from its explosion. **Rerunning `gen_sounds.py` rewrites some of the older sound files in a slightly different way; restore them from the repository and keep only the new files.**
* **Tests.** `tools/test_factions.py` (new, in `build_sdz.py`'s test step) checks the four rosters, the models, scripts, pictures, pieces, build lists, sounds, weapon tags and the three gadgets against a mock engine. `tools/test_icons.py` now asks for "a unit of every faction per role" instead of "both factions".
* **Interface.** The ABOUT page of the dashboard describes all four factions; the build panel, statistics, forge and bot needed no change.
* Version 0.16 in `modinfo.lua` and the start scripts.

## Honest limits

* **None of this has been played in the engine.** The weapons, the two gadgets, the scent mark and the radar targeting are written to the engine's documented API and tested only against a mock. Whether the scent mark also reveals a *cloaked* unit, whether radar blips are shot at the way the notes above say, and how all four factions feel against each other is unknown until someone plays it.
* **Balance is a first pass.** Costs sit within 30% of the older factions' averages by role (checked by the tests), hit points and damage were set by the same rules of thumb, and the two new tricks (up to +48% from Resonance, up to +40% damage over time from poison) are the real unknowns. Both can be tuned or switched off in the lobby.
* The models and emblems are judged from software renders and may need a pass once seen in the engine.
