-- Voidborn LUS script: mi_rafflesia
local base = piece 'base'
local petals = piece 'petals'
local head = piece 'head'
local muzzle = piece 'muzzle'
local rings = piece 'rings'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(petals, y_axis, math.rad(22))
	Spin(rings, y_axis, math.rad(25))
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
function script.AimWeapon2(heading, pitch)
	Signal(SIG_AIM[2]) SetSignalMask(SIG_AIM[2])
	Turn(head, y_axis, heading, math.rad(420))
	Turn(head, x_axis, -pitch, math.rad(300))
	WaitForTurn(head, y_axis) WaitForTurn(head, x_axis)
	return true
end
function script.AimFromWeapon2() return head end
function script.QueryWeapon2() return muzzle end
function script.FireWeapon2() end
function script.AimWeapon3(heading, pitch)
	Signal(SIG_AIM[3]) SetSignalMask(SIG_AIM[3])
	Turn(head, y_axis, heading, math.rad(420))
	Turn(head, x_axis, -pitch, math.rad(300))
	WaitForTurn(head, y_axis) WaitForTurn(head, x_axis)
	return true
end
function script.AimFromWeapon3() return head end
function script.QueryWeapon3() return muzzle end
function script.FireWeapon3() end
function script.AimWeapon4(heading, pitch)
	Signal(SIG_AIM[4]) SetSignalMask(SIG_AIM[4])
	Turn(head, y_axis, heading, math.rad(420))
	Turn(head, x_axis, -pitch, math.rad(300))
	WaitForTurn(head, y_axis) WaitForTurn(head, x_axis)
	return true
end
function script.AimFromWeapon4() return head end
function script.QueryWeapon4() return muzzle end
function script.FireWeapon4() end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
