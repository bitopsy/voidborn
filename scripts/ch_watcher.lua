-- Voidborn LUS script: ch_watcher
local base = piece 'base'
local head = piece 'head'
local dish = piece 'dish'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(dish, y_axis, math.rad(70))
end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
