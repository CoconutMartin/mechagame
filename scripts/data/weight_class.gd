class_name WeightClass
extends RefCounted
## Mech weight class from the build's total weight (user request 2026-10-13: the dodge roll is for
## light and medium mechs). Thresholds in tons: light up to LIGHT_MAX_T, medium up to MEDIUM_MAX_T,
## heavy above. Sanggigilid with the beam rifle is 58.5 t: medium.

enum Class { LIGHT, MEDIUM, HEAVY }

const NAMES: Array[String] = ["Light", "Medium", "Heavy"]
const LIGHT_MAX_T := 45.0
const MEDIUM_MAX_T := 70.0


static func of_weight(tons: float) -> Class:
	if tons <= LIGHT_MAX_T:
		return Class.LIGHT
	if tons <= MEDIUM_MAX_T:
		return Class.MEDIUM
	return Class.HEAVY


## The mech's class (its build stats; the mass when it has no stats).
static func of_mech(mech: Mech) -> Class:
	if mech.stats != null:
		return of_weight(mech.stats.total_weight_t)
	return of_weight(mech.mass_tons)
