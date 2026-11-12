-- Voidborn LUS script: ch_siphon
local base = piece 'base'
local spin = piece 'spin'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
end
function script.Activate() Spin(spin, y_axis, math.rad(200), math.rad(40)) end
function script.Deactivate() StopSpin(spin, y_axis, math.rad(30)) end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
