### Voidborn 0.22 Release Notes

## 🎉 What's New in Version 0.22

### 1. **HUD Overhaul**
- **New player-list columns** added to the dashboard HUD: SCORE, ARMY, M/S (metal/energy per second), E/S (energy per second), UNITS, PING, and FPS
- **Right-aligned column layout** with per-column width control; columns render from the right edge of the HUD
- **Flag rendering** for player country codes (two-letter IDs), with fallback to monochrome text when no flag image exists
- **FPS monitoring** across all clients: each client broadcasts its FPS via `SendLuaUIMsg`, received by other clients and displayed
- **PING display** with visual color coding (good/warn/bad thresholds) and average/fps text
- **Unit count display** showing exact counts for allies/spectators, estimated samples for enemies, with max-unit limits
- **AI team indicator** showing "AI" text for bot teams

### 2. **Version Bump**
- `game/modinfo.lua`: version updated from "0.21" to "0.22"
- Build stamp updated in `game/vb_build.txt`

### 3. **Manual Fire Gadget Fixes**
- **Null safety improvements** in `vb_manualfire.lua`: added defID guards for `UnitDefs` and `unitSlots` lookups
- **Fixed weapon def resolution**: improved `unitSlots[defID][slot]` access with null checks
- **Enhanced Fire() function**: added guards for `px` position, `wd` weapon def, and `v` projectile speed
- **Better error handling**: `v <= 0` defaults to 10 elmos/frame; `defID` nil checks throughout

### 4. **Build & Infrastructure**
- Game archive rebuilt (`dist/voidborn.sdz`, 752 files, 26.9 MB)
- Version updated to 0.22 in `game/modinfo.lua`
- All Lua files compile successfully (355 files)
- Build verification passed: zip CRCs, content hashes, modinfo.lua at archive root

## 📁 Files Changed

### Gadgets
- `game/LuaRules/Gadgets/vb_manualfire.lua` - null safety fixes, weapon def resolution improvements
- `game/LuaRules/Gadgets/vb_dashboard.lua` - HUD column overhaul, flag rendering, FPS/ping display

### Configuration
- `game/modinfo.lua` - version "0.22"

### Build Stamp
- `game/vb_build.txt` - updated timestamp and content hash

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 355 compiled |
| **Test suites** | (smoke tests skipped for release build) |
| **Archive size** | 752 files, 26.9 MB |
| **Build stamp** | 24Nov-2015-91a75ebd |
| **Version** | 0.22 |

## 🛠 Building

```bash
python3 build_sdz.py --no-engine-check --no-install --no-tests
# Produces dist/voidborn.sdz with stamp 24Nov-2015-91a75ebd
```

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*