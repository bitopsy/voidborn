# voidborn 0.15

## 🎉 What's New

* **Cloak toggle for commanders and constructors** — Both commanders (Hierophant, Matriarch) and both constructors (Seer, Weaver) can cloak. A commander pays **250 energy/s**, a constructor **100 energy/s**. The **Cloak** toggle is in the build panel and on key **K**. Choir commanders could not cloak at all before (`canCloak = false`); that is fixed.
* **Hierophant: persistent blue beam** — *Gaze* is now a continuous blue beam (`BeamLaser`, range 470) instead of a stream of laser pulses.
* **Matriarch: long-range acid glob** — *Acid Spit* is now a slow, heavy, splashing projectile with range 560 (was 420 as a fast laser).
* **New faction emblems** — `game/sidepics/choir.png` and `maw.png` are redrawn in the in-game blue and acid-orange palettes.
* **New sounds** — 20 new sound effects for the new weapons, a separate D-gun and Q-gun sound for each faction, and a set of announcements (see below).

### Cloak

* The engine's own cloak button and upkeep are replaced by the gadget `vb_cloak.lua`, which holds the cloak at engine level 3 (free for the engine, no engine decloaking except while stunned) and charges the energy itself. The level is one constant, `CLOAK_LEVEL`.
* Cost by unit kind: `com` = 250 E/s, `con` = 100 E/s (`COST_BY_KIND` at the top of the gadget).
* The cloak drops when the team runs out of energy, the unit dies or is captured, the unit fires the D-gun or Q-gun, or it receives an explicit attack order.
* While cloaked, a unit with weapons is put on hold fire so it does not shoot by itself and give itself away; its previous fire state is restored when the cloak drops.
* The build panel shows the toggle as **Cloak: OFF** (grey) or **Cloak: ON** (cyan). **K** toggles every selected unit that has a cloak and sends the order directly, so it no longer depends on the command index.

### Weapons

| Unit | Weapon | Before | Now |
|---|---|---|---|
| Hierophant | Gaze | LaserCannon, range 430, 43 dmg / 0.55 s | BeamLaser, range 470, blue (`0.2 0.55 1.0`), beam on 0.85 s of each 1.0 s, damage 80 (about per second) |
| Matriarch | Acid Spit | LaserCannon, range 420, speed 900, 48 dmg / 0.55 s | Cannon, range 560, speed 280, 150 dmg / 1.5 s, splash 44, nearly straight flight (`myGravity` 0.02) |

The Cataract Stare / Devour (D-gun) and the Destabilisation Gun (Q-gun) are unchanged in damage, range and cost.

### Sounds

* **Weapons:** `beam_choir` and `hit_beam` (Gaze), `acid_glob` and `hit_glob` (Acid Spit).
* **D-gun, one per faction:** `dgun_choir` (glassy rising chord, clean deep blast) and `dgun_maw` (wet inhale, guttural roar).
* **Q-gun, one per faction:** `qgun_choir` and `qgun_maw`, both ending in the shared `stun_wave` impact.
* **Gun feedback:** `gun_denied` when a manual shot is refused (reloading, out of range, no energy, stunned); `gun_ready` when the Q-gun is loaded again (only for guns that reload in 4 s or more, so the D-gun stays quiet).
* **Announcements** (widget `vb_sounds.lua`): `cloak_on` / `cloak_off`, `commander_lost`, `enemy_commander_down`, `victory`, `defeat`, `tier2_ready` (a Tier 2 factory finishes), `energy_low` and `metal_low` (storage under 3%, at most once per 25 s each).
* All announcements are synthesised jingles in the same style as the existing sounds; there are no voice samples. `/vbsound on|off|vol|ambient` still controls them.

### Faction emblems

* **Choir:** a pale eye with a blue radial iris inside a tilted double halo, light tendrils below, on a deep navy void.
* **Maw:** a front-on ringed mouth with three rings of interlocking teeth, an acid-green and orange throat, carapace spikes and mandibles, on dark crimson.
* Both share one frame and are drawn at 1024 px and downscaled to 512 px.

### Bug Fixes

* Fixed the Choir commander being unable to cloak (`canCloak` was false for every commander in `gen_defs.py`).
* Fixed the cloak dropping on its own: the old boolean cloak was undone by the engine whenever the unit fired or an enemy came near, while the gadget kept charging energy.
* Fixed the **K** hotkey using an off-by-one command index.
* Fixed D-gun and Q-gun refusals being chat messages only; they now also play a sound.

### Game Balance

* **Hierophant Gaze:** range 430 → 470; roughly equal damage per second (about 78 → 80).
* **Matriarch Acid Spit:** range 420 → 560 (the commander's sight distance, so the full range is usable); damage per second about 87 → 100, but the projectile needs about two seconds to cross its full range, so fast targets can dodge it.
* **Cloak:** commander 250 E/s, constructor 100 E/s.

### Gameplay Changes

* **Commanders:** both can cloak; both have a new primary weapon.
* **Constructors:** the Seer and the Weaver can cloak.
* **Sounds:** new announcements for commander loss, enemy commander kills, victory and defeat, Tier 2, cloak and low resources.

### Testing Notes

* Not play-tested in the engine. The Lua files were checked for syntax, the cloak gadget was run against a mock of the Spring API (cost, toggle, drain, out-of-energy drop, attack-order drop), and every sound item was checked to point at an existing file.
* Beam-laser damage scaling differs between engine builds; if Gaze hits too hard or too soft, tune `damage` of `ch_hierophant_w1`.
* If the cloak does not hold, change `CLOAK_LEVEL` in `vb_cloak.lua`.
* `tools/gen_defs.py` still lacks the Q-gun (third weapon). Regenerate `game/weapons/vb_weapons.lua` and the unit files with care: `vb_weapons.lua`, `mw_matriarch.lua`, `ch_hierophant.lua`, `mw_weaver.lua` and `ch_seer.lua` were edited directly. Rerun `tools/add_sounds.py` after regenerating.
* The version in `game/modinfo.lua` and the start scripts is 0.15.

### Files Modified

* `game/LuaRules/Gadgets/vb_cloak.lua`
* `game/LuaRules/Gadgets/vb_manualfire.lua`
* `game/LuaUI/Widgets/vb_buildpanel.lua`
* `game/LuaUI/Widgets/vb_hotkeys.lua`
* `game/LuaUI/Widgets/vb_sounds.lua`
* `game/gamedata/sounds.lua`
* `game/units/mw_matriarch.lua`, `game/units/ch_hierophant.lua`, `game/units/mw_weaver.lua`, `game/units/ch_seer.lua`
* `game/weapons/vb_weapons.lua`
* `game/sidepics/choir.png`, `game/sidepics/maw.png`
* `game/sounds/` — 20 new `.wav` files: `beam_choir`, `hit_beam`, `acid_glob`, `hit_glob`, `dgun_choir`, `dgun_maw`, `qgun_choir`, `qgun_maw`, `stun_wave`, `gun_ready`, `gun_denied`, `cloak_on`, `cloak_off`, `commander_lost`, `enemy_commander_down`, `victory`, `defeat`, `energy_low`, `metal_low`, `tier2_ready`
* `tools/gen_defs.py`, `tools/gen_sounds.py`, `tools/add_sounds.py`, `tools/gen_sidepics.py`
* `README.md` (commander weapon ranges)
* `docs/release-0.15.md` (this file)
