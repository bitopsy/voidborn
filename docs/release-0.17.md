# voidborn 0.17

## 🎉 What's New

* **The fifth and last faction: the Haptic Grasp (the Hand, the sense of touch).** The Choir has the eye, the Maw the mouth, the Tympan the ear and the Miasma the nose; 0.17 adds the hand. It has the full roster of the others: a commander, builder, scout, raider, assault unit, artillery, support unit and heavy, eight structures, and a Tier 2 factory with five more units: 22 units, each with its own model, texture, unit picture, script and sounds.
* **Hands and tentacles.** Palms for bodies, fingers for legs and guns, tentacle skirts, suckers, and a fingerprint on every fingertip, palm and sucker. Slate-blue flesh, rose veins, ink-dark plates and a coral nerve-glow.
* **Not far-sighted.** The shortest sight of any faction (the fighters see about 330 elmos against about 560 for the others), **no radar on any unit**, a Whisker Mast that reaches only 1100 (the others 2300 – 2800) and the shortest artillery (650 T1, 900 T2).
* **Closeness: hits harder the nearer the enemy is.** Every Haptic gun (all but the commander's D-gun and Q-gun) deals up to **+75%** at point-blank range (80 elmos or less between the two surfaces), fading in a straight line to nothing at the weapon's maximum range.
* **Kamikazes and the grip.** The raiders are bombs: a **Clutch** (T1) or **Strangler** (T2) that gets within 70 elmos of an enemy **bursts**, hurts everything around it and **grips** what it reached. A gripped enemy takes another **+25%** from every Haptic weapon for 6 s (Strangler 9 s).
* **Five sides in the lobby** (`Haptic` is new), a fifth emblem, a **faction menu with five cards** (key **5**, `/vbfaction haptic`), five new lobby options, and two start scripts: `Play_Haptic_vs_Bot.txt` and `Watch_5Factions_FFA.txt` (one bot of each faction; the fifth starts on the north island of Voidborn Rift).
* **The bot plays the new faction without any change** (it picks by role, and the Haptic Grasp has all the roles; its raider is simply a kamikaze).

## Haptic Grasp (the Hand)

| Unit | Role | Metal | HP | Altitude | Sight | Weapon (range) |
|---|---|---|---|---|---|---|
| Manus | Hand Commander | 2500 | 4400 | 45 | 360 | Crushing Grasp (400), Squeeze (240), Destabilisation Gun (700) |
| Palp | Builder | 90 | 580 | 50 | 300 | — |
| Whisker | Scout | 36 | 230 | 90 | 380 | Prod (170) |
| Clutch | Raider (kamikaze) | 55 | 300 | 60 | 260 | Latch (60) |
| Fist | Assault | 190 | 1700 | 90 | 300 | Pound (230) |
| Reacher | Long range | 225 | 640 | 140 | 340 | Long Reach (650) |
| Caress | Support | 150 | 740 | 105 | 300 | — |
| Polydactyl | Heavy | 1600 | 10500 | 225 | 380 | Crushing Grip (420), Finger Flurry (260) |

Structures: **Open Palm** (factory, 450 metal), **Fingertip Probe** (metal extractor), **Warm Pad** (energy), **Pulse Point** (advanced energy), **Cupped Palms** (storage), **Whisker Mast** (radar, range 1100), **Pinch Finger** (light defence, 330), **Slam Fist** (heavy defence, 520). The factory upgrades to the **Great Palm**, which builds:

| Unit | Role | Metal | HP | Altitude | Sight | Weapon (range) |
|---|---|---|---|---|---|---|
| Strangler | Raider (kamikaze) | 150 | 900 | 70 | 280 | Wrap (65) |
| Gauntlet | Assault | 500 | 4800 | 100 | 320 | Haymaker (280), Knuckle Burst (200) |
| Lasso | Artillery | 630 | 1150 | 170 | 380 | Lasso Crack (900) |
| Kneader | Support (fast builder) | 370 | 1900 | 110 | 340 | — |
| Hecatoncheir | Heavy | 4050 | 38000 | 300 | 460 | Hundred Fists (520), Hundred Hands (300) |

### Touch (`vb_touch.lua`)

* **Closeness.** A weapon with `customParams.vb_touch` gets `touch_bonus` (0.75) x k more damage, where k is 1 up to `touch_near` (80 elmos) between the two units' surfaces and falls in a straight line to 0 at the weapon's range. Paralysing damage and friendly fire never count. A shot from far away does the plain damage, which is set about level with the other factions' guns of the same role (a Fist's Pound is 62 damage per second, a Hoplite's gaze 57, a Ravager's bolt 66): the Grasp has no disadvantage up close and gains up to 75% there, and its price is the short range and the short sight, so the closeness bonus is a real gain and not a repayment.
* **Kamikaze burst.** A unit with `customParams.vb_kami_dmg / vb_kami_aoe / vb_kami_grip` bursts when an enemy is within 70 elmos (checked ten times a second). The touched enemy takes `vb_kami_dmg` (Clutch 420, Strangler 800); every other enemy inside `vb_kami_aoe` (70 / 95) takes 60% fading to 15% with distance. The damage is dealt by the gadget (`Spring.AddUnitDamage`, credited to the kamikaze, so experience counts); the unit's `selfDestructAs` (`vb_haptic_burst`, `vb_haptic_burst_big`) is only the picture and does 1 damage. A kamikaze that is shot down pops as a small `vb_small`. An ally never triggers it and is never hurt or gripped.
* **Grip.** Everything a burst reached is gripped for `vb_kami_grip` seconds (rules param `vb_grip`): +`grip_bonus` (25%) on every Haptic touch weapon hit, on top of the closeness bonus.
* A Clutch has a tiny weapon (**Latch**, range 60, 3 damage) so that the engine flies it at enemies by itself; the gadget does the rest.
* Lobby options: `touch_bonus` (0.75; 0 switches it off), `touch_near` (80), `grip_bonus` (0.25; 0 switches it off), `kami_scale` (1.0; 0 makes the bursts harmless).

## Not changed

Choir, Maw, Tympan and Miasma: no unit, weapon, sound, model, texture or emblem was touched. The Tympan and Miasma models, textures, unit pictures, scripts, weapons and emblems were regenerated and compared byte for byte with the 0.16 files, and their unit files were put back as they were. The only shared change is that the faction menu now has five cards.

## Other changes

* **Tools.** `tools/designs_f.py` (units and structures, with the hand / finger / tentacle helpers) and `tools/designs_f2.py` (Tier 2) hold the models; `tools/gen_assets.py haptic` writes them. `tools/textures.py` has a Haptic palette and a fifth tile kind, a **fingerprint** (the fourth atlas tile), and the old textures come out identical. `tools/gen_defs.py` writes the Haptic units, scripts, `weapons/vb_weapons_017.lua` and `effects/vb_effects_017.lua` too. **Use `python3 tools/regen_017.py`** to regenerate them: `gen_defs.py` also rewrites the Tympan and Miasma unit files, which carry `script = ...` lines it does not write, so the wrapper puts those files back and patches the same lines into the Haptic ones.
* **Sounds.** 11 new sounds (`gen_sounds.py`, function `haptic`): a select and an acknowledge, a structure select, a touch ping / lash / pound / heavy blow and their hit, the kamikaze burst, and a D-gun and a Q-gun. Run only that function (`python3 -c "import sys; sys.path.insert(0, 'tools'); import gen_sounds; gen_sounds.haptic()"`): the whole script rewrites older files slightly differently. `add_sounds.py` knows the new faction.
* **Tests.** `tools/test_factions.py` checks five factions: rosters, assets, sounds, build lists, the sight / radar / reach limits of the Haptic faction, the touch tags, the kamikaze data, the sides, the five-card menu and the spawner, and the touch gadget against a mock engine (closeness at several distances, the surface distance, the grip, the burst and its falloff, allies, dead units, the lobby options). 38 new checks.
* **Interface.** The ABOUT page of the dashboard describes the fifth faction; the build panel, statistics, forge and bot needed no change.
* Version 0.17 in `modinfo.lua` and the start scripts.

## Honest limits

* **None of this has been played in the engine.** The weapons, the gadget, the kamikaze bursts (`Spring.GetUnitsInSphere`, `Spring.AddUnitDamage`, `Spring.DestroyUnit(..., true)`) and the chase of a Clutch with a 60-elmo weapon are written to the engine's documented API and tested only against a mock. Most likely to need a look: whether a Clutch really flies at the enemy by itself (if it only hovers, give it a longer Latch), and whether hovering aircraft come close enough for the closeness bonus to matter.
* **Balance is a first pass.** Costs sit within 30% of the older factions' averages by role (checked by the tests). The real unknowns are the +75% closeness bonus, how much a swarm of Clutches (10 of them cost 550 metal and burst for 4200 on a clump) outdoes everything else, and the grip. All four can be tuned or switched off in the lobby.
* **The models, the emblem and the sounds** are judged from software renders and the generators, not from the engine.
