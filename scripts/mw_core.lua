-- Voidborn LUS script: mw_core
local base = piece 'base'
local ribs = piece 'ribs'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(ribs, y_axis, math.rad(12))
end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
