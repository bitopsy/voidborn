# voidborn 0.16

## 🎉 What's New

A release about the interface: the HUD panels stop floating around the screen and dock into **one column**, every panel the same width, at the edge you choose.

### The dock (`/vbdock`)

* New widget `game/LuaUI/Widgets/vb_dock.lua`. From the bottom up, the default column is: **tooltip → build menu → economy radar → army radar → unit census → minimap** (the engine's own minimap, placed by the dock).
* **Snap**: drag any panel by its title bar to another slot; the slot it will snap into is outlined, the others make room, it settles on release. The order is remembered. **RESET THE LAYOUT** in SETTINGS (or `/vbdock reset`) restores the default.
* **It always fits**: when the column is taller than the screen it shrinks (down to 75 %), then folds the top panels (census, army radar, economy radar). `/vbdock scale 0.6..1.6` sets the overall size, `/vbdock side left|right` the edge.
* The build menu's own scale handle is gone in the dock (the dock sets the size of the whole column); without the dock widget the build menu and the tooltip float as before.

### Self-contained panels

* New **economy radar** (`vb_hud_econ.lua`) and **army radar** (`vb_hud_army.lua`) panels, each with its own `-` (fold to the title bar) and `x` (switch off) button. They read the dashboard's statistics (`vb_dashboard.lua` must run); click a radar to open its page.
* The old "radar in the HUD: combat / economy" toggle is gone; the HUD keeps the leaderboard and three sparklines (army, metal income, damage).
* **Unit census** (`vb_unitstats.lua`) is now a docked panel for the **selected units**: totals, one page at a time — histogram of health / speed / range / damage/s / experience / size, unit types (TYPES) or the units closest to splitting (SPLIT) — picked with small tabs. Without a selection it shrinks to its title bar. `/vbstats` (or the SETTINGS switch) turns it on and off.
* **Tooltip** (`vb_tooltip.lua`) is on by default now, with a fixed height so nothing above it jumps. `/vbtooltip dock` sits it at the bottom of the dock column (default, same width as the build menu); `/vbtooltip pos br` and friends still float it in a corner instead.
* Dashboard **SETTINGS** page: a *HUD panels* group switches the three panels on or off (mirrors `/vbdock econ|army|census`) and carries **RESET THE LAYOUT**.

### Testing Notes

* The Lua files are syntax-checked and the archive is verified against the sources by the build, and the engine loads the build on a bot match (`spring-headless`).
* Mock renders: `python3 tools/render_hud.py OUTDIR` draws the docked column without the engine (needs `pip install lupa pillow`).
* If a panel refuses to snap or the column overflows on your resolution, `/vbdock scale <n>` and `/vbdock reset` are the first things to try.

### Files Modified

* `game/LuaUI/Widgets/vb_dock.lua` (new), `game/LuaUI/Widgets/vb_hud_econ.lua` (new), `game/LuaUI/Widgets/vb_hud_army.lua` (new)
* `game/LuaUI/Headers/vb_dockui.h.lua` (new), `game/LuaUI/Headers/vb_hud_radar.h.lua` (new)
* `game/LuaUI/Widgets/vb_buildpanel.lua`, `game/LuaUI/Widgets/vb_dashboard.lua`, `game/LuaUI/Widgets/vb_tooltip.lua`, `game/LuaUI/Widgets/vb_unitstats.lua`
* `tools/render_hud.py` (new)
* `docs/hud_dock.png` (screenshot of the docked column), `README.md` (*HUD layout* section)
* `game/modinfo.lua`, the three start scripts (version 0.16)
* Housekeeping: `vb_zzz_debug.lua` and `old/voidborn.jpg` (a debug gadget and a backup image that had slipped into the 0.15 archive) are removed from the game tree.
