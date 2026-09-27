class_name Mech
extends CharacterBody3D
## Moves a heavy mech. Reads what to do from a MechInput node.
## All tuning values are in the Inspector. Units: meters, seconds.

signal jumped
signal boost_exit_hop
signal landed(fall_speed: float)

@export var input: MechInput
@export var energy: MechEnergy
## Gives stride length and step events for walk-in, stop, and boost exit steps.
@export var footsteps: MechFootsteps
@export var landing_recovery: MechLandingRecovery

## Total mech weight in tons. Phase 2 computes this from parts.
@export var mass_tons: float = 60.0

@export_group("Ground")
## Top forward walking speed in m/s.
@export var walk_speed: float = 9.1
## Walk speed to the side = walk speed x this value.
@export var strafe_speed_multiplier: float = 0.9
## Speed gain while walking (m/s per second). 4.04 reaches top walk speed in 2.25 s.
@export var acceleration: float = 4.04
## Slowdown for very slow stops that take less than one step (m/s per second).
@export var deceleration: float = 9.0
## Steps the mech takes to stop from full walk speed.
@export var walk_stop_steps: int = 2
## Steps the mech takes to stop from full boost speed.
@export var boost_stop_steps: int = 4
## Slowdown while the mech recovers from a hard landing (m/s per second).
@export var landing_brake: float = 25.0

@export_group("Turning")
## Top body turn speed toward the camera direction (degrees per second).
@export var turn_speed_deg: float = 84.0
## How fast the body gains turn speed (degrees per second per second).
@export var turn_acceleration_deg: float = 360.0
## How far the body turns past the aim at full turn speed, in degrees. Slow turns overshoot less.
@export var turn_overshoot_deg: float = 10.0

@export_group("Boost")
## Boost top speed = walk speed x this value.
@export var boost_speed_multiplier: float = 1.5
## Walking steps needed before boost can start.
@export var boost_start_steps: int = 2
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
## Upward push of the jets (m/s per second). Gravity x gravity_scale is about 21.6.
## At 23.7 the jets climb at 2.1 m/s per second.
@export var jet_thrust: float = 23.7
## The jets stop pushing above this rise speed (m/s). This sets the top height on a full tank (about 9 m).
@export var jet_max_rise_speed: float = 1.7
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
## True from the boost exit hop until the mech is back at walk speed or stopped.
var is_exiting_boost: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _walk_steps: int = 0
var _exit_deceleration: float = 0.0
var _stop_deceleration: float = 0.0
var _turn_velocity: float = 0.0
var _turn_settling: bool = false


func _ready() -> void:
	footsteps.footstep.connect(_on_footstep)


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


## True after the walk-in steps, so boost can start.
func is_boost_ready() -> bool:
	return _walk_steps >= boost_start_steps


func get_walk_steps_left() -> int:
	return maxi(boost_start_steps - _walk_steps, 0)


func _on_footstep(_strength: float) -> void:
	_walk_steps += 1


func _update_boost(delta: float) -> void:
	if get_horizontal_speed() < footsteps.min_speed:
		_walk_steps = 0
	var was_boosting := is_boosting
	var has_input := input.move_direction.length_squared() > 0.01
	var wants_boost := input.boost_held and has_input and is_boost_ready() and not landing_recovery.is_recovering()
	is_boosting = wants_boost and energy.try_drain(boost_energy_per_second * delta)
	if is_boosting:
		is_exiting_boost = false
	elif was_boosting and is_on_floor() and get_horizontal_speed() > walk_speed * 1.05:
		is_exiting_boost = true
		_exit_deceleration = 0.0
		_stop_deceleration = 0.0
		velocity.y = boost_exit_hop_velocity
		boost_exit_hop.emit()


func _update_jets(delta: float) -> void:
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	var wants_jets := input.jump_held and not is_on_floor() and _air_time >= jet_delay
	is_jetting = wants_jets and energy.try_drain(boost_energy_per_second * jet_energy_multiplier * delta)


func _update_horizontal(delta: float) -> void:
	var recovering := landing_recovery.is_recovering()
	var wish := Vector3.ZERO if recovering else input.move_direction
	var has_input := wish.length_squared() > 0.001
	# A hop that starts this frame counts as air, so step plans start after landing.
	var on_floor := is_on_floor() and velocity.y <= 0.0
	var speed := get_horizontal_speed()

	var target := Vector3.ZERO
	var rate := deceleration
	if recovering:
		rate = landing_brake
	elif not has_input:
		rate = _get_stop_deceleration() if on_floor else deceleration
	elif is_boosting:
		target = wish * get_boost_speed()
		rate = boost_acceleration
	else:
		target = wish * _get_walk_speed(wish)
		rate = _get_exit_deceleration() if is_exiting_boost and on_floor else acceleration
	if not on_floor and not is_boosting:
		rate *= jet_air_control if is_jetting else air_control

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if has_input:
		_stop_deceleration = 0.0
		if is_exiting_boost and on_floor and speed <= walk_speed + 0.05:
			is_exiting_boost = false
	elif speed < 0.05:
		_stop_deceleration = 0.0
		is_exiting_boost = false


## Walk speed for a move direction. Moving to the side is slower than forward.
func _get_walk_speed(wish: Vector3) -> float:
	var local := wish.rotated(Vector3.UP, -input.aim_yaw)
	var side := absf(local.x) / maxf(local.length(), 0.001)
	return walk_speed * lerpf(1.0, strafe_speed_multiplier, side)


## Distance that ends with the given number of footsteps, measured from now.
func _get_steps_distance(steps: int) -> float:
	var stride := footsteps.stride_length
	return footsteps.get_distance_to_next_step() + (steps - 1) * stride + 0.25 * stride


## Slowdown that stops the mech in a set number of steps: 2 from walk, 4 from boost.
## Slower speeds take fewer steps.
func _get_stop_deceleration() -> float:
	if _stop_deceleration <= 0.0:
		var speed := get_horizontal_speed()
		var from_boost := is_exiting_boost or speed > walk_speed * 1.05
		var max_steps := boost_stop_steps if from_boost else walk_stop_steps
		var reference_speed := get_boost_speed() if from_boost else walk_speed
		var steps := mini(roundi(max_steps * pow(speed / reference_speed, 2.0)), max_steps)
		if is_exiting_boost:
			# The hop loses a little speed in the air. A stop from boost always takes all its steps.
			steps = max_steps
		if steps < 1:
			_stop_deceleration = deceleration
		else:
			_stop_deceleration = maxf(speed * speed / (2.0 * _get_steps_distance(steps)), 0.5)
	return _stop_deceleration


## Slowdown that brings boost speed down to walk speed over the exit steps.
func _get_exit_deceleration() -> float:
	if _exit_deceleration <= 0.0:
		var speed := get_horizontal_speed()
		var distance := _get_steps_distance(boost_exit_steps)
		_exit_deceleration = maxf((speed * speed - walk_speed * walk_speed) / (2.0 * distance), 0.5)
	return _exit_deceleration


func _update_vertical(delta: float) -> void:
	if is_on_floor():
		if input.consume_jump() and not landing_recovery.is_recovering():
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
