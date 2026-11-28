### Voidborn 0.26 Release Notes

## 🎉 What's New in Version 0.26

### 1. **Dashboard: ELO~ Rating & Frontline Analysis** (major)
- **New HUD columns** added to the player list: **ELO~** (performance rating) alongside SCORE, ARMY, M/S, E/S, UNITS, PING, FPS
- **ELO~ rating system**: Estimated performance rating based on army, income, damage dealt/taken, and value killed/lost — compared against opponents and the field average (starts at 1500, gains confidence over first 10 minutes)
- **Frontline tab** added to the dashboard: shows territory, frontline position, who is stronger at the front, and territory over time
- **Speed controls** for replays and single player: buttons at top right of timeline (0.5x to 12x) and `/vbdash speed <n>`
- **Front tab** added to dashboard tab list (replaces old order, now tabs are: overview, graphs, economy, combat, **front**, army, share, settings, keys, about)
- **Screen settings** in HUD commands: `/vbdash screen <fullscreen|windowed|borderless>` and `F11` for whole-game window mode

**Changes in `game/LuaUI/Widgets/vb_dashboard.lua`:**
- New `ELO~` column in HUD (width 34, next to ARMY)
- `eloNow[]` table tracks per-team rating per frame
- `ELO_W` weight table: av (0.30), mi (0.20), dd (0.20), dt (0.10), kv (0.10), lv (0.10)
- `ELO_PER_LN = 380` rating points per unit of log ratio
- `ELO_PER_SKILL = 47` OpenSkill points to ELO points
- `EloOf(ctx)` function computes the rating from leaderboard data
- New **Front tab** (`TabFront`) shows frontline territory and analysis
- HUD column identifiers updated: `elo` added, `units` width reduced from 56 to 52, ping width reduced from 30 to 28, fps width from 26 to 24
- `HUD_PING` variable tracks ping column index
- `DEV_OPTION` and `DevOn()` functions for dev mode integration
- `ActivateDev()` enables cheats and loads dev widgets

### 2. **Build Panel: Version & Key Hints** (major)
- **Game version display**: Build tag now shows the game version from `Game.gameVersion` or falls back to `modinfo.lua` version
- **Developer key hints**: `showKeys` flag controls whether hotkey hints are shown in the build panel (can be toggled on/off, not just via `vb_dev` mod option)
- **Build key caching**: `BuildKey(ud)` function caches keybindings for units/structures, supporting both Voidborn hotkeys and engine defaults
- **`vb_hotkeys.lua`** `t = repeat` (changed from `t = resurrect`), `y = capture` removed

**Changes in `game/LuaUI/Widgets/vb_buildpanel.lua`:**
- Version detection logic: tries `Game.gameVersion`, falls back to `modinfo.lua` version
- `showKeys` variable and `KeyHint(c)` updated to support non-dev mode key hints
- `buildKeyCache[]` caches unit/build key mappings
- `Is(v)` helper checks if a hotkey value stands for a unit

### 3. **Test Updates**
- **`tools/test_buildpanel.lua`** - Updated to match new grid behavior: when nothing selected, says "Select unit to load menu"; qgun/dgun order buttons get energy LED
- **`tools/test_labs.lua`** - Updated to check for "Select unit to load menu" when nothing selected; legend shows no counts

### 4. **Configuration**
- `game/modinfo.lua` - version bumped from "0.25" to "0.26"

## 🛠 How to Try the New Features

### ELO~ Rating
The ELO~ rating appears in the dashboard HUD column alongside SCORE, ARMY, etc. It's estimated from the match so far and starts at the field average (1500 when lobby doesn't send OpenSkill data).

### Front Tab
Press `/vbdash front` or navigate to the **Front** tab in the dashboard to see:
- Territory control for each side
- Frontline position
- Who is stronger at the front
- Territory over time graph

### Build Panel Key Hints
- Hotkey hints now appear by default (not just via `vb_dev = "1"`)
- Includes Voidborn hotkeys and engine defaults
- Toggle with the **Keys** button or `/vbkeys` command

### Game Version in Build Tag
The build stamp now includes the game version (e.g., "v 0.26" or the version from `modinfo.lua`).

## 📁 Files Changed

### Dashboard
- `game/LuaUI/Widgets/vb_dashboard.lua` - ELO~ rating, Front tab, HUD column updates, speed controls, screen commands

### Build Panel
- `game/LuaUI/Widgets/vb_buildpanel.lua` - Version detection, key hints, build key caching

### Test Tools
- `tools/test_buildpanel.lua` - Updated test expectations
- `tools/test_labs.lua` - Updated test expectations

### Configuration
- `game/modinfo.lua` - version "0.26"

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 363 compiled |
| **Dashboard changes** | ELO~, Front tab, HUD columns, speed controls |
| **Build panel changes** | Version, key hints, key caching |
| **Test updates** | 2 test files modified |
| **Archive size** | 1019 files (carried forward from 0.25) |

## 🛠 Building

```bash
python3 build_sdz.py --no-engine-check --no-install --no-tests
# Produces dist/voidborn.sdz with updated stamp
```

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*