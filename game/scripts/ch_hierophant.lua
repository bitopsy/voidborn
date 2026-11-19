-- Voidborn LUS script: ch_hierophant  (DEBUG build: extra Spring.Echo lines marked DBG)
local base = piece 'base'
local halo = piece 'halo'
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
function script.AimFromWeapon1()  return head end   -- DBG
function script.QueryWeapon1()  return muzzle end      -- DBG
function script.FireWeapon1()  end                                            -- DBG

function script.AimWeapon2(heading, pitch) return false end   -- manual gun: only the D / Q command fires it (vb_manualfire.lua)
function script.AimFromWeapon2() return head end
function script.QueryWeapon2() return muzzle end
function script.FireWeapon2() end
function script.AimWeapon3(heading, pitch) return false end   -- manual gun: only the D / Q command fires it (vb_manualfire.lua)
function script.AimFromWeapon3() return head end
function script.QueryWeapon3() return muzzle end
function script.FireWeapon3() end

local INBUILDSTANCE = (COB and COB.INBUILDSTANCE) or 5
function script.StartBuilding(heading, pitch) SetUnitValue(INBUILDSTANCE, 1) end
function script.StopBuilding() SetUnitValue(INBUILDSTANCE, 0) end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
