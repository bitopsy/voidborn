-- Voidborn LUS script: ha_kneader
local base = piece 'base'
local nano = piece 'nano'
local SIG_AIM = {2, 4, 8, 16}
function script.Create()
end
local INBUILDSTANCE = (COB and COB.INBUILDSTANCE) or 5
function script.StartBuilding(heading, pitch) SetUnitValue(INBUILDSTANCE, 1) end
function script.StopBuilding() SetUnitValue(INBUILDSTANCE, 0) end
function script.QueryNanoPiece() return nano end
function script.StartMoving() end
function script.StopMoving() end
function script.Killed(recentDamage, maxHealth) return 1 end
