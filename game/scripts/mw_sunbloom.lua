-- Voidborn LUS script: mw_sunbloom
local base = piece 'base'
local fronds = piece 'fronds'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(fronds, y_axis, math.rad(6))
end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
