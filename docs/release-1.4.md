# voidborn 1.4

## 🎉 What's New

* **Tier 2 upgrade system** — Factories can be upgraded to Tier 2 for 2000 metal and 2800 energy over 45 seconds, unlocking T2 units and the unit forge.
* **Mushrooms & gray matter** — When units die, they shrink into gray matter lumps that grow into 8 procedural mushroom shapes. Size is proportional to energy capacity. Stalks grow first, caps open later. 1/3 of mushrooms stay as small "buds."
* **Statistics dashboard** — Dashboard widget (Ctrl+Shift+D) with live graphs, end-game report, and full docs on the new story page.
* **D-Gun** — Both commanders (Hierophant, Matriarch) have a third weapon: the Destabilisation Gun. Fires a slow shell that lands and spreads a 240-elom wave. Enemies stunned: 9s at centre, 1s at rim. Electric shield visual.
* **Mex snapping** — Tight CELL=16 snapping with SNAP_MARGIN=8 and CLUSTER_CELLS=4 for connected metal cells.
* **Website** — New `/story.html` page documents all units, mechanics, options, and keys. Navigation links added to all pages.
* **AI fix** — Removed `[AI0]`/`[AI1]` blocks from startscripts. VoidBot gadget now handles AI. `bot_skill` set to 2 (Medium).
* **Version 1.4** — `game/modinfo.lua` updated, `ENGINE_VERSION: "2026.11.02"`.

### Bug Fixes

* Fixed `[FetchSkirmishAILibrary] unknown skirmish AI specified` error
* Fixed census widget disabled by default
* Fixed build panel always loads open
* Fixed dashboard menu (Stats, Keys, About, Resign)
* Fixed mushrooms: 8 shapes, energy-proportional size, stalk-then-cap growth
* Fixed D-gun: 900 energy, wave stun (9s/1s), mouse aiming

### Game Systems

* **Tier 2 upgrade** — Factories upgrade for 2000 metal + 2800 energy over 45 seconds
* **Mushrooms** — 8 procedural shapes, energy-proportional size, stalk-then-cap growth, 1/3 bud mushrooms
* **D-Gun** — 900 energy, 9s centre / 1s rim stun, Ctrl+B 5s countdown, mouse aiming
* **Website** — New story page, nav links on all pages
* **AI** — VoidBot active, bot_skill=2

### Game Balance

* **Tier 2 units**: Panopticon (34000 HP), Sclera Knight (4200 HP), Lidless Lance (1100 HP), Singularity Heart (3600 HP), Iris Womb (3300 → 7200 HP)
* **Mushroom shapes**: 8 varieties with different forms and palettes
* **D-Gun energy**: 900 (reduced from 1000)

### Gameplay Changes

* **Commanders**: Both have D-gun as third weapon
* **Website**: Story page with all features documented
* **UI**: Census disabled, build panel always open, dashboard with Resign

### Files Modified

* `game/LuaRules/Gadgets/vb_factory_upgrade.lua`
* `game/LuaRules/Gadgets/vb_mushrooms.lua`
* `game/LuaRules/Gadgets/vb_dgun.lua`
* `game/LuaRules/Gadgets/vb_explode.lua`
* `game/LuaUI/Widgets/vb_dashboard.lua`
* `game/LuaUI/Widgets/vb_unitstats.lua`
* `game/LuaUI/Widgets/vb_buildpanel.lua`
* `game/LuaUI/Widgets/vb_hotkeys.lua`
* `game/LuaUI/Widgets/vb_mex_click.lua`
* `game/LuaUI/Widgets/vb_stats_data.h.lua`
* `game/LuaUI/Widgets/vb_stats_draw.h.lua`
* `game/LuaUI/Widgets/vb_resbar.lua`
* `vb/story.html`
* `game/modinfo.lua` (version 1.4)
* `Play_Choir_vs_Bot.txt`, `Play_Maw_vs_Bot.txt`, `Watch_Bot_vs_Bot.txt`
- `tools/test_t2.py`, `tools/test_site.py`, `tools/test_stats.py`

### Download

* **Windows Standalone**: `voidborn_windows.sd7` / `voidborn_windows.zip`
* **Linux Standalone**: `voidborn_linux.sd7` / `voidborn_linux.zip`
* **Map archive**: `voidborn_rift.sd7` (1.7 MB)
* **Source code**: [GitHub - bitopsy/voidborn](https://github.com/bitopsy/voidborn)

### Installation

```bash
# Extract the archive into your Spring engine data folder
# Or use the installer scripts provided

# To play:
# 1. Extract the archive into your ~/.spring/engine/data folder
# 2. Run: spring-headless voidborn_rift.sd7
# 3. Or use the Play button on the website
```