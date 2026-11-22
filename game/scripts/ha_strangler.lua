-- Voidborn LUS script: ha_strangler
local base = piece 'base'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
end
function script.AimWeapon1(heading, pitch) return true end
function script.AimFromWeapon1() return base end
function script.QueryWeapon1() return base end
function script.FireWeapon1() end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
