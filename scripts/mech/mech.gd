class_name Mech
extends CharacterBody3D
## Moves a heavy mech. Reads what to do from a MechInput node.
## All tuning values are in the Inspector. Units: meters, seconds.

signal jumped
signal landed(fall_speed: float)

@export var input: MechInput
@export var energy: MechEnergy

@export_group("Ground")
## Top walking speed in m/s.
@export var walk_speed: float = 14.0
## How fast the mech gains speed (m/s per second). Low value = heavy feel.
@export var acceleration: float = 10.0
## How fast the mech loses speed when you release the keys.
@export var deceleration: float = 14.0
## How fast the body turns to face the camera direction (degrees per second).
@export var turn_speed_deg: float = 140.0

@export_group("Boost")
## Top speed while boosting in m/s.
@export var boost_speed: float = 36.0
## Speed gain while boosting (m/s per second).
@export var boost_acceleration: float = 45.0
## Energy used each second while boosting.
@export var boost_energy_per_second: float = 30.0

@export_group("Air")
## Upward speed at the start of a jump in m/s.
@export var jump_velocity: float = 17.0
## Multiplier on world gravity. Above 1 makes the mech fall faster and feel heavier.
@export var gravity_scale: float = 2.2
## Fraction of ground control you keep in the air (0 to 1).
@export var air_control: float = 0.35
@export var max_fall_speed: float = 60.0

var is_boosting: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_on_floor: bool = true


func _physics_process(delta: float) -> void:
	_update_boost(delta)
	_update_horizontal(delta)
	_update_vertical(delta)
	_turn_body(delta)
	var fall_speed := -velocity.y
	move_and_slide()
	_check_landing(fall_speed)


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _update_boost(delta: float) -> void:
	var wants_boost := input.boost_held and input.move_direction.length_squared() > 0.01
	is_boosting = wants_boost and energy.try_drain(boost_energy_per_second * delta)


func _update_horizontal(delta: float) -> void:
	var wish := input.move_direction
	var target_speed := boost_speed if is_boosting else walk_speed
	var target := wish * target_speed

	var rate := deceleration
	if wish.length_squared() > 0.001:
		rate = boost_acceleration if is_boosting else acceleration
	if not is_on_floor() and not is_boosting:
		rate *= air_control

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_vertical(delta: float) -> void:
	if is_on_floor():
		if input.consume_jump():
			velocity.y = jump_velocity
			jumped.emit()
	else:
		velocity.y = maxf(velocity.y - _gravity * gravity_scale * delta, -max_fall_speed)


func _turn_body(delta: float) -> void:
	rotation.y = rotate_toward(rotation.y, input.aim_yaw, deg_to_rad(turn_speed_deg) * delta)


func _check_landing(fall_speed: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
	_was_on_floor = on_floor
