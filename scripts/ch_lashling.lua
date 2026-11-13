-- Voidborn LUS script: ch_lashling
local base = piece 'base'
local head = piece 'head'
local muzzle = piece 'muzzle'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
end
function script.AimWeapon1(heading, pitch)
	Signal(SIG_AIM[1]) SetSignalMask(SIG_AIM[1])
	Turn(head, y_axis, heading, math.rad(420))
	Turn(head, x_axis, -pitch, math.rad(300))
	WaitForTurn(head, y_axis) WaitForTurn(head, x_axis)
	return true
end
function script.AimFromWeapon1() return head end
function script.QueryWeapon1() return muzzle end
function script.FireWeapon1() end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
