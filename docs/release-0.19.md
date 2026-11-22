# voidborn 0.19 Release Notes

## 🎉 What's New in Version 0.19

### **Tier 3 Labs & Heavy Units** (Major New System)

#### 1. **Tier 3 Lab Upgrade**
- **Upgrade T3** button on Tier 2 labs (same pattern as T1→T2)
- **Cost**: 4500 metal + 7500 energy over 70 seconds
- **Stalls** when resources run out; pressing the button again cancels and refunds
- **Lab transforms** in-place into the faction's Tier 3 lab:
  - Same spot, same health fraction
  - Production queue moves with it
  - Keeps the unit forge unlocked
- **Five Tier 2 labs** can upgrade:
  - Choir: Great Iris Womb → Eternal Iris Womb
  - Maw: Great Brood Hive → Primeval Brood Hive
  - Tympan: Great Echo Chamber → Sanctum Echo Chamber
  - Miasma: Great Nostril → Ancient Nostril
  - Haptic: Great Palm → Titan Palm

#### 2. **Tier 3 Heavy Units** (One per faction)
- **Speed**: 0.44 - 0.48 (T2 heavies move at 0.8 - 0.85)
- **Metal cost**: 9200 - 9800
- **Health**: 88000 - 120000
- **Buildable** from T3 labs, adding new late-game strategic options

| Faction | Unit | Metal | HP | Speed | Weapons (range) |
|---------|------|-------|----|-------|-----------------|
| **Choir** | **Eidolon** | 9600 | 90000 | 0.46 | Final Sight (beam, 900), Optic Storm (lightning, 560), Judgement Lance (1400) |
| **Maw** | **Dreadmaw** | 9200 | 115000 | 0.44 | Gorge Beam (900), Arc Glands (lightning, 540), Brood Mortar (1300), Brood Swarm (rockets, 800) |
| **Tympan** | **Carillon** | 9700 | 88000 | 0.46 | Great Toll (beam, 900), Static Discharge (lightning, 540), Knell (1300) |
| **Miasma** | **Rafflesia** | 9200 | 120000 | 0.44 | Corpse Ray (beam, 900), Spore Arc (lightning, 540), Putrid Mortar (1300), Spore Storm (rockets, 800) |
| **Haptic** | **Atlas** | 9800 | 95000 | 0.46 | Grasping Beam (640), Nerve Storm (lightning, 380), Titan Fist (520) |

#### 3. **Weapon Updates** (Engine-content driven)
- **Leviathan's `lasercannon`** → Every heavy's **beam**: `BeamLaser`, 6s reload, 2.4s beam, thickness 9, range 900 (Haptic: 640)
- **Leviathan's `lightningcannon`** → Every heavy's **storm**: `LightningCannon`, burst of 8, range 380-560
- **Emperor's Scorpion `flakcannon`** → **Long-range gun**: 1300-1400 range shell/lance, 2400-3000 damage
- **Harbinger's rockets and plasma** → **Maw and Miasma rocket salvos** (burst of 6-8)

#### 4. **Faction Weapon Rules** (Voidborn-specific)
- **Resonance** (Tympan)
- **Poison** (Miasma)
- **Closeness** (Haptic, `vb_touch`)

#### 5. **Damage Scaling**
- Sustained damage per metal is within ~15% of T2 heavies
- Atlas is higher (before closeness bonus)
- Roughly twice the total damage, twice the health, and half the speed of T2 heavies
- Printed by `tools/test_t3_units.py`

## 📁 Files Changed/Added

- `game/modinfo.lua` — version "0.19"
- `game/modoptions.lua` — faction section label updated to "0.18 / 0.19"
- `game/LuaUI/Widgets/vb_buildpanel.lua` — T3 labels and magenta lab chip
- `game/LuaUI/Widgets/vb_upgrade_bars.lua` — upgrade bar enhancements
- `game/LuaUI/Widgets/vb_sounds.lua` — T3 upgrade sounds
- `game/LuaRules/Gadgets/vb_factory_upgrade.lua` — reads `customParams.upgrade_tier`, team rule `vb_t3`
- `tools/designs_t3.py` — ten Tier 3 model designs
- `tools/gen_assets_t3.py` — asset generation scripts
- `tools/gen_t3.py` — unit definitions and scripts
- `tools/regen_017.py` — regeneration helper
- `tools/test_t3.py` — gadget test against mock engine
- `tools/test_t3_units.py` — rosters, links, weapons, assets tests
- `weapons/vb_weapons_018.lua` — weapon definitions
- `game/LuaRules/Gadgets/llmAI.lua` — Evolab AI (Evolab-evolved skirmish AI)
- `game/LuaRules/Gadgets/evolved_ai_735c0710.lua` — AI helpers

## 📥 Download

- **Game archive**: `voidborn.sdz` (built by `build_sdz.py`)
- **Map archive**: `voidborn_rift.sd7` (built by `tools/package.sh`)

## 🐛 Known Limits (First Pass)

- **Not engine-tested in-game**: Tier 3 beam textures (`texture1 = "lightning"`) come from the engine's content system
- **Bot does not use Tier 3**: AI upgrades to T2 only; `heavy3` / `fac3` not in its tables
- **Balance is a first pass**: Beam damage follows commanders' Gaze beam convention; may need retuning
- **Models are enlarged T2 models** with an ornament ring, judged from software renders

---

*Voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*