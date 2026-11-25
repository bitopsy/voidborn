### Voidborn 0.23 Release Notes

## 🎉 What's New in Version 0.23

### 1. **AI System Overhaul** (major)
Three new AI options added to `game/LuaAI.lua`, replacing the old EvoAI/llmAI entries:

| AI Name | Description | How to Switch |
|---------|-------------|--------------|
| **VoidBot** | Scripted bot: expands over metal spots, upgrades to tier 2, attacks in waves. `bot_skill` (1-3) controls tier 2 timing and attack group size. | Default; use `LuaAI=VoidBot` in start script |
| **Darwin** | Evolved Lua skirmish bot for Voidborn (VoidBot logic, evolab-tuned numbers). Constants differ: expands hard from start (9 mex at once), constructors 3x faster, raider-heavy army, heavies after ~10 min (4500+ metal stock), tier 2 late (11-14 min depending on skill), smaller attack groups. Switch with `LuaAI=Darwin` or the old `EvoAI` name is still accepted. | `LuaAI=Darwin` in start script, or `bot_skill` reads 1..3 like VoidBot |
| **Learner** | Voidborn skirmish bot that learns from every match. In-game adaptation: bad waves → attack later with bigger army; good waves → attack earlier; per-unit kill/loss efficiency shifts unit mix; energy stalls → more solar/ deeper queues; metal floating → deeper factory queues. At game over, prints ONE line per bot team with genome, result, economy/combat numbers, and lessons learned. Between matches, `learner.py` parses the line, turns it into a fitness, moves the genome, and logs to `games.csv`. Switch with `LuaAI=Learner` or mod option `lrn_teams = 1,3`. | `LuaAI=Learner` in start script, or `lrn_teams = 1,3` mod option |

**New mod options** (in `game/modoptions.lua`):
- `lrn_attack_interval` (default 1200)
- `lrn_attack_value` (default 2500)
- `lrn_con_rate` (default 1)
- `lrn_def_ratio` (default 0.15)
- `lrn_eco_priority` (default 0.5)
- `lrn_expand_interval` (default 600)
- `lrn_game_id` (default copied from save file name)
- `lrn_max_frames` (default 54000, ends match as draw at that frame)
- `lrn_retreat_hp` (default 0.25, units with HP below this retreat)
- `lrn_scout_rate` (default 0.2)
- `lrn_tech2_frame` (default 12000, frame when tech 2 becomes available)
- `lrn_tech3_frame` (default 30000, frame when tech 3 becomes available)
- `lrn_w_art`, `lrn_w_assault`, `lrn_w_heavy`, `lrn_w_raider`, `lrn_w_support` (weightings for unit mix, defaults: 0.25, 0.3, 0.5, 0.3, 0.1)

**Start script changes:**
- Several `Play_*.txt` and `Watch_*.txt` start scripts removed (see deleted files list)
- New start scripts may be added separately; old `llmAI` references updated

### 2. **Game Configuration & Mod Options**
- `game/modinfo.lua` - version bump to 0.23
- `game/modoptions.lua` - 11 new/modified mod options for the Learner AI and other tweaks

### 3. **Gameplay & Balance Tweaks**
- Sound re-generation: all `.wav` and `.ogg` files regenerated via `tools/gen_sounds.py` (deterministic, fixed random seed 1234). All 86 sound definitions preserved with updated gain/envelope values.
- Dashboard: total unit count added to mini title (` | N units`)
- Dashboard: "Production Queue Monitor" toggle added to settings row (Alt+Q or `/vbqueue` to show/hide)
- DEV console and other widgets updated with minor UI adjustments

### 4. **Build & Infrastructure**
- `dist/voidborn.sdz` rebuilt (26,953,169 bytes, stamp `24Nov-2317-13d725a3`)
- 752 files verified byte-for-byte against sources
- Archive verification passed: zip CRCs, content hashes, modinfo.lua at root

## 🛠 How to Try the New AIs

### Darwin (Evolved)
```lua
LuaAI=Darwin
```
or in start script:
```lua
LuaAI=EvoAI   -- still accepted, maps to Darwin
```

### Learner (Learning Bot)
```lua
LuaAI=Learner
```
or via mod options:
```lua
lrn_teams = 1,3     -- enable learning for teams 1 and 3
```

### Default (VoidBot)
No change needed — VoidBot remains the default skirmish AI.

## 📁 Files Changed

### AI System
- `game/LuaAI.lua` - Updated AI registry with VoidBot/Darwin/Learner
- `game/LuaRules/Gadgets/ai_darwin.lua` - New evolved AI constants file
- `game/LuaRules/Gadgets/ai_learner.lua` - New learning AI gadget
- `learner_data/L1125150704_00001.txt` - Learning session data snapshot

### Start Scripts (deleted, replaced)
- `Play_Choir_vs_Bot.txt`
- `Play_Choose_Faction_vs_Bot.txt`
- `Play_Haptic_vs_Bot.txt`
- `Play_Maw_vs_Bot.txt`
- `Play_Miasma_vs_Bot.txt`
- `Watch_4Factions_FFA.txt`
- `Watch_5Factions_FFA.txt`
- `Watch_Bot_vs_Bot.txt`
- `Watch_Default_vs_llmAI_Voidborn.txt`

### Configuration
- `game/modinfo.lua` - version "0.23"
- `game/modoptions.lua` - 10 new Learner mod options + 1 modified

### Sounds & Build
- All `game/sounds/*.wav` and `game/sounds/*.ogg` regenerated
- `tools/gen_sounds.py` - updated
- `dist/voidborn.sdz` - rebuilt, 752 files
- `game/vb_build.txt` - updated stamp

### UI
- `game/LuaUI/Widgets/dev_console.lua` - minor updates
- `game/LuaUI/Widgets/vb_dashboard.lua` - unit count + queue monitor toggle
- `game/LuaUI/Widgets/vb_debug.lua` - minor updates
- `game/LuaUI/Widgets/vb_hello.lua` - minor updates
- `game/LuaUI/Widgets/vb_memgraph.lua` - minor updates

### Deleted (cleanup)
- `RELEASE_NOTES.md` (replaced by `docs/release-0.23.md`)
- `install_and_build.py`

## 📊 Statistics

| Metric | Value |
|--------|-------|
| **Lua files** | 355+ compiled |
| **AI systems** | 4 (VoidBot, Darwin, Learner, plus legacy EvoAI) |
| **Mod options** | 10+ new/modified for Learner |
| **Archive size** | 752 files, 26.9 MB |
| **Learning data** | L1125150704_00001.txt snapshot included |

## 🛠 Building

```bash
python3 build_sdz.py --no-engine-check --no-install --no-tests
# Produces dist/voidborn.sdz with stamp 24Nov-23xx-xxxxxxx
```

---

*voidborn is a project of [goddot](https://github.com/bitopsy). Free and open source.*