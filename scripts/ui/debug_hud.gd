extends CanvasLayer
## Shows live movement values for testing, and the build stats from the loadout (Phase 2):
## total weight, load ratio, speeds and the HP of each part.

@export var mech: Mech
@export var mech_aim: MechAim

@onready var _info: Label = $Info
@onready var _energy_bar: ProgressBar = $EnergyBar
@onready var _build: Label = $Build
@onready var _weapons_label: Label = $Weapons


func _ready() -> void:
	set_mech(mech)


## Follows a mech (LoadoutSwitcher calls it after it builds a new one).
func set_mech(new_mech: Mech) -> void:
	mech = new_mech
	mech_aim = mech.get_node("MechAim") as MechAim
	var reticle := $AimReticle as AimReticle
	reticle.mech_aim = mech_aim
	reticle.weapons = mech.get_node_or_null("WeaponController") as WeaponController


func _process(_delta: float) -> void:
	var speed := mech.get_horizontal_speed()
	var state := "GROUND" if mech.is_on_floor() else "AIR"
	if mech.is_boosting:
		state += " + BOOST"
	state += "\nTorso twist: %d deg (limit %d left, %d right)" % [roundi(rad_to_deg(mech.get_torso_twist())), roundi(mech.torso_twist_left_deg), roundi(mech.torso_twist_right_deg)]
	var charge := mech.jump_charge
	if charge.is_charging:
		state += "\nJump charge: %d%% (%.1f m)" % [roundi(charge.charge * 100.0), charge.charge * charge.full_height]
	if mech.is_running:
		state += " + RUN"
	if mech.dodge.is_dodging:
		state += " + DODGE"
	if mech.is_skidding:
		state += " + SKID"
	elif mech.is_exiting_boost:
		state += " + BOOST EXIT"
	if mech.kneel.is_kneeling:
		state += " + KNEEL"
	var recovery := mech.landing_recovery
	if recovery.is_recovering():
		state += "\nLanding recovery: %.1f s" % recovery.time_left
	elif not mech.is_boost_ready():
		state += "\nBoost ready in %d steps (walk %d, run %d)" % [mech.get_walk_steps_left(), mech.boost_start_steps, mech.run_steps]
	var energy := mech.energy
	_info.text = "Speed: %.1f m/s (%d km/h)\nHeight: %.1f m\nWeight: %d t\nState: %s\nEnergy: %d / %d%s\nFPS: %d" % [
		speed, roundi(speed * 3.6), mech.global_position.y, roundi(mech.mass_tons), state,
		roundi(energy.current), roundi(energy.capacity),
		"  (EMPTY)" if energy.is_depleted else "",
		Engine.get_frames_per_second(),
	]
	_build.text = _build_text()
	_weapons_label.text = _weapons_text()
	_energy_bar.value = energy.get_fraction() * 100.0
	_energy_bar.modulate = Color(1.0, 0.35, 0.3) if energy.is_depleted else Color.WHITE


func _build_text() -> String:
	var stats := mech.stats
	if stats == null:
		return "Build: no loadout"
	var text := "BUILD\nWeight: %.1f / %.0f t   Load: %d%%\n" % [stats.total_weight_t, stats.load_capacity_t, roundi(stats.load_ratio * 100.0)]
	text += "Walk %.1f m/s   Boost %.1f m/s   Boost accel %.1f\n" % [stats.walk_speed, stats.walk_speed * stats.boost_speed_multiplier, stats.boost_acceleration]
	text += "Torso turn %d deg/s   Legs turn %d deg/s   Jump %.1f m\n" % [roundi(stats.torso_turn_speed_deg), roundi(stats.leg_turn_speed_deg), stats.jump_height]
	text += "PART HP"
	for part_name in stats.part_hp:
		text += "\n  %s: %d" % [part_name, roundi(stats.part_hp[part_name])]
	return text


func _weapons_text() -> String:
	var weapons := mech.get_node_or_null("WeaponController") as WeaponController
	if weapons == null:
		return ""
	var lines := PackedStringArray()
	for slot in weapons.get_hud_slots():
		var key: String = slot[0]
		var item = slot[1]
		if item is MechWeapon:
			var weapon := item as MechWeapon
			lines.append("%s  %s   %s" % [key, weapon.data.display_name, weapon.get_status_text()])
		else:
			lines.append("%s  %s" % [key, (item as WeaponData).display_name])
	return "\n".join(lines)
