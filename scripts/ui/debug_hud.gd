extends CanvasLayer
## Shows live movement values for testing, and the build stats from the loadout (Phase 2):
## total weight, load ratio, speeds and the HP of each part.

const NAMES: MechNameCatalog = preload("res://data/names/mech_names.tres")

@export var mech: Mech
@export var mech_aim: MechAim

## Test text (speeds, build, part HP, weapon status, controls). Hidden on the mech screen (user request
## 2026-10-14: no text); the ` key shows and hides it.
@export var show_text: bool = false

@onready var _info: Label = $Info
@onready var _energy_bar: ProgressBar = $EnergyBar
@onready var _build: Label = $Build
@onready var _weapons_label: Label = $Weapons

var _pickup_prompt: WeaponPickupPrompt
var _scan_status: PulseScanStatus


func _ready() -> void:
	set_mech(mech)
	_show_text(show_text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_text"):
		_show_text(not show_text)


func _show_text(on: bool) -> void:
	show_text = on
	for path in [^"Info", ^"Build", ^"Weapons", ^"Controls", ^"EnergyBar/EnergyLabel"]:
		(get_node(path) as CanvasItem).visible = on


## Follows a mech (LoadoutSwitcher calls it after it builds a new one).
func set_mech(new_mech: Mech) -> void:
	mech = new_mech
	mech_aim = mech.get_node("MechAim") as MechAim
	var reticle := $AimReticle as AimReticle
	reticle.mech_aim = mech_aim
	reticle.weapons = mech.get_node_or_null("WeaponController") as WeaponController
	# The pick-up line (user rule 2026-10-17), made once; it follows each new mech.
	if _pickup_prompt == null:
		_pickup_prompt = WeaponPickupPrompt.new()
		add_child(_pickup_prompt)
	_pickup_prompt.mech = mech
	if _scan_status == null:
		_scan_status = PulseScanStatus.new()
		add_child(_scan_status)
	_scan_status.mech = mech


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
	state += "\n" + _camera_text()
	var energy := mech.energy
	_info.text = "Speed: %.1f m/s (%d km/h)\nHeight: %.1f m\nWeight: %d t\nState: %s\nEnergy: %d / %d%s\nFPS: %d" % [
		speed, roundi(speed * 3.6), mech.global_position.y, roundi(mech.mass_tons), state,
		roundi(energy.current), roundi(energy.capacity),
		"  (EMPTY)" if energy.is_depleted else "",
		Engine.get_frames_per_second(),
	]
	if show_text:
		_build.text = _build_text()
		_weapons_label.text = _weapons_text()
	_energy_bar.value = energy.get_fraction() * 100.0
	_energy_bar.modulate = Color(1.0, 0.35, 0.3) if energy.is_depleted else Color.WHITE


## Camera angle: camera pitch (negative = looking down), aim pitch, distance to the mech and FOV.
func _camera_text() -> String:
	var camera := mech_aim.camera
	if camera == null:
		return "Camera: none"
	var forward := -camera.global_basis.z
	var cam_pitch := rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	var aim_pitch := rad_to_deg(mech_aim.camera_rig.pitch) if mech_aim.camera_rig != null else 0.0
	var distance := camera.global_position.distance_to(mech.global_position)
	return "Camera: pitch %.1f deg   aim %.1f deg   dist %.1f m   FOV %d" % [cam_pitch, aim_pitch, distance, roundi(camera.fov)]


func _build_text() -> String:
	var stats := mech.stats
	var health := mech.health
	if stats == null and health == null:
		return "Build: no loadout"
	var text := "BUILD\n"
	var entry := NAMES.find_code(mech.name_code) if mech.name_code != "" else null
	if entry != null:
		text += "Mech: %s\n" % MechNameCatalog.full_name(entry)
	if stats == null or mech.get_node_or_null("WeaponMount") != null:
		# A mech not built from parts (Sagigilid): its own speeds; the parts give weight and HP only.
		if stats != null:
			text += "Weight: %.1f t\n" % stats.total_weight_t
		text += "Walk %.1f m/s   Boost %.1f m/s\n" % [mech.walk_speed, mech.get_boost_speed()]
	else:
		text += "Weight: %.1f / %.0f t   Load: %d%%\n" % [stats.total_weight_t, stats.load_capacity_t, roundi(stats.load_ratio * 100.0)]
		text += "Walk %.1f m/s   Boost %.1f m/s   Boost accel %.1f\n" % [stats.walk_speed, stats.walk_speed * stats.boost_speed_multiplier, stats.boost_acceleration]
		text += "Torso turn %d deg/s   Legs turn %d deg/s   Jump %.1f m\n" % [roundi(stats.torso_turn_speed_deg), roundi(stats.leg_turn_speed_deg), stats.jump_height]
	text += "PART HP"
	if health == null:
		for part_name in stats.part_hp:
			text += "\n  %s: %d" % [_part_label(part_name), roundi(stats.part_hp[part_name])]
		return text
	for key: String in health.max_hp:
		var now: float = health.hp[key]
		var state := "  DESTROYED" if now <= 0.0 else ""
		text += "\n  %s: %d / %d%s" % [_part_label(key), roundi(now), roundi(health.max_hp[key]), state]
	if health.is_destroyed:
		text += "\nMECH DESTROYED"
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


## Part HP label in the part name style (user request 2026-10-14): "Arm L" -> "Arm (L)".
func _part_label(key: String) -> String:
	var words := key.split(" ")
	if words.size() == 2 and words[1].length() == 1:
		return "%s (%s)" % [words[0], words[1]]
	return key
