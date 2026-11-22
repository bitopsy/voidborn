-- Voidborn LUS script: ha_pad
local base = piece 'base'
local petals = piece 'petals'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(petals, y_axis, math.rad(22))
end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
