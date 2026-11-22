# voidborn 0.18

## 🎉 Version Bump

* **Version**: 0.18 (updated from 0.17 in `game/modinfo.lua`)
* **Build**: `dist/voidborn.sdz` built and verified (stamp: `22Nov-1317-3198172c`)
* **Archive**: 681 files, sha256 `9089c1a47742c40e...`

## 🐛 Bug Fixes

* **Font fallback**: Font system now prioritizes Georgia.ttf, falls back to Gelasio.ttf (metric-compatible), then engine font. Old `VoidbornGlyph.ttf` ships in archive but is no longer the default.
* **Mono stats text**: Stats dashboard no longer uses separate `VoidbornMono.ttf`; all numbers use the same Georgia face for consistency.
* **vb_resbar.lua removed**: Resource bar widget deleted (functionality merged into dashboard).
* **vb_hello.lua deleted**: Greeting widget removed.
* **vb_dev_queue.lua**: Factory upgrade gate now properly blocks T2 forge until factory is upgraded.
* **vb_explode.lua**: 5-second countdown detonation gadget fixed for selected units.
* **vb_manualfire.lua**: Manual fire gadget logic corrected.
* **game_spawn.lua**: Spawn logic updated for five-faction support.
* **auto_mex_recognize.lua**: Metal extractor recognition fixed for new cell snapping constraints.

## 🖥 Layout & Interface

* **Dashboard (vb_dashboard.lua)**:
  - New **GRAPHICS panel** with screen resolution and graphics quality dropdown (OFF/LOW/MED/HIGH/MAX).
  - Tab order changed: `OVERVIEW` → `GRAPHS` → `ECONOMY` → `COMBAT` → `ARMY` → `REPORT` → `SETTINGS` → `KEYS` → `ABOUT` (share tab added before settings).
  - **Share panel**: send metal/energy to ally or transfer selected units.
  - Resign option added to dashboard menu.
  - SETTINGS tab now includes graphics quality preset (saves/loads `WG.FPSOps` preset 0-99).
  - Window layer changed from 8 → 5.

* **Build Panel (vb_buildpanel.lua)**:
  - **Categorized build menu** with four labelled sections:
    - **ECONOMY** (mex, energy, storage, heart) — gold label
    - **COMBAT** (fighting units, defences) — red label
    - **UTILITY** (radar, support units) — blue label
    - **BUILD** (labs and constructors) — green label
  - Every tile belongs to one category shown as coloured tabs all at once.
  - **Lab selection**: panel always shows the selected lab, or the one picked with its chip, or the first. Tier 1 and Tier 2 labs are never mixed.
  - **Constructor detection**: `IsLab()` function detects factories including T2 versions (Hive, Palm, Womb, Nostril, Echo and their T2 forms).
  - **Design lab**: identifies the active T2 lab for forge designs, or the first T2 lab available.

* **Faction Menu (vb_faction_menu.lua)**:
  - **Five factions** now: Choir, Maw, Tympan, Miasma, **Haptic**.
  - Five cards in the menu (was four).
  - Keybindings extended: number keys **1-5** (was 1-4), `/vbfaction haptic` command.
  - Layout recalculated for dynamic width based on faction count (`n = #SIDES`).
  - Resolution adaptive: gap and card width scale with `vsy / 1080`.

* **Tooltip (vb_tooltip.lua)**:
  - Enabled by default (was disabled).
  - **Fixed plate height**: `SLOT_LINES = 7` lines high when `vb_layout.lua` owns the placement.
  - Slot system: tooltip plate has fixed position, width and height set by layout; nothing above moves when text changes.
  - Layout integration: `WG.VBTooltip.Place()`, `Release()`, `Height()` functions for use by `vb_layout.lua`.

* **FPS Ops (gui_fps_ops.lua)**:
  - **Graphics quality presets**: OFF(0), LOW(1), MED(2), HIGH(3), MAX(99).
  - `WG.FPSOps.SetPreset(p)` and `WG.FPSOps.GetPreset()` API exposed for other widgets.
  - Preset saved in widget config and restored on load.
  - Panel snap integration: widget can dock to screen edges via `PanelLayout`.

* **Statistics Data (vb_stats_draw.h.lua)**:
  - **Overlays layer**: dropdown lists and tooltip systems now have dedicated `D.overlays` table drawn after everything else.
  - Dropdown system: `D.Dropdown(x1, y1, x2, y2, spec)` widget with options, selected state, onSelect callback.
  - All stats text uses Georgia face (mono removed, falls back to Georgia).
  - Resolution `1280x720` default canvas updated to reflect new layout structure.

## ♻️ Graphics & Performance

* **Graphics quality** (new dashboard GRAPHICS panel):
  - Preset 0: OFF — all optional effects disabled
  - Preset 1: LOW — lightest effects
  - Preset 2: MED — medium effects (default)
  - Preset 3: HIGH — heavy effects
  - Preset 99: MAX — all effects enabled
  - Controlled via `WG.FPSOps.SetPreset(p)` API.
  - Preset saved per-session and restored on game start.

* **FPS-OPS widget** (`gui_fps_ops.lua`):
  - Was disabled (`enabled = true` → `enabled = false`) — its knobs are now exposed via `WG.FPSOps` API for the dashboard to use.
  - Panel snap support added for docking to screen edges.
  - Config persistence: `preset` and `levels` saved/loaded.

## 🔤 Font: Georgia

* **Default font** changed from `VoidbornGlyph.ttf` to **Georgia**.
* Archive ships `fonts/Gelasio.ttf` (SIL OFL, metric-compatible with Georgia) as fallback.
* Font resolution order:
  1. `fonts/Georgia.ttf` — if present in `game/fonts/` (your own copy takes priority)
  2. `fonts/georgia.ttf` — bundled fallback
  3. `fonts/Gelasio.ttf` — metric-compatible fallback
  4. Engine default font — if nothing loads, UI never breaks
* All UI text, stats, dashboard, build panel, tooltip use Georgia.
* Stats numbers no longer use a separate `VoidbornMono.ttf`; they use the same Georgia face.

## 📐 Resolution & Menu Adaptation

* **Dynamic faction menu**: width calculated from `vsy / 1080` scale and faction count `n`.
  - Gap between cards: `gap * (n + 1)` (was fixed for 4 factions).
  - Card width: `(vsx * 0.94 - gap * (n + 1)) / n` (scales with screen width).
  - Works for 4 or 5 factions automatically.
* **Build panel categories** adapt to available space with labelled sections.
* **Dashboard layout** stacks HUD again in default column; resolution quality preset affects FPS.

## 📦 Separate Label Orders

* **Build panel categories** have independent labelled sections (Economy/Combat/Utility/Build), each with their own colour and logic — no longer a single monolithic list.
* **Faction menu** labels order adapts: `1 - 5` keypresses now work (was `1 - 4`).
* **Dashboard tabs** have new order with SHARE inserted before SETTINGS.

## 👷 Idle Constructors Detection

* **Build panel** now detectsconstructor labs via `IsLab()` function:
  - Returns `true` for factory units (`ud.isFactory`)
  - Returns `true` for units with `customParams.kind == "fac"` or `"fac2"` (T2 factories)
  - Returns `true` for any unit with `buildOptions` and no movement (non-factory labs)
* **Labs collection**: `labs = { uid, def, tier, n }` stored in unit ID order.
* **Active lab** logic: selected lab → lab picked with chip → first lab in list.
* **Design lab** helper: identifies the active T2 lab for forge, or the first T2 lab available.
* **Category assignment**: `KIND_CAT` maps unit kinds to ECONOMY/COMBAT/UTILITY/BUILD categories:
  - `fac`, `fac2` → **BUILD** (constructors/labs)
  - `con`, `com` → **BUILD** (commanders and construction units)
  - `mex`, `solar`, `heart`, `store` → **ECONOMY**
  - `art`, `art2`, `heavy`, `heavy2`, `assault`, `raider`, `scout`, `combat`, `def1`, `def2` → **COMBAT**
  - `radar`, `support`, `support2` → **UTILITY**

## 🎯 Units / Constructor Selection Difference

* **Build panel selects labs, not generic factories**:
  - `SelectedFactory()` now uses `IsLab()` check — only lab-eligible units shown.
  - `FactoryDef()` similarly filtered.
  - This means the build panel always shows the *selected lab*'s production queue, never a random factory.
* **Chip-based lab picking**: if no lab is selected, the panel remembers the lab picked with its chip (saved between sessions).
* **T1/T2 separation**: tier 1 and tier 2 labs are never mixed in the same panel view.
* **Constructor visibility**: units with `customParams.kind == "con"` or similar constructor markers appear in the **BUILD** category, not mixed with combat or economy.

## 🛠 Other Changes

* **Tools**: `tools/gen_font.py` generates Gelasio font table; `tools/regen_017.py` updated for new font and layout.
* **vb_font.h.lua**: Full rewrite for Georgia/Gelasio font system with `FONT_CHOICES` array and `PickFile()`.
* **vb_stats_draw.h.lua**: Overlay system for dropdowns; mono font removed.
* **vb_resbar.lua**: Deleted (merged into dashboard).
* **vb_hello.lua**: Deleted (greeting removed).
* **vb_dev_queue.lua**: Upgrade gate logic enforced.
* **vb_explode.lua**: Detonation countdown fixed.
* **vb_manualfire.lua**: Fire logic corrected.
* **game_modoptions.lua**: New game options for graphics quality and font selection.
* **vb_build.txt**: Build stamp format updated.
* **14 smoke tests** all pass (same as 0.17).
* **322 Lua files** compile cleanly.

## 🚀 Installation

The archive is already installed at `~/.spring/games/voidborn.sdz`.  
Start the Spring engine with `voidborn_rift.sd7` map to play.

## 🔗 Links

* GitHub: [bitopsy/voidborn](https://github.com/bitopsy/voidborn)
* Website: [voidborn.com](https://voidborn.com)