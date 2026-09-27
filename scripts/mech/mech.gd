class_name Mech
extends CharacterBody3D
## Moves a heavy mech. Reads what to do from a MechInput node.
## All tuning values are in the Inspector. Units: meters, seconds.

signal jumped
signal boost_exit_hop
signal landed(fall_speed: float)

@export var input: MechInput
@export var energy: MechEnergy
## Gives the stride length for the boost exit steps.
@export var footsteps: MechFootsteps

@export_group("Ground")
## Top walking speed in m/s.
@export var walk_speed: float = 9.1
## How fast the mech gains speed (m/s per second). Low value = heavy feel.
@export var acceleration: float = 6.5
## How fast the mech loses speed when you release the keys.
@export var deceleration: float = 9.0

@export_group("Turning")
## Top body turn speed toward the camera direction (degrees per second).
@export var turn_speed_deg: float = 140.0
## How fast the body gains turn speed (degrees per second per second).
@export var turn_acceleration_deg: float = 600.0
## How far the body turns past the aim at full turn speed, in degrees. Slow turns overshoot less.
@export var turn_overshoot_deg: float = 10.0

@export_group("Boost")
## Boost top speed = walk speed x this value.
@export var boost_speed_multiplier: float = 1.5
## Speed gain while boosting (m/s per second).
@export var boost_acceleration: float = 20.0
## Upward speed of the small hop when boost stops on the ground (m/s).
@export var boost_exit_hop_velocity: float = 6.0
## After the hop, the mech slows to walk speed over this many steps.
@export var boost_exit_steps: int = 2
## Energy used each second while boosting.
@export var boost_energy_per_second: float = 30.0

@export_group("Jump Jets")
## Hold jump in the air to fire jump jets.
## Energy use per second = boost energy use x this value. Jets cost more than boost.
@export var jet_energy_multiplier: float = 2.0
## Upward push of the jets (m/s per second). Must be above gravity x gravity_scale (about 21.6) to climb.
## At 25.8 the mech climbs at 4.2 m/s per second.
@export var jet_thrust: float = 25.8
## The jets stop pushing above this rise speed (m/s).
@export var jet_max_rise_speed: float = 8.0
## Air control while the jets fire (0 to 1).
@export var jet_air_control: float = 0.8
## Wait after a jump (seconds) before the jets can fire, so a tap stays a normal jump.
@export var jet_delay: float = 0.25

@export_group("Air")
## Upward speed at the start of a jump in m/s.
@export var jump_velocity: float = 17.0
## Multiplier on world gravity. Above 1 makes the mech fall faster and feel heavier.
@export var gravity_scale: float = 2.2
## Fraction of ground control you keep in the air (0 to 1).
@export var air_control: float = 0.35
@export var max_fall_speed: float = 60.0

var is_boosting: bool = false
var is_jetting: bool = false
## True from the boost exit hop until the mech is back at walk speed.
var is_exiting_boost: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _exit_deceleration: float = 0.0
var _turn_velocity: float = 0.0
var _turn_settling: bool = false


func _physics_process(delta: float) -> void:
	_update_boost(delta)
	_update_jets(delta)
	_update_horizontal(delta)
	_update_vertical(delta)
	_turn_body(delta)
	var fall_speed := -velocity.y
	move_and_slide()
	_check_landing(fall_speed)


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_boost_speed() -> float:
	return walk_speed * boost_speed_multiplier


func _update_boost(delta: float) -> void:
	var was_boosting := is_boosting
	var wants_boost := input.boost_held and input.move_direction.length_squared() > 0.01
	is_boosting = wants_boost and energy.try_drain(boost_energy_per_second * delta)
	if is_boosting:
		is_exiting_boost = false
	elif was_boosting and is_on_floor() and get_horizontal_speed() > walk_speed * 1.05:
		is_exiting_boost = true
		_exit_deceleration = 0.0
		velocity.y = boost_exit_hop_velocity
		boost_exit_hop.emit()


func _update_jets(delta: float) -> void:
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	var wants_jets := input.jump_held and not is_on_floor() and _air_time >= jet_delay
	is_jetting = wants_jets and energy.try_drain(boost_energy_per_second * jet_energy_multiplier * delta)


func _update_horizontal(delta: float) -> void:
	var wish := input.move_direction
	var target_speed := get_boost_speed() if is_boosting else walk_speed
	var target := wish * target_speed

	var rate := deceleration
	if wish.length_squared() > 0.001:
		rate = boost_acceleration if is_boosting else acceleration
		if is_exiting_boost and is_on_floor():
			rate = _get_exit_deceleration()
	if not is_on_floor() and not is_boosting:
		rate *= jet_air_control if is_jetting else air_control

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_exiting_boost and is_on_floor() and horizontal.length() <= walk_speed + 0.05:
		is_exiting_boost = false


## Slowdown that brings boost speed down to walk speed over the exit steps.
func _get_exit_deceleration() -> float:
	if _exit_deceleration <= 0.0:
		var speed := get_horizontal_speed()
		var distance := footsteps.stride_length * boost_exit_steps
		_exit_deceleration = maxf((speed * speed - walk_speed * walk_speed) / (2.0 * distance), 0.5)
	return _exit_deceleration


func _update_vertical(delta: float) -> void:
	if is_on_floor():
		if input.consume_jump():
			velocity.y = jump_velocity
			jumped.emit()
	else:
		velocity.y = maxf(velocity.y - _gravity * gravity_scale * delta, -max_fall_speed)
		if is_jetting and velocity.y < jet_max_rise_speed:
			velocity.y = minf(velocity.y + jet_thrust * delta, jet_max_rise_speed)


## Turns the body toward the aim with momentum. A fast turn goes past the aim, stops, and comes back.
func _turn_body(delta: float) -> void:
	var error := wrapf(input.aim_yaw - rotation.y, -PI, PI)
	var max_speed := deg_to_rad(turn_speed_deg)
	var accel := deg_to_rad(turn_acceleration_deg)
	var overshoot := deg_to_rad(turn_overshoot_deg)
	# Braking after the aim is passed. At full speed this stops the body exactly overshoot past the aim.
	var brake := max_speed * max_speed / (2.0 * overshoot)

	var passed_aim := _turn_velocity != 0.0 and signf(error) != signf(_turn_velocity)
	if passed_aim:
		_turn_velocity = move_toward(_turn_velocity, 0.0, brake * delta)
		_turn_settling = true
	else:
		if absf(error) > overshoot * 2.0:
			_turn_settling = false
		var desired := signf(error) * max_speed
		if _turn_settling:
			# Come back to the aim smoothly, with no second overshoot.
			desired = signf(error) * minf(max_speed, sqrt(2.0 * accel * absf(error)))
		_turn_velocity = move_toward(_turn_velocity, desired, accel * delta)

	rotation.y = wrapf(rotation.y + _turn_velocity * delta, -PI, PI)
	if absf(error) < 0.002 and absf(_turn_velocity) < 0.05:
		_turn_velocity = 0.0
		_turn_settling = false


func _check_landing(fall_speed: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
	_was_on_floor = on_floor
