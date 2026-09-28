class_name MechStatApplier
extends RefCounted
## Sets computed MechStats on the mech and its parts (movement, energy, jump, recoil).


static func apply(stats: MechStats, mech: Mech) -> void:
	mech.stats = stats
	mech.mass_tons = stats.total_weight_t
	mech.walk_speed = stats.walk_speed
	mech.boost_speed_multiplier = stats.boost_speed_multiplier
	mech.boost_acceleration = stats.boost_acceleration
	mech.boost_energy_per_second = stats.boost_energy_per_second
	mech.turn_speed_deg = stats.torso_turn_speed_deg
	mech.leg_turn_speed_deg = stats.leg_turn_speed_deg
	mech.leg_turn_speed_standing_deg = stats.leg_turn_speed_standing_deg
	mech.energy.capacity = stats.energy_capacity
	mech.energy.recharge_rate = stats.energy_output
	mech.energy.recharge_delay = stats.recharge_delay
	mech.jump_charge.full_height = stats.jump_height
	var rig := mech.get_node_or_null("CameraRig") as MechCameraRig
	if rig != null and rig.free_aim != null:
		rig.free_aim.recoil_multiplier = stats.recoil_multiplier
