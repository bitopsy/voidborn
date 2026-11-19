-- Voidborn LUS script: mi_nostril2
local base = piece 'base'
local crown = piece 'crown'
local pad = piece 'pad'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
	Spin(crown, y_axis, math.rad(24))
end
local INBUILDSTANCE = (COB and COB.INBUILDSTANCE) or 5
function script.StartBuilding(heading, pitch) SetUnitValue(INBUILDSTANCE, 1) end
function script.StopBuilding() SetUnitValue(INBUILDSTANCE, 0) end
function script.Activate()
	SetUnitValue(COB.YARD_OPEN, 1) SetUnitValue(COB.BUGGER_OFF, 0) SetUnitValue(COB.INBUILDSTANCE, 1)
end
function script.Deactivate()
	SetUnitValue(COB.INBUILDSTANCE, 0) SetUnitValue(COB.YARD_OPEN, 0) SetUnitValue(COB.BUGGER_OFF, 1)
end
function script.QueryBuildInfo() return pad end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
