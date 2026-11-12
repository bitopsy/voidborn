return {
	movement = { allowAirPlanesToLeaveMap = false, allowPushingEnemyUnits = false, allowUnitCollisionDamage = false },
	construction = { constructionDecay = true, constructionDecayTime = 6.667, constructionDecaySpeed = 0.03 },
	reclaim = { multiReclaim = 1, reclaimMethod = 1, unitMethod = 1, unitEnergyCostFactor = 0, unitEfficiency = 1, featureEnergyCostFactor = 0, allowEnergyCost = true },
	repair = { energyCostFactor = 0.0 },
	resurrect = { energyCostFactor = 0.5 },
	capture = { energyCostFactor = 0.0 },
	paralyze = { paralyzeOnMaxHealth = true },
	sensors = { los = { losMipLevel = 2, losMul = 1, airMipLevel = 4, airMul = 1 }, requireSonarUnderWater = true },
	fireAtDead = { fireAtKilled = false, fireAtCrashing = true },
}
