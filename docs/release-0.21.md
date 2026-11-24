### Voidborn 0.21 Release Notes

## 🎉 What's New in Version 0.21

### 1. **Arc & Wave Gadgets**
- New `vb_arc.lua` gadget: arc weapons with custom effect systems for all five factions
- New `vb_wave.lua` gadget: wave-based weapon effects with shockwaves and visual distortion
- Arc and wave projectiles have distinct visual patterns and impact effects

### 2. **Expanded Sound Library**
- New sound effects: `arc_heavy.wav`, `arc_zap.wav`, `beam_thin.wav`, `beam_thin_light.wav`
- `sonar_deep.wav`, `sonar_ping.wav` for underwater/awareness cues
- `warble_heavy.wav`, `warble_light.wav` for modulated audio effects
- Updated existing sounds with higher fidelity rerecordings

### 3. **Tooling Improvements**
- `tools/gen_beams.py` - beam effect generator with improved presets
- `tools/gen_specials.py` - special weapon effect generator
- `tools/test_beams.py` - beam effect test suite
- `tools/test_specials.py` - special effect validation tests
- `tools/gen_defs.py` - updated definition generator with new parameters

### 4. **Growth Parameter Balance Changes**
- `split_xp` default changed from 0.14 to **0.25** (units split at higher experience)
- `max_growth` default changed from 1.0 to **2.0** (units grow larger before splitting)
- These changes affect how units progress through their lifecycle and when they divide

### 5. **New Unit Designs**
- `game/LuaRules/Gadgets/vb_arc.lua` - arc weapon gadget
- `game/LuaRules/Gadgets/vb_wave.lua` - wave weapon gadget
- Additional unit variants and design updates across all factions

## 📁 Files Changed

### Gadgets
- `game/LuaRules/Gadgets/vb_arc.lua` - arc weapon system
- `game/LuaRules/Gadgets/vb_wave.lua` - wave weapon system
- `game/LuaRules/Gadgets/vb_dev_queue.lua` - updated rally/repeat logic
- `game/LuaRules/Gadgets/vb_dev_units.lua` - unit design updates
- `game/LuaRules/Gadgets/vb_factory_upgrade.lua` - factory upgrade gate

### Widgets
- `game/LuaUI/Widgets/vb_sounds.lua` - expanded sound list

### Unit Definitions
- Various unit weapons and effects updated across all factions

### Tools
- `tools/gen_beams.py` - beam effect generator
- `tools/gen_specials.py` - special effects generator
- `tools/gen_defs.py` - definition generator updates

### Sounds
- `game/sounds/arc_heavy.wav` - new arc heavy impact
- `game/sounds/arc_zap.wav` - new arc zap sound
- `game/sounds/beam_thin.wav` - new thin beam sound
- `game/sounds/beam_thin_light.wav` - new thin beam light sound

### Effects
- `game/effects/vb_effects_019.lua` - expanded effect definitions

## 🔧 Build

- Game archive rebuilt (`dist/voidborn.sdz`, 752 files, 26.9 MB)
- Version updated to 0.21 in `game/modinfo.lua`
- All 19 test suites pass

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 355+ compiled |
| **Test suites** | 19 passed |
| **Archive size** | 752 files, 26.9 MB |
| **New sound files** | 10+ new/updated WAV files |
| **New tools** | 3 new generator/test tools |
| **Graphics effects** | Arc & wave systems |

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*