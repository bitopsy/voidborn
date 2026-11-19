-- Voidborn LUS script: mi_amber
local base = piece 'base'
local rings = piece 'rings'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(rings, y_axis, math.rad(25))
end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
