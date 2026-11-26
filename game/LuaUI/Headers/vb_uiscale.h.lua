-- Voidborn UI text boost, shared by the build panel and the dashboard.
-- Pixel sizes of the UI are tuned for 4K.  On HD screens everything looks small, so the text is drawn larger there:
--   1080p and below: 116 %,  easing down to 100 % at 2000 px of height and above.
-- The player can override it with /vbtext <percent> (and /vbtext auto): the dashboard stores that in
-- WG.VBTextBoostOverride and passes it in here.
--   local UI = VFS.Include("LuaUI/Headers/vb_uiscale.h.lua")
--   local boost = UI.TextBoost(vsy, WG.VBTextBoostOverride)
local M = {}
local HD_BOOST, HD_MAX_H, FULL_H = 1.16, 1200, 2000

function M.TextBoost(vsy, override)
	if type(override) == "number" and override > 0 then return math.max(0.8, math.min(1.6, override)) end
	vsy = vsy or 1080
	if vsy <= HD_MAX_H then return HD_BOOST end
	if vsy >= FULL_H then return 1 end
	return HD_BOOST - (HD_BOOST - 1) * (vsy - HD_MAX_H) / (FULL_H - HD_MAX_H)
end

-- true when the boost is big enough that the mini dashboard should show only what matters
function M.Compact(boost) return boost > 1.02 end

return M
