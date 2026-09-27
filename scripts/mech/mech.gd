class_name Mech
extends CharacterBody3D
## Moves a heavy mech. Reads what to do from a MechInput node.
## Jumps come from MechJumpCharge. A move key held while charging gives a directional jump.
## In the air, a move key uses free steering (MechAirSteer, up to 5 m).
## Shift + a move key in the air fires the boosters at reduced power and uses energy.
## All tuning values are in the Inspector. Units: meters, seconds.

signal jumped
signal boost_exit_hop
signal landed(fall_speed: float)

@export var input: MechInput
@export var energy: MechEnergy
## Gives stride length and step events for walk-in, stop, and boost exit steps.
@export var footsteps: MechFootsteps
@export var landing_recovery: MechLandingRecovery
@export var jump_charge: MechJumpCharge
@export var air_steer: MechAirSteer

## Total mech weight in tons. Phase 2 computes this from parts.
@export var mass_tons: float = 60.0

@export_group("Ground")
## Top forward walking speed in m/s.
@export var walk_speed: float = 9.1
## Walk speed to the side = walk speed x this value.
@export var strafe_speed_multiplier: float = 0.9
## Speed gain while walking (m/s per second). 5.2 reaches top walk speed in 1.75 s.
@export var acceleration: float = 5.2
## Slowdown for very slow stops that take less than one step (m/s per second).
@export var deceleration: float = 9.0
## Steps the mech takes to stop from full walk speed.
@export var walk_stop_steps: int = 2
## Steps the mech takes to stop from full boost speed.
@export var boost_stop_steps: int = 4
## Steps the mech takes to stop after landing from a jump with sideways speed.
@export var landing_stop_steps: int = 3
## Slowdown while the mech charges its jump jets (m/s per second). The mech stands still to charge.
@export var jump_charge_brake: float = 9.0

@export_group("Turning")
## Top body turn speed toward the camera direction (degrees per second).
@export var turn_speed_deg: float = 84.0
## How fast the body gains turn speed (degrees per second per second).
@export var turn_acceleration_deg: float = 360.0
## Near the end of a turn the body slows down. The slow zone starts when the gap to the aim
## is this fraction of the gap at the start of the turn.
@export_range(0.0, 1.0) var turn_slow_zone: float = 0.25
## Turn speed in the slow zone = turn speed x this value.
@export_range(0.1, 1.0) var turn_slow_multiplier: float = 0.5

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
## Air boost acceleration = boost acceleration x this value. 0.25 = 75% less than on the ground.
@export var air_boost_multiplier: float = 0.25

@export_group("Air")
## Sideways speed of a directional jump (move key held while charging), in m/s.
@export var directional_jump_speed: float = 9.1
## Multiplier on world gravity. Above 1 makes the mech fall faster and feel heavier.
@export var gravity_scale: float = 2.2
@export var max_fall_speed: float = 60.0

var is_boosting: bool = false
## True while boosting in the air to steer.
var is_air_boosting: bool = false
## True from the boost exit hop until the mech is back at walk speed or stopped.
var is_exiting_boost: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_on_floor: bool = true
var _boost_on_ground: bool = false
var _in_exit_hop: bool = false
var _walk_steps: int = 0
var _exit_deceleration: float = 0.0
var _stop_deceleration: float = 0.0
var _landing_stop: bool = false
var _airborne: bool = false
var _turn_velocity: float = 0.0
var _turn_start_error: float = 0.0


func _ready() -> void:
	footsteps.footstep.connect(_on_footstep)


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
	if get_horizontal_speed() < footsteps.min_speed and is_on_floor():
		_walk_steps = 0
	if is_on_floor() and velocity.y <= 0.0:
		_in_exit_hop = false
	var was_ground_boosting := is_boosting and _boost_on_ground
	var has_input := input.move_direction.length_squared() > 0.01
	var wants_boost := false
	if is_on_floor():
		wants_boost = input.boost_held and has_input and is_boost_ready() \
				and not landing_recovery.is_recovering() and not jump_charge.is_charging
	else:
		# Shift + a move key fires the boosters in the air. A move key alone uses free steering.
		# The boost exit hop is part of the walk, so no steering there.
		wants_boost = input.boost_held and has_input and not _in_exit_hop
	is_boosting = wants_boost and energy.try_drain(boost_energy_per_second * delta)
	is_air_boosting = is_boosting and not is_on_floor()
	_boost_on_ground = is_boosting and is_on_floor()
	if is_boosting:
		is_exiting_boost = false
	elif was_ground_boosting and is_on_floor() and get_horizontal_speed() > walk_speed * 1.05:
		is_exiting_boost = true
		_in_exit_hop = true
		_exit_deceleration = 0.0
		_stop_deceleration = 0.0
		velocity.y = boost_exit_hop_velocity
		boost_exit_hop.emit()


func _update_horizontal(delta: float) -> void:
	var recovering := landing_recovery.is_recovering()
	var charging := jump_charge.is_charging
	var wish := Vector3.ZERO if recovering or charging else input.move_direction
	var has_input := wish.length_squared() > 0.001
	# A hop that starts this frame counts as air, so step plans start after landing.
	var on_floor := is_on_floor() and velocity.y <= 0.0
	var speed := get_horizontal_speed()

	if not on_floor and not is_boosting:
		if not _airborne:
			# First air frame (hop or walking off an edge). Jumps start the flight at launch.
			_start_flight()
		# Free steering, or momentum only after the free steering is used.
		var steered := air_steer.steer(Vector3.ZERO if _in_exit_hop else wish, delta)
		velocity.x = steered.x
		velocity.z = steered.z
		return

	var target := Vector3.ZERO
	var rate := deceleration
	if recovering:
		# No control after a landing, but the mech keeps walking out its momentum.
		rate = _get_stop_deceleration()
	elif charging:
		rate = jump_charge_brake
	elif not has_input:
		rate = _get_stop_deceleration() if on_floor else deceleration
	elif is_boosting:
		target = wish * get_boost_speed()
		rate = boost_acceleration if on_floor else boost_acceleration * air_boost_multiplier
	else:
		target = wish * _get_walk_speed(wish)
		rate = _get_exit_deceleration() if is_exiting_boost and on_floor else acceleration

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not on_floor:
		air_steer.rebase()

	if has_input:
		_stop_deceleration = 0.0
		_landing_stop = false
		if is_exiting_boost and on_floor and speed <= walk_speed + 0.05:
			is_exiting_boost = false
	elif speed < 0.05:
		_stop_deceleration = 0.0
		is_exiting_boost = false
		_landing_stop = false


## Walk speed for a move direction. Moving to the side is slower than forward.
func _get_walk_speed(wish: Vector3) -> float:
	var local := wish.rotated(Vector3.UP, -input.aim_yaw)
	var side := absf(local.x) / maxf(local.length(), 0.001)
	return walk_speed * lerpf(1.0, strafe_speed_multiplier, side)


## Steady slowdown from the current speed to end_speed, with the given number of footsteps on the way.
## The last step lands a quarter stride before the end.
func _get_deceleration_for_steps(steps: int, end_speed: float) -> float:
	var step_target := footsteps.get_progress_to_next_step() + (steps - 1) + 0.25
	var steps_times_rate := footsteps.get_steps_times_rate(get_horizontal_speed(), end_speed)
	return maxf(steps_times_rate / step_target, 0.3)


## Slowdown that stops the mech in a set number of steps:
## 2 from walk, 4 from boost, 3 after landing from a jump with sideways speed.
## Slow walks take fewer steps.
func _get_stop_deceleration() -> float:
	if _stop_deceleration <= 0.0:
		var speed := get_horizontal_speed()
		var steps := walk_stop_steps
		if _landing_stop:
			steps = landing_stop_steps
		elif is_exiting_boost or speed > walk_speed * 1.05:
			steps = boost_stop_steps
		else:
			steps = mini(roundi(walk_stop_steps * pow(speed / walk_speed, 2.0)), walk_stop_steps)
		if steps < 1 or speed < footsteps.min_speed:
			_stop_deceleration = deceleration
		else:
			_stop_deceleration = _get_deceleration_for_steps(steps, 0.0)
	return _stop_deceleration


## Slowdown that brings boost speed down to walk speed over the exit steps.
func _get_exit_deceleration() -> float:
	if _exit_deceleration <= 0.0:
		_exit_deceleration = _get_deceleration_for_steps(boost_exit_steps, walk_speed)
	return _exit_deceleration


func _update_vertical(delta: float) -> void:
	var gravity := _gravity * gravity_scale
	if is_on_floor():
		var height := jump_charge.take_launch_height()
		if height > 0.0:
			# Launch speed that reaches the charged height.
			# The half-frame term cancels the extra rise from the physics frame step.
			velocity.y = sqrt(2.0 * gravity * height) - 0.5 * gravity * delta
			var sideways := jump_charge.launch_direction * directional_jump_speed
			velocity.x = sideways.x
			velocity.z = sideways.z
			_start_flight()
			jumped.emit()
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


func _start_flight() -> void:
	_airborne = true
	air_steer.begin_flight()


## Turns the body toward the aim with no overshoot. The last part of each turn is slower,
## so the mech crosshair eases onto the camera crosshair.
func _turn_body(delta: float) -> void:
	var error := wrapf(input.aim_yaw - rotation.y, -PI, PI)
	var gap := absf(error)
	if gap < deg_to_rad(0.1):
		_turn_start_error = 0.0
	_turn_start_error = maxf(_turn_start_error, gap)

	var max_speed := deg_to_rad(turn_speed_deg)
	if gap < _turn_start_error * turn_slow_zone:
		max_speed *= turn_slow_multiplier
	var accel := deg_to_rad(turn_acceleration_deg)
	# Brake in time to stop exactly on the aim.
	var desired := signf(error) * minf(max_speed, sqrt(2.0 * accel * gap))
	_turn_velocity = move_toward(_turn_velocity, desired, accel * delta)

	var step := _turn_velocity * delta
	if signf(step) == signf(error) and absf(step) >= gap:
		rotation.y = wrapf(rotation.y + error, -PI, PI)
		_turn_velocity = 0.0
	else:
		rotation.y = wrapf(rotation.y + step, -PI, PI)


func _check_landing(fall_speed: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		# Landing with sideways speed from a jump: walk it out in a set number of steps.
		_landing_stop = not is_exiting_boost and get_horizontal_speed() > footsteps.min_speed
		_stop_deceleration = 0.0
		_airborne = false
		landed.emit(fall_speed)
	_was_on_floor = on_floor
