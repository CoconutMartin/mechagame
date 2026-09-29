class_name AIPilot
extends Node
## A simple gunner pilot (Phase 4b). It fills the same MechInput values a player fills with the
## keyboard and mouse, so the enemy mech moves, turns, boosts, dodges and fires with the same rules.
##   Range: it walks toward the target when it is far (and boosts when very far), backs off when it
##          is too close, and keeps a preferred range in between.
##   Strafe: it steps left or right and changes side every few seconds.
##   Fire: it holds the trigger when it can see the target, the target is in range, and the torso
##         is turned to it. The aim point wanders around the target (it is not a perfect shot).
##   Shield: it lifts the shield now and then, more often when it is hurt.
##   Dodge: now and then a dodge hop to the side it strafes to.

@export var mech: Mech
@export var input: MechInput
@export var mech_aim: MechAim

@export_group("Range")
## The pilot tries to stay between these distances from the target, in meters.
@export var near_range: float = 40.0
@export var far_range: float = 80.0
## Farther than this it boosts toward the target, in meters.
@export var boost_range: float = 130.0
## It sees targets up to this far, in meters.
@export var sight_range: float = 400.0

@export_group("Fire")
## Largest distance it shoots from, in meters.
@export var fire_range: float = 180.0
## It fires only when the torso points within this angle of the target, in degrees.
@export var fire_angle_deg: float = 6.0
## Aim error: the aim point wanders up to this far from the target center, in meters.
@export var aim_error: float = 2.2
## Seconds before it reacts to a target it just saw.
@export var reaction_time: float = 0.8

@export_group("Moves")
## Seconds between strafe side changes (random in this range).
@export var strafe_time_min: float = 2.0
@export var strafe_time_max: float = 4.5
## Chance per second of a dodge hop, and of lifting the shield (for shield_time seconds).
@export var dodge_chance: float = 0.06
@export var shield_chance: float = 0.12
@export var shield_time: float = 1.6

var target: Mech

var _strafe_side: float = 1.0
var _strafe_left: float = 0.0
var _seen_time: float = 0.0
var _aim_offset := Vector3.ZERO
var _aim_offset_goal := Vector3.ZERO
var _aim_offset_left: float = 0.0
var _shield_left: float = 0.0
var _dodge_step: int = 0
var _dodge_wait: float = 0.0


func _ready() -> void:
	# Before the Mech reads its input (same slot as MechInput).
	process_physics_priority = -10
	input.process_mode = Node.PROCESS_MODE_DISABLED
	mech_aim.use_ai_target = true
	_strafe_side = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	_clear_buttons()
	if mech.is_wrecked:
		return
	target = _find_target()
	if target == null:
		_seen_time = 0.0
		return
	var to_target := target.get_lock_point() - mech.get_lock_point()
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var distance := flat.length()
	var sees := distance < sight_range and _has_line_of_sight()
	_seen_time = _seen_time + delta if sees else 0.0

	# Turn the torso (and so the legs) toward the target.
	input.aim_yaw = atan2(-flat.x, -flat.z)
	_update_aim(delta)
	if _seen_time < reaction_time:
		return
	_move(flat, distance, delta)
	_fire(distance, sees)
	_shield(delta)
	_dodge(delta)


func _clear_buttons() -> void:
	input.move_direction = Vector3.ZERO
	input.turn_input = 0.0
	input.boost_held = false
	input.jump_held = false
	input.jump_pressed = false
	input.fire_held = false
	input.aim_held = false
	input.shield_held = false
	input.left_fire_held = false
	input.back_left_held = false
	input.back_right_held = false
	input.reload_pressed = false
	input.forward_held = false
	input.crouch_pressed = false


## The nearest living player mech.
func _find_target() -> Mech:
	var best: Mech = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"player"):
		var other := node as Mech
		if other == null or other == mech or other.is_wrecked:
			continue
		var distance := mech.global_position.distance_to(other.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _has_line_of_sight() -> bool:
	var from := mech_aim.aim_origin.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target.get_lock_point(), 1)
	return mech.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The aim point wanders around the target (a new spot every so often, reached smoothly).
func _update_aim(delta: float) -> void:
	_aim_offset_left -= delta
	if _aim_offset_left <= 0.0:
		_aim_offset_left = randf_range(0.6, 1.4)
		_aim_offset_goal = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * aim_error
	_aim_offset = _aim_offset.lerp(_aim_offset_goal, 1.0 - exp(-3.0 * delta))
	mech_aim.ai_target = target.get_lock_point() + _aim_offset


func _move(flat: Vector3, distance: float, delta: float) -> void:
	var forward := flat.normalized()
	var side := forward.cross(Vector3.UP).normalized()
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(strafe_time_min, strafe_time_max)
		_strafe_side = -_strafe_side
	var wish := side * _strafe_side
	if distance > far_range:
		wish = forward * 1.0 + side * _strafe_side * 0.3
	elif distance < near_range:
		wish = -forward * 0.8 + side * _strafe_side * 0.6
	input.move_direction = wish.normalized()
	# A (+1) is left: the side vector points right.
	input.turn_input = -_strafe_side
	input.boost_held = distance > boost_range
	input.forward_held = distance > far_range


func _fire(distance: float, sees: bool) -> void:
	if not sees or distance > fire_range or _shield_left > 0.0:
		return
	var error := absf(wrapf(input.aim_yaw - mech.get_aim_yaw(), -PI, PI))
	input.fire_held = error < deg_to_rad(fire_angle_deg)


## Now and then the shield comes up for a moment (more often when hurt).
func _shield(delta: float) -> void:
	_shield_left = maxf(_shield_left - delta, 0.0)
	var hurt := 1.0 - mech.health.get_fraction("Torso C") if mech.health != null else 0.0
	if _shield_left <= 0.0 and randf() < shield_chance * (1.0 + 2.0 * hurt) * delta:
		_shield_left = shield_time
	input.shield_held = _shield_left > 0.0
	input.left_fire_held = input.shield_held


## A dodge hop is a double tap of the jump key: two one-frame presses 0.12 s apart.
func _dodge(delta: float) -> void:
	if _dodge_step == 0:
		if mech.is_on_floor() and not mech.one_leg and randf() < dodge_chance * delta:
			_dodge_step = 1
		return
	_dodge_wait -= delta
	if _dodge_wait > 0.0:
		return
	input.jump_pressed = true
	input.jump_held = true
	_dodge_step += 1
	_dodge_wait = 0.12
	if _dodge_step > 2:
		_dodge_step = 0
