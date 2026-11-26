### Voidborn 0.24 Release Notes

## 🎉 What's New in Version 0.24

### 1. **Version Bump**
- `game/modinfo.lua` - version updated from "0.23" to "0.24"

### 2. **Dashboard: Spectator Enhancements** (major)
- **Skill ratings displayed**: OpenSkill/Elo numbers shown for spectators in the dashboard HUD
- **Country flags**: Player country codes (cc) rendered as flags alongside player names
- **Spectator list**: Dedicated spectator rows shown when expanded (`/vbdash specOpen`)
- **Skill uncertainty** (`sigma`): displayed alongside skill ratings
- **New header files**: `LuaUI/Headers/vb_countries.h.lua` and `LuaUI/Headers/vb_uiscale.h.lua` added

**Changes in `game/LuaUI/Widgets/vb_dashboard.lua`:**
- `COUNTRY` table included for flag lookups
- `specList` table holds all spectators with name, country code, skill, sigma, active status, ping
- `skillSeen` flag tracks whether any player has a visible skill rating
- `SPEC_MAX = 8` limits spectator rows shown when expanded
- `SkillOf()` / `SigmaOf()` / `SkillText()` helper functions parse lobby-sent skill data
- `Spring.GetPlayerInfo(pid, true)` now reads skill/uncertainty custom keys
- Spectators sorted alphabetically by name

### 3. **Build Panel: UI Scaling & Developer Tools**
- **`vb_uiscale.h.lua`** - Dynamic UI scaling based on viewport height:
  - 1080p and below: 116% boost
  - 1440p: 116% → 100% (easing)
  - 2000px+: 100%
  - `/vbtext <percent>` overrides the boost
  - `M.Compact(boost)`: hides mini dashboard details when boost is large

- **Hidden orders**: WAIT, TIMEWAIT, DEATHWAIT, SQUADWAIT, GATHERWAIT, LOAD_UNITS orders hidden from build panel by default
- **Developer tools** (`vb_dev` mod option): command hotkeys shown when `vb_dev = "1"`
- **`vb_dev`** mod option added to `game/modoptions.lua`

**Changes in `game/LuaUI/Widgets/vb_buildpanel.lua`:**
- `OKUI, UI = pcall(VFS.Include, "LuaUI/Headers/vb_uiscale.h.lua")` for scaling
- `TextBoost(vsy, override)` function for dynamic text sizing
- `HIDE_ORDER` table mapping hidden command IDs
- `HiddenOrder(c)` checks if order should be hidden
- `DEV = (Spring.GetModOptions() or {}).vb_dev == "1"` developer flag
- `KeyHint(c)` shows hotkey hints in developer mode

### 4. **New Widgets & Headers**
- `game/LuaUI/Headers/vb_countries.h.lua` - ISO 3166 country code → English name mapping (all nation flags)
- `game/LuaUI/Headers/vb_uiscale.h.lua` - UI text boost logic for varying resolutions
- `game/LuaUI/Widgets/vb_commander_names.lua` - commander name display widget
- `game/LuaUI/Widgets/vb_minimap_nav.lua` - minimap navigation widget

### 5. **Build & Infrastructure**
- `dist/voidborn.sdz` rebuilt (stamp updated)
- All Lua files verified against sources
- Archive contains 755+ entries, modinfo.lua at root

### 6. **Start Script Reorganization**
- Various `Play_*.txt` and `Watch_*.txt` start scripts moved to `start/` subdirectory for cleaner repo layout

## 🛠 How to Try the New Features

### Dashboard Skill Ratings
Ensure the lobby sends skill data via custom keys:
- `skill` / `openskill` - the rating number
- `openskilluncertainty` / `skilluncertainty` - the uncertainty sigma

Then press `/vbdash specOpen` to see spectator skill ratings, or enable them in the dashboard settings.

### UI Scaling
The dashboard and build panel automatically scale UI text based on viewport height:
- Default boost: 116% at 1080p and below
- Manual override: `/vbtext 120` (or `/vbtext auto`)

### Developer Tools
Enable with mod option:
```lua
vb_dev = "1"
```
This shows command hotkeys in the build panel and other widgets.

## 📁 Files Changed

### Dashboard
- `game/LuaUI/Widgets/vb_dashboard.lua` - spectator skills, country flags, specList
- `game/LuaUI/Headers/vb_countries.h.lua` - country code names (all nations)
- `game/LuaUI/Headers/vb_uiscale.h.lua` - UI text boost logic

### Build Panel
- `game/LuaUI/Widgets/vb_buildpanel.lua` - hidden orders, dev tools, UI scaling
- `game/LuaUI/Headers/vb_uiscale.h.lua` - text boost function

### New Files
- `game/LuaUI/Headers/vb_countries.h.lua` - country name mapping
- `game/LuaUI/Headers/vb_uiscale.h.lua` - UI scaling function
- `game/LuaUI/Widgets/vb_commander_names.lua` - commander names widget
- `game/LuaUI/Widgets/vb_minimap_nav.lua` - minimap navigation

### Configuration
- `game/modinfo.lua` - version "0.24"
- `game/modoptions.lua` - `vb_dev` mod option added

### UI Widgets (new)
- `game/LuaUI/Widgets/vb_commander_names.lua`
- `game/LuaUI/Widgets/vb_minimap_nav.lua`

### Start Scripts (reorganized)
- Several `Play_*.txt` and `Watch_*.txt` moved to `start/`

### Sounds & Build
- `dist/voidborn.sdz` rebuilt
- `game/vb_build.txt` - updated stamp

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 357+ compiled |
| **New headers** | vb_countries.h.lua, vb_uiscale.h.lua |
| **New widgets** | vb_commander_names.lua, vb_minimap_nav.lua |
| **Mod options** | vb_dev added |
| **Archive size** | 755+ files |
| **Dashboard features** | Spectator skills, country flags, UI scaling |

## 🛠 Building

```bash
python3 build_sdz.py --no-engine-check --no-install --no-tests
# Produces dist/voidborn.sdz with updated stamp
```

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*