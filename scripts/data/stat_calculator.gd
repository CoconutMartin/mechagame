class_name StatCalculator
extends RefCounted
## Computes final mech stats from a Loadout: parts, weapons, plates and mods.
## Phase 6 adds pilot skills here.


## Weight formula (the only place it lives, so it is easy to tune).
## Returns the speed factor: walk speed = legs base speed x this value.
## load_ratio <= 1: 1 - 0.3 x load_ratio (a full load is 30% slower).
## load_ratio >  1: 0.7 / load_ratio² (overloaded mechs slow down fast).
static func weight_factor(load_ratio: float) -> float:
	if load_ratio <= 1.0:
		return 1.0 - 0.3 * load_ratio
	return 0.7 / (load_ratio * load_ratio)


static func compute(loadout: Loadout) -> MechStats:
	var stats := MechStats.new()
	var mods := _mod_totals(loadout.mods)

	# Weight: parts, weapons and plates.
	var weight := 0.0
	for part in loadout.get_parts():
		weight += part.weight_t
	for plate in loadout.plates:
		weight += plate.weight_t
	stats.total_weight_t = weight * _mod(mods, ModData.Stat.WEIGHT)

	var legs := loadout.legs
	stats.load_capacity_t = legs.load_capacity_t if legs != null else 1.0
	stats.load_ratio = stats.total_weight_t / maxf(stats.load_capacity_t, 0.1)
	stats.weight_factor = weight_factor(stats.load_ratio)

	# Speed, boost and turning drop with weight.
	var base_speed := legs.base_speed if legs != null else 0.0
	stats.walk_speed = base_speed * stats.weight_factor * _mod(mods, ModData.Stat.SPEED)
	var booster := loadout.booster
	if booster != null:
		stats.boost_speed_multiplier = booster.boost_speed_multiplier
		stats.boost_acceleration = booster.thrust * _mod(mods, ModData.Stat.BOOST_THRUST) / maxf(stats.total_weight_t, 1.0)
		stats.boost_energy_per_second = booster.energy_per_second
	var turn := _mod(mods, ModData.Stat.TURN_SPEED) * stats.weight_factor
	if loadout.core != null:
		stats.torso_turn_speed_deg = loadout.core.torso_turn_speed_deg * turn
	if legs != null:
		stats.leg_turn_speed_deg = legs.turn_speed_deg * turn
		stats.leg_turn_speed_standing_deg = legs.turn_speed_standing_deg * turn
		stats.jump_height = legs.jump_height * _mod(mods, ModData.Stat.JUMP_HEIGHT)

	# Energy.
	if loadout.core != null:
		stats.energy_capacity = loadout.core.energy_capacity * _mod(mods, ModData.Stat.ENERGY_CAPACITY)
	if loadout.generator != null:
		stats.energy_output = loadout.generator.energy_output * _mod(mods, ModData.Stat.ENERGY_OUTPUT)
		stats.recharge_delay = loadout.generator.recharge_delay

	# Recoil: the arm with the weapon (right) steadies it.
	var arm_recoil := loadout.arm_right.recoil_control if loadout.arm_right != null else 1.0
	stats.recoil_multiplier = arm_recoil * _mod(mods, ModData.Stat.RECOIL)

	# Part HP with plates.
	var hp_mod := _mod(mods, ModData.Stat.PART_HP)
	var slots := {
		PlateData.Slot.HEAD: ["Head", loadout.head],
		PlateData.Slot.CORE: ["Core", loadout.core],
		PlateData.Slot.ARM_LEFT: ["Arm L", loadout.arm_left],
		PlateData.Slot.ARM_RIGHT: ["Arm R", loadout.arm_right],
		PlateData.Slot.LEGS: ["Legs", loadout.legs],
	}
	for slot in slots:
		var part: PartData = slots[slot][1]
		if part == null:
			continue
		var hp := part.hp
		for plate in loadout.plates:
			if plate.slot == slot:
				hp += plate.hp
		stats.part_hp[slots[slot][0]] = hp * hp_mod
	return stats


## Sum of mod percents for each stat.
static func _mod_totals(mods: Array[ModData]) -> Dictionary:
	var totals := {}
	for mod in mods:
		totals[mod.stat] = totals.get(mod.stat, 0.0) + mod.percent
	return totals


## Multiplier for one stat from the mod totals (+10% = 1.1).
static func _mod(totals: Dictionary, stat: ModData.Stat) -> float:
	return 1.0 + totals.get(stat, 0.0) / 100.0
