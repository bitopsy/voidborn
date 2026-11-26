### Voidborn 0.25 Release Notes

## 🎉 What's New in Version 0.25

### 1. **Crater Gadget Debug & Development** (major)
- **`game/LuaRules/Gadgets/vb_crater.lua`** - Full debug output system added:
  - `DEBUG = true` flag controls console logging
  - `Dbg(...)` function prints detailed logs to infolog
  - Weapon watching with "below MIN_BLAST" warnings
  - `/vbcrater` console command to dig test craters
  - Full trace of crater digging operations, rejections, and queue management

**Changes:**
- Every crater dig operation is logged: radius, depth, rim, ground height, blast power
- Weapons that don't meet `MIN_BLAST` threshold are logged as rejected
- `GG.VB_Crater()` function now logs rejection reasons
- End-of-initialization log: "no death weapon found; only Ctrl+D blasts can dig"
- Cheat command `/vbcrater [blast]` to dig a test crater 200 elmos east of your first unit

### 2. **Developer Mode Enhancements**
- **`game/LuaUI/Widgets/dev_console.lua`** - Now loads when dashboard "DEV MODE" button is pressed, not just via `vb_dev` mod option
- **`game/LuaUI/Widgets/vb_memgraph.lua`** - Same conditional loading
- **`game/LuaUI/Widgets/vb_dashboard.lua`** - DEV MODE button in settings panel:
  - When enabled: enables cheats (`/cheat`), loads dev widgets, shows "DEV MODE ACTIVE" badge
  - When disabled: shows "ACTIVATE DEV MODE" button with description
  - Sets `WG.VBDevMode` global for widget conditional loading
- **`game/LuaUI/Widgets/vb_hotkeys.lua`** - Hotkey table updated:
  - `t = repeat` (changed from `t = resurrect`)
  - `y = capture` removed from order keys
- **`game/LuaUI/Widgets/vb_debug.lua`** - Minor updates consistent with dev mode

### 3. **Build Panel & Hotkeys Revamp**
- **`game/LuaUI/Widgets/vb_buildpanel.lua`** - Hidden order types:
  - WAIT, TIMEWAIT, DEATHWAIT, SQUADWAIT, GATHERWAIT, LOAD_UNITS orders hidden by default
  - `HiddenOrder(c)` function checks if order name contains "wait" or is "load units"
  - Build panel cleaner: only active orders shown
- **`game/LuaUI/Widgets/vb_hotkeys.lua`** - Key table updated:
  - `t = repeat` (was: `t = resurrect`)
  - `y = capture` removed entirely
- **`game/LuaUI/Headers/vb_uiscale.h.lua`** now used by both build panel and dashboard for dynamic text scaling based on viewport height

### 3. **GUI Minimap Widget Removed**
- **`game/LuaUI/Widgets/gui_minimap_start_double.lua`** - deleted:
  - "Minimap Start Double" widget that doubled minimap size at game start
  - Functionality superseded by other settings or player preference

### 4. **Sound Changes**
- **`game/LuaUI/Widgets/vb_sounds.lua`** - Low resource sounds:
  - `energy_low` now plays `energy_low` WAV (was custom sequence)
  - `metal_low` now plays `metal_low` WAV (was custom sequence)
  - Simplified stall/full announcement logic

### 5. **Configuration & Cleanup**
- **`game/modinfo.lua`** - version bumped to "0.25"
- **`game/modoptions.lua`** - no new options, but `vb_dev` usage expanded
- **`game/ga.zip`** - deleted (was empty/placeholder, 0 bytes in 0.24)
- **`game/LuaUI/Widgets/vb_hello.lua`** - deleted (redundant/duplicate)
- **`game/vb_build.txt`** - build stamp updated
- **`tools/test_crater_census.lua`** - 15 line addition for census testing
- **`tools/test_t3_units.py`** - 2 line addition for T3 unit testing

### 5. **New Utility Files** (untracked, not yet committed)
- `game/LuaRules/Gadgets/vb_buildfx.lua` - Build effects gadget
- `game/LuaUI/Widgets/vb_build_eta.lua` - BuildETA widget showing estimated build time
- `game/LuaUI/Widgets/vb_dev_queue.lua` - Developer queue widget
- `learner_data/best_genome.json` - Best genome from learning AI
- `learner_data/best_modoptions.txt` - Mod options for best learner genome
- `learner_data/state.json` - Learner AI state snapshot
- `screenshots/` WebP versions of all 4 screenshots (from 0.23)

## 🛠 How to Try the New Features

### Craters with Debug Output
```lua
-- The crater gadget now logs every operation to the infolog
-- No config change needed; DEBUG=true by default in the gadget
-- Check infolog.txt for: "digging: radius X depth Y rim Z", "rejected: blast Z is below MIN_BLAST", etc.

-- Test with cheats:
/cheat
/vbcrater 500     -- dig a crater with 500 blast power
```

### Developer Mode
```lua
-- Enable via mod option:
vb_dev = "1"

-- Or press the new "ACTIVATE DEV MODE" button in the dashboard settings panel (Settings tab)
-- This enables /cheat, loads dev widgets (console, debug), and shows "DEV MODE ACTIVE"

-- Available dev widgets:
-- /vbconsole - Voidborn console
-- /vbdebug - Memory graph widget
```

### Hotkeys
- `t` = repeat (was: resurrect)
- `y` = capture removed
- All other hotkeys unchanged

### Low Resource Sounds
- `/vbsound vol 100` then listen for energy_low/metal_low WAV files
- Simpler announcement logic (direct WAV playback vs. custom sequence)

## 📁 Files Changed

### Gadgets
- `game/LuaRules/Gadgets/vb_crater.lua` - 30 insertions: debug output, weapon watching, `/vbcrater` command

### UI Widgets
- `game/LuaUI/Widgets/dev_console.lua` - 4 lines: conditional loading
- `game/LuaUI/Widgets/vb_dashboard.lua` - 46 lines: DEV MODE button, pitch calc, DEV MODE ACTIVE badge
- `game/LuaUI/Widgets/vb_hotkeys.lua` - 2 lines: hotkey table update
- `game/LuaUI/Widgets/vb_memgraph.lua` - 4 lines: conditional loading
- `game/LuaUI/Widgets/vb_sounds.lua` - 2 lines: simplified low resource sounds
- `game/LuaUI/Widgets/gui_minimap_start_double.lua` - deleted
- `game/LuaUI/Widgets/vb_hello.lua` - deleted

### Configuration
- `game/modinfo.lua` - version "0.25"
- `game/modoptions.lua` - no new options, `vb_dev` usage expanded
- `game/vb_build.txt` - updated stamp

### Sounds
- `game/LuaUI/Widgets/vb_sounds.lua` - 2 lines: `energy_low`/`metal_low` now play WAV files

### Deleted
- `game/LuaUI/Widgets/gui_minimap_start_double.lua` - removed
- `game/LuaUI/Widgets/vb_hello.lua` - removed

### New Utility Files (untracked)
- `game/LuaRules/Gadgets/vb_buildfx.lua` - Build effects gadget
- `game/LuaUI/Widgets/vb_build_eta.lua` - BuildETA widget
- `game/LuaUI/Widgets/vb_dev_queue.lua` - Dev queue widget
- `learner_data/` - AI learning state files
- `screenshots/` WebP conversions (from 0.23)

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 361 compiled |
| **Gadget changes** | vb_crater.lua (30 lines added) |
| **UI widget changes** | 6 widgets modified/deleted |
| **New utility files** | 4 files + 3 learner_data + 4 WebP screenshots |
| **Sound changes** | 2 lines simplified |
| **Deleted files** | 2 widgets removed |
| **Hotkey updates** | 2 changes (t=y repeat, y=capture removed) |

## 🛠 Building

```bash
python3 build_sdz.py --no-engine-check --no-install --no-tests
# Produces dist/voidborn.sdz with updated stamp
```

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*