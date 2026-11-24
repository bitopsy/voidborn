# voidborn 1.4 Release Notes

## 🎉 What's New in Version 1.4

voidborn 1.4 is a major release featuring three significant gameplay systems, balance updates, and quality of life improvements.

---

## ✨ New Features

### 1. **Tier 2 Upgrade System**
- **Factory upgrade gate**: Factories must be upgraded to Tier 2 to unlock the unit forge
- **Upgrade cost**: 2000 metal and 2800 energy over 45 seconds
- **T2 roster**: 7 new Tier 2 units available through the forge
- **Tests pass**: `tools/test_t2.py` ✅

### 2. **Mushrooms & Gray Matter**
- When units die, they shrink into gray matter lumps over ~2 seconds
- Gray matter grows into 8 different mushroom shapes
- Mushroom size is proportional to energy capacity (`8 + 2.4 * sqrt(cap)`)
- Stalks grow first, caps open later; 1/3 of mushrooms stay as small "buds"
- Nurses can reclaim ~50 energy/sec from mushroom patches
- Mushroom patches hold energy up to the dead unit's max health / 15

### 3. **Statistics Dashboard**
- **Ctrl+Shift+D** toggles the dashboard
- Live graphs showing resource income/outgo, unit counts, and more
- End-game summary report
- Full documentation on the new **Story page** (`/story.html`)
- All 31 game options and 11 keybindings documented

### 4. **D-Gun (Destabilisation Gun)**
- Both commanders (Hierophant & Matriarch) have the D-gun as their third weapon
- **900 energy cost** per shot
- **Wave stuns enemies**: 9 seconds at centre, 1 second at rim
- **Electric shield visual** around stunned units
- **Ctrl+B**: 5-second countdown detonation of selected units
- **D key**: Aim with mouse at targeted location

### 5. **Mex Snapping Constraints**
- **CELL=16**: Metal map cell size
- **SNAP_MARGIN=8**: Snap margin for snapping near cell edges
- **CLUSTER_CELLS=4**: Snap to connected metal cells within 4 cells

### 6. **Website Updates**
- **New story page** (`/story.html`): Documents the Rift, Choir vs Maw, all units, mechanics, options, and keys
- **Navigation links** added to all pages (Story link in navbar)
- **7 new web pages** total (including story.html)

### 7. **AI Fix**
- Removed `[AI0]`/`[AI1]` blocks from startscripts that caused "unknown skirmish AI" error
- VoidBot gadget now handles AI functionality
- `bot_skill` set to 2 (Medium) in all startscripts

### 8. **Version & Configuration**
- **Version**: 1.4 (updated from 1.0 in `game/modinfo.lua`)
- **GameType**: Voidborn 1.4 in all startscripts
- **Engine**: 2026.11.02 (Recoil) with `gl.CreateList` support

---

## 📁 Modified Files

### Core Game Systems
- `game/LuaRules/Gadgets/vb_factory_upgrade.lua` - Factory upgrade gate
- `game/LuaUI/Widgets/vb_upgrade_bars.lua` - Upgrade progress display
- `game/LuaRules/Gadgets/vb_mushrooms.lua` - 8 mushroom shapes, gray matter
- `game/LuaRules/Gadgets/vb_dgun.lua` - Destabilisation Gun gadget
- `game/LuaRules/Gadgets/vb_explode.lua` - 5-second countdown detonation

### UI & Configuration
- `game/LuaUI/Widgets/vb_dashboard.lua` - Dashboard widget + Resign option
- `game/LuaUI/Widgets/vb_unitstats.lua` - Census disabled by default
- `game/LuaUI/Widgets/vb_buildpanel.lua` - Always open by default
- `game/LuaUI/Widgets/vb_hotkeys.lua` - D key = dgun, Ctrl+B = detonate
- `game/LuaUI/Widgets/vb_mex_click.lua` - Mex snapping (CELL=16, etc.)
- `game/LuaUI/Widgets/vb_stats_data.h.lua` / `vb_stats_draw.h.lua` - Dashboard headers
- `game/LuaUI/Widgets/vb_resbar.lua` - Resource bar widget

### Website
- `vb/story.html` - New page (19KB) documenting all features
- `vb/index.html`, `vb/play.html`, `vb/maps.html`, `vb/forge.html`, `vb/roadmap.html` - Navigation updated

### Configuration
- `game/modinfo.lua` - version "1.4"
- `Play_Choir_vs_Bot.txt`, `Play_Maw_vs_Bot.txt`, `Watch_Bot_vs_Bot.txt` - bot_skill=2, GameType=1.4

### Tests
- `tools/test_t2.py` - T2 factory upgrade tests ✅
- `tools/test_site.py` - Website tests ✅
- `tools/test_stats.py` - Dashboard tests ✅
- + 6 other test suites ✅

---

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 171 compiled |
| **Test suites** | 9 passed |
| **Archive size** | 333 files, 7.2 MB |
| **Website pages** | 8 HTML pages |
| **New units** | 7 T2 units + 8 mushroom shapes |
| **Game options** | 31 documented |
| **Keybindings** | 11 documented |

---

## 📥 Download

- **Windows Standalone**: `voidborn_windows.sd7` / `voidborn_windows.zip`
- **Linux Standalone**: `voidborn_linux.sd7` / `voidborn_linux.zip`
- **Map archive**: `voidborn_rift.sd7` (1.7 MB)
- **Source code**: [GitHub](https://github.com/bitopsy/voidborn)

### 0.21

- New arc and wave gadgets for enhanced battlefield effects
- Additional sound effects (arc, beam thin, sonar, warble)
- Expanded unit variety with new arc, beam, and special generation tools
- Improved weapon effect systems and definition generators
- Growth parameter revisions: split at 0.25 experience, growth before split doubled to 2.0x

---

### 0.20
- Rally points for labs: units follow lab's rally orders (move/fight/patrol/guard, shift adds waypoints, stop clears, carries over through upgrades)
- T2 upgrade sound: gadget plays tier2_ready.wav / tier3_ready.wav itself; widget lines removed to prevent double playing
- Weapon graphics: new impact bursts and projectile trails for all five factions; thicker lasers, bigger plasma, cannon/missile trails
- Repeat on labs: canRepeat = true added to all 15 lab defs; repeat loops production line, survives upgrade

## 📦 Installation

```bash
# Extract the archive into your Spring engine data folder
# Or use the installer scripts provided

# To play:
# 1. Extract the archive into your ~/.spring/engine/data folder
# 2. Run: spring-headless voidborn_rift.sd7
# 3. Or use the Play button on the website
```

---

## 🐛 Bug Fixes

- Fixed `[FetchSkirmishAILibrary] unknown skirmish AI specified` error
- Fixed mex snapping constraints (CELL=16, SNAP_MARGIN=8, CLUSTER_CELLS=4)
- Fixed census widget disabled by default
- Fixed build panel always loads open
- Fixed dashboard menu (Stats, Keys, About, Resign)
- Fixed mushrooms: 8 shapes, energy-proportional size, stalk-then-cap growth
- Fixed D-gun: 900 energy, wave stun (9s/1s), mouse aiming
- Fixed version bump to 1.4

---

## 📬 Contact

- **GitHub**: [bitopsy/voidborn](https://github.com/bitopsy/voidborn)
- **Discord**: [discord.gg/voidborn](https://discord.gg/voidborn)
- **Website**: [voidborn.com](https://voidborn.com)

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*
