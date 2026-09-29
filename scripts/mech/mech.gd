class_name Mech
extends CharacterBody3D
## Moves a heavy mech. Reads what to do from a MechInput node.
## Jumps come from MechJumpCharge. A move key held while charging gives a directional jump.
## In the air, a move key uses free steering (MechAirSteer, up to 5 m).
## Shift + a move key in the air fires the boosters at reduced power (a small extra speed) and uses energy.
## All tuning values are in the Inspector. Units: meters, seconds.

signal jumped
signal boost_exit_step
## Sent when the mech bumps into a wall. strength = speed into the wall, in m/s.
signal bumped(strength: float)
signal landed(fall_speed: float)

@export var input: MechInput
@export var energy: MechEnergy
## Gives stride length and step events for walk-in, stop, and boost exit steps.
@export var footsteps: MechFootsteps
@export var landing_recovery: MechLandingRecovery
@export var jump_charge: MechJumpCharge
@export var air_steer: MechAirSteer
@export var kneel: MechKneel
@export var dodge: MechDodge
## Optional. While the shield is up the mech moves slower (MechShield.get_speed_limit).
@export var shield: MechShield

## Total mech weight in tons. MechAssembler sets it from the loadout.
@export var mass_tons: float = 60.0
## Mech height in meters. Sway and footstep shake scale with it (10 m = base). Phase 2 computes it from parts.
@export var height_m: float = 10.0

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
## Steps the mech takes to stop after landing from a jump with sideways speed.
@export var landing_stop_steps: int = 3
## Slowdown while the mech charges its jump jets (m/s per second). The mech stands still to charge.
@export var jump_charge_brake: float = 9.0

@export_group("Turning")
## The torso and the legs turn separately. The torso turns toward the camera aim (torso turn speed),
## inside these twist limits. The legs turn only with A / D. The camera cannot look past the limits.
## Largest torso twist to the left of the legs, in degrees.
@export var torso_twist_left_deg: float = 52.0
## Largest torso twist to the right of the legs, in degrees.
@export var torso_twist_right_deg: float = 64.0
## Leg turn speed (following the torso) while moving, in degrees per second. Steady (no speed-up).
@export var leg_turn_speed_deg: float = 60.0
## Leg turn speed (following the torso) while standing still, in degrees per second.
@export var leg_turn_speed_standing_deg: float = 30.0
## Standing still, the legs start to follow the torso when it is more than this far off (degrees).
@export var legs_follow_standing_deg: float = 25.0
## Top torso turn speed toward the camera direction (degrees per second).
@export var turn_speed_deg: float = 44.1
## How fast the body gains turn speed (degrees per second per second).
@export var turn_acceleration_deg: float = 189.0
## Near the end of a turn the body slows down. The slow zone starts when the gap to the aim
## is this fraction of the gap at the start of the turn.
@export_range(0.0, 1.0) var turn_slow_zone: float = 0.25
## Turn speed in the slow zone = turn speed x this value.
@export_range(0.1, 1.0) var turn_slow_multiplier: float = 0.5
## Size of each settle swing past the aim, in degrees. 0 = no settle swings (the torso stops on the aim).
@export var turn_settle_swing_deg: float = 0.0
## Turns smaller than this (degrees) lock in with no settle swings.
@export var turn_settle_min_turn_deg: float = 5.0
## Seconds for the first swing (past the aim).
@export var turn_settle_first_time: float = 0.15
## Seconds for the second swing (to the other side of the aim).
@export var turn_settle_second_time: float = 0.3
## Seconds for the snap back onto the aim.
@export var turn_settle_snap_time: float = 0.08

@export_group("Boost")
## Boost top speed = walk speed x this value.
@export var boost_speed_multiplier: float = 1.5
## Walking steps before the mech can start to run. Skipped if the mech already walked this many steps.
@export var boost_start_steps: int = 2
## Running steps before boost starts from a standstill.
@export var run_steps: int = 2
## Moving at least this fast (m/s), boost starts at once with no walk or run steps.
@export var boost_ready_speed: float = 1.5
## Run top speed = walk speed x this value.
@export var run_speed_multiplier: float = 1.25
## Speed gain while boosting (m/s per second).
@export var boost_acceleration: float = 20.0
enum BoostExit { SKID, LEAP }
## How the mech stops a ground boost.
## SKID: feet plant and slide, body leans back, dust, then heavy steps.
## LEAP ("revert 1"): a leap that lands on one leg, then 2 medium and 2 small steps.
@export var boost_exit_style: BoostExit = BoostExit.SKID
## SKID: slowdown while the feet slide (m/s per second).
@export var skid_deceleration: float = 6.7
## A fallen or wrecked mech slides to a stop with this slowdown, in m/s².
@export var fallen_slide_deceleration: float = 3.0
## SKID: the slide ends at this speed (m/s). Then the heavy steps start, or the walk with a move key.
@export var skid_end_speed: float = 4.0
## SKID: stride lengths (meters) of the heavy steps to a stop after the slide, when no move key is held.
@export var skid_stop_strides: PackedFloat32Array = PackedFloat32Array([0.45, 0.35])
## LEAP: upward speed of the leap (m/s).
@export var boost_exit_leap_velocity: float = 5.0
## After the leap, the mech slows down over these steps (stride length of each, in meters):
## 2 medium steps, then 2 small steps. Ends at walk speed with a move key held, or stopped with no key.
@export var boost_exit_strides: PackedFloat32Array = PackedFloat32Array([4.8, 4.8, 3.4, 3.4])

@export_group("Wall Bump")
## Bumps slower than this (m/s into the wall) only slide along the wall.
@export var bump_min_speed: float = 3.0
## Restitution = bounce-back speed / speed into the wall. It grows with the impact speed:
## min at bump_min_speed, max at bump_full_speed and above.
@export_range(0.0, 1.0) var bump_restitution_min: float = 0.4
@export_range(0.0, 1.0) var bump_restitution_max: float = 0.9
## Extra slowdown after a bump, at bump_full_speed and above (0.3 = 30% slower). Less at lower speed.
@export_range(0.0, 1.0) var bump_slowdown_max: float = 0.3
## Impact speed (m/s into the wall) that gives the strongest bounce and slowdown. Boost speed is 13.65.
@export var bump_full_speed: float = 13.65
## Energy used each second while boosting.
@export var boost_energy_per_second: float = 30.0
## Air boost acceleration and top speed = ground boost values x this value. 0.25 = 75% less.
## The air boost speed adds to the jump momentum.
@export var air_boost_multiplier: float = 0.25
## Air boost energy use = ground boost energy use x this value. 2.8 = 84 per second.
@export var air_boost_energy_multiplier: float = 2.8

@export_group("Air")
## Forward length of a directional jump at full charge, in meters (move key held while charging).
## Lower charges go shorter by the same fraction as their height: 33% charge = 3.3 m.
@export var directional_jump_full_distance: float = 10.0
## Multiplier on world gravity. Above 1 makes the mech fall faster and feel heavier.
@export var gravity_scale: float = 2.2
@export var max_fall_speed: float = 60.0

## Final stats from the loadout (set by MechAssembler). Null when the mech has no loadout.
var stats: MechStats
## Part HP and hitboxes (Phase 4). MechHealth sets it.
var health: MechHealth
## True after the mech is destroyed: no control, the wreck slides to a stop.
var is_wrecked: bool = false
## True while the mech lies on the ground after a fall (MechFall). No control until it gets up.
var is_fallen: bool = false
## One leg destroyed (PartBreaker): slower, no jump, falls over after a boost.
var one_leg: bool = false
## Side of the destroyed leg: -1 left, +1 right.
var broken_leg_side: float = 0.0
## False when the booster (backpack) is destroyed: no boost.
var can_boost: bool = true
## MechFall sets it (falls over, for example after a pile bunker miss on one leg).
var fall_control: MechFall
var is_boosting: bool = false
## True while the mech runs between the walk steps and the boost (Shift held).
var is_running: bool = false
## True while boosting in the air to steer.
var is_air_boosting: bool = false
## True from the end of a ground boost until the mech is back at walk speed or stopped.
var is_exiting_boost: bool = false
## True while the feet slide in a boost skid stop.
var is_skidding: bool = false
## True while the mech is entrenched (braced for a missile volley). It cannot move or boost.
var is_bracing: bool = false
var _brace_left: float = 0.0
## True during a blade lunge (the boosters push the mech toward the target).
var is_lunging: bool = false
var _lunge_direction: Vector3 = Vector3.ZERO
var _lunge_speed: float = 0.0
var _lunge_left: float = 0.0
## True while the current skid uses the brake thrusters (dodge hop ending).
var is_brake_skidding: bool = false
## Random side of the current skid: +1 = left, -1 = right. Set when a skid starts.
var skid_side: float = 1.0
## False = this skid ends without the Akira slide (back dodge).
var skid_akira: bool = true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_on_floor: bool = true
var _boost_on_ground: bool = false
var _walk_steps: int = 0
var _run_steps_done: int = 0
## Leg turn speed this frame, in radians per second (positive = left).
var leg_turn_rate: float = 0.0
var _exit_deceleration: float = 0.0
var _stop_deceleration: float = 0.0
var _landing_stop: bool = false
var _airborne: bool = false
var _in_exit_leap: bool = false
var _skid_stop_plan: PackedFloat32Array = PackedFloat32Array()
var _skid_slowdown: float = 9.4
var _skid_start_speed: float = 0.0
## World yaw where the torso (and the mech aim) points.
var _aim_yaw: float = 0.0
## True while the legs turn to follow the torso (standing: until they face it).
var _legs_following: bool = false
var _previous_aim_yaw: float = 0.0
var _turn_velocity: float = 0.0
var _turn_start_error: float = 0.0
## Time into the settle swings. Below 0 = no settle.
var _settle_time: float = -1.0
var _settle_sign: float = 0.0


func _ready() -> void:
	_aim_yaw = rotation.y
	footsteps.footstep.connect(_on_footstep)


func _physics_process(delta: float) -> void:
	if is_wrecked or is_fallen:
		_update_wreck(delta)
		return
	_previous_aim_yaw = _aim_yaw
	_brace_left = maxf(_brace_left - delta, 0.0)
	is_bracing = _brace_left > 0.0
	_update_boost(delta)
	_update_horizontal(delta)
	_update_vertical(delta)
	_turn_legs(delta)
	_turn_torso(delta)
	_clamp_torso_aim()
	var fall_speed := -velocity.y
	var velocity_before := velocity
	move_and_slide()
	_check_bump(velocity_before)
	_check_landing(fall_speed)


## Bodies this mech's own weapons and aim must not hit: its body and its hitboxes.
func get_hit_exclude() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	if health != null:
		rids.append_array(health.get_hitbox_rids())
	return rids


## A fallen or wrecked mech slides to a stop and falls with gravity.
func _update_wreck(delta: float) -> void:
	is_boosting = false
	is_lunging = false
	var slide := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, fallen_slide_deceleration * delta)
	velocity.x = slide.x
	velocity.z = slide.y
	velocity.y = maxf(velocity.y - _gravity * gravity_scale * delta, -max_fall_speed)
	var fall_speed := -velocity.y
	move_and_slide()
	# A wreck or fallen mech in the air still tells when it lands (MechFall waits for it).
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(fall_speed)
	_was_on_floor = on_floor


## MechFall: the mech falls over (it keeps its speed and slides).
func start_fall() -> void:
	is_fallen = true
	is_boosting = false
	is_running = false
	is_skidding = false
	is_brake_skidding = false
	is_exiting_boost = false
	is_lunging = false


## MechFall: turns the whole mech (legs and torso) to face this yaw, with no turn animation.
## The camera does not follow it (MechCameraRig free look while the mech is down); after the get-up
## the torso and legs turn toward the camera aim.
func set_heading(yaw: float) -> void:
	rotation.y = yaw
	_aim_yaw = yaw
	_previous_aim_yaw = yaw


## MechFall: the mech is up again.
func end_fall() -> void:
	is_fallen = false
	velocity = Vector3.ZERO


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Uses the short normal stop instead of the 3 landing steps (for example after a dodge hop).
func cancel_landing_steps() -> void:
	_landing_stop = false
	_stop_deceleration = 0.0


## World yaw where the torso and the mech aim point.
func get_aim_yaw() -> float:
	return _aim_yaw


## Torso yaw between physics frames, for smooth camera motion on fast screens.
func get_aim_yaw_interpolated() -> float:
	var step := wrapf(_aim_yaw - _previous_aim_yaw, -PI, PI)
	return _previous_aim_yaw + step * Engine.get_physics_interpolation_fraction()


## Torso twist from the legs, in radians. Positive = left.
func get_torso_twist() -> float:
	return wrapf(_aim_yaw - rotation.y, -PI, PI)


## Entrenches the mech for this many seconds (missile volley at locked targets).
func brace(seconds: float) -> void:
	_brace_left = maxf(_brace_left, seconds)
	is_bracing = true


## Blade lunge: moves the mech along direction at speed for distance meters (no steering).
## At the end the mech keeps a third of the speed and slows down normally.
func start_lunge(direction: Vector3, speed: float, distance: float) -> void:
	_lunge_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_lunge_speed = speed
	_lunge_left = distance
	is_lunging = distance > 0.05
	is_skidding = false
	is_brake_skidding = false


## Starts a skid stop: the feet plant and slide, then heavy steps. The body turns and rolls to a
## random side. Used by the boost exit and at the end of a dodge hop.
## stop_strides: stride lengths of the steps after the slide (empty = skid_stop_strides).
## slowdown: skid slowdown in m/s per second (0 = skid_deceleration).
## boost_brake: true when small thrusters help to brake (BrakeThrusters shows their fire).
func start_skid(stop_strides: PackedFloat32Array = PackedFloat32Array(), slowdown: float = 0.0,
		boost_brake: bool = false, akira: bool = true) -> void:
	skid_akira = akira
	_skid_stop_plan = stop_strides if not stop_strides.is_empty() else skid_stop_strides
	_skid_slowdown = slowdown if slowdown > 0.0 else skid_deceleration
	is_brake_skidding = boost_brake
	_skid_start_speed = get_horizontal_speed()
	is_exiting_boost = true
	_exit_deceleration = 0.0
	_stop_deceleration = 0.0
	is_skidding = true
	skid_side = 1.0 if randf() < 0.5 else -1.0


## 0 at the skid start, 1 at the skid end (by speed).
func get_skid_progress() -> float:
	var span := _skid_start_speed - skid_end_speed
	if span <= 0.01:
		return 1.0
	return clampf((_skid_start_speed - get_horizontal_speed()) / span, 0.0, 1.0)


func get_boost_speed() -> float:
	return walk_speed * boost_speed_multiplier


## True after the run steps, so boost can start.
## Boost can start: at once when the mech already moves (since 4a.6), or after the walk and run
## steps from a standstill.
func is_boost_ready() -> bool:
	return get_horizontal_speed() >= boost_ready_speed or _run_steps_done >= run_steps


## Steps left before boost can start (walk steps if needed, plus run steps).
func get_walk_steps_left() -> int:
	if is_boost_ready():
		return 0
	var walk_left := maxi(boost_start_steps - _walk_steps, 0)
	return walk_left + maxi(run_steps - _run_steps_done, 0)


func get_run_speed() -> float:
	return walk_speed * run_speed_multiplier


func _on_footstep(_strength: float) -> void:
	_walk_steps += 1
	if is_running:
		_run_steps_done += 1


func _update_boost(delta: float) -> void:
	if get_horizontal_speed() < footsteps.min_speed and is_on_floor():
		_walk_steps = 0
	var was_ground_boosting := is_boosting and _boost_on_ground
	var has_input := input.move_direction.length_squared() > 0.01
	var wants_boost := false
	if is_on_floor():
		wants_boost = input.boost_held and has_input and is_boost_ready() \
				and not landing_recovery.is_recovering() and not jump_charge.is_charging and not kneel.is_kneeling \
				and not dodge.is_busy() and not is_bracing
	else:
		# Shift + a move key fires the boosters in the air. A move key alone uses free steering.
		wants_boost = input.boost_held and has_input
	var energy_rate := boost_energy_per_second if is_on_floor() else boost_energy_per_second * air_boost_energy_multiplier
	is_boosting = wants_boost and can_boost and energy.try_drain(energy_rate * delta)
	# Shift held after the walk steps: run until boost is ready.
	is_running = is_on_floor() and not is_boosting and input.boost_held and has_input \
			and _walk_steps >= boost_start_steps and not landing_recovery.is_recovering() \
			and not jump_charge.is_charging and not kneel.is_kneeling
	if not is_running and not is_boosting:
		# The run steps start again from zero before the next boost.
		_run_steps_done = 0
	is_air_boosting = is_boosting and not is_on_floor()
	_boost_on_ground = is_boosting and is_on_floor()
	if is_boosting:
		is_exiting_boost = false
	elif was_ground_boosting and is_on_floor() and get_horizontal_speed() > walk_speed * 1.05 \
			and not dodge.is_dodging:
		is_exiting_boost = true
		_exit_deceleration = 0.0
		_stop_deceleration = 0.0
		if boost_exit_style == BoostExit.SKID:
			start_skid()
		else:
			# One leap forward that lands on one leg, then medium and small steps to slow down.
			_in_exit_leap = true
			velocity.y = boost_exit_leap_velocity
		boost_exit_step.emit()


func _update_horizontal(delta: float) -> void:
	var recovering := landing_recovery.is_recovering()
	# Charging a jump, kneeling, or recovering from a dodge: the mech stands still.
	var charging := jump_charge.is_charging or kneel.is_kneeling or dodge.is_busy() or is_bracing
	var wish := Vector3.ZERO if recovering or charging else input.move_direction
	var has_input := wish.length_squared() > 0.001
	# A jump that starts this frame counts as air.
	var on_floor := is_on_floor() and velocity.y <= 0.0
	var speed := get_horizontal_speed()

	if is_lunging:
		var step := _lunge_speed * delta
		_lunge_left -= step
		var push := _lunge_direction * _lunge_speed
		if _lunge_left <= 0.0:
			is_lunging = false
			push *= 0.33
		velocity.x = push.x
		velocity.z = push.z
		return

	if not on_floor:
		if not _airborne:
			# First air frame (walking off an edge). Jumps start the flight at launch.
			_start_flight()
		# Free steering or air boost. No key = momentum only.
		# No steering during the boost exit leap or a dodge hop.
		var steer_wish := Vector3.ZERO if _in_exit_leap or dodge.is_dodging else wish
		var boost_speed := get_boost_speed() * air_boost_multiplier if is_boosting else 0.0
		var steered := air_steer.steer(steer_wish, delta, boost_speed, boost_acceleration * air_boost_multiplier)
		velocity.x = steered.x
		velocity.z = steered.z
		return

	if is_skidding:
		_update_skid(delta, has_input)
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
		target = _limit_for_shield(wish * get_boost_speed())
		rate = boost_acceleration
	elif is_running:
		target = _limit_for_shield(wish * get_run_speed())
		rate = acceleration
	else:
		target = _limit_for_shield(wish * _get_walk_speed(wish))
		rate = _get_exit_deceleration() if is_exiting_boost and on_floor else acceleration

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if has_input:
		_stop_deceleration = 0.0
		_landing_stop = false
		if is_exiting_boost and on_floor and speed <= walk_speed + 0.05:
			is_exiting_boost = false
	elif speed < 0.05:
		_stop_deceleration = 0.0
		is_exiting_boost = false
		_landing_stop = false


## Skid stop: the feet slide and the mech slows fast. At the end: heavy steps to a stop,
## or back to walking if a move key is held.
func _update_skid(delta: float, has_input: bool) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(Vector3.ZERO, _skid_slowdown * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if horizontal.length() > skid_end_speed:
		return
	is_skidding = false
	is_brake_skidding = false
	_stop_deceleration = 0.0
	if has_input:
		is_exiting_boost = false
	else:
		footsteps.start_stride_plan(_skid_stop_plan)


## Limits a target velocity while the shield is up. Blends in as the shield comes up.
func _limit_for_shield(target: Vector3) -> Vector3:
	if shield == null or shield.amount <= 0.0:
		return target
	var speed := target.length()
	var limit := lerpf(speed, minf(speed, shield.get_speed_limit()), shield.amount)
	return target.limit_length(limit)


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
## 2 from walk, 3 after landing from a jump with sideways speed, the boost exit strides after a boost.
## Slow walks take fewer steps.
func _get_stop_deceleration() -> float:
	if _stop_deceleration <= 0.0:
		var speed := get_horizontal_speed()
		if footsteps.has_stride_plan():
			_stop_deceleration = _get_deceleration_for_plan(0.0)
			return _stop_deceleration
		var steps := walk_stop_steps
		if _landing_stop:
			steps = landing_stop_steps
		else:
			steps = mini(roundi(walk_stop_steps * pow(speed / walk_speed, 2.0)), walk_stop_steps)
		if steps < 1 or speed < footsteps.min_speed:
			_stop_deceleration = deceleration
		else:
			_stop_deceleration = _get_deceleration_for_steps(steps, 0.0)
	return _stop_deceleration


## Slowdown that brings boost speed down to walk speed over the boost exit strides.
func _get_exit_deceleration() -> float:
	if _exit_deceleration <= 0.0:
		_exit_deceleration = _get_deceleration_for_plan(walk_speed)
	return _exit_deceleration


## Steady slowdown to end_speed over the planned strides that are left.
func _get_deceleration_for_plan(end_speed: float) -> float:
	var speed := get_horizontal_speed()
	var distance := footsteps.get_stride_plan_distance()
	return maxf((speed * speed - end_speed * end_speed) / (2.0 * maxf(distance, 0.5)), 0.3)


func _update_vertical(delta: float) -> void:
	var gravity := _gravity * gravity_scale
	if is_on_floor():
		var height := jump_charge.take_launch_height()
		if height > 0.0:
			# Launch speed that reaches the charged height.
			# The half-frame term cancels the extra rise from the physics frame step.
			velocity.y = sqrt(2.0 * gravity * height) - 0.5 * gravity * delta
			# Sideways speed that covers the directional distance in the time of flight.
			var flight_time := 2.0 * sqrt(2.0 * height / gravity)
			var distance := directional_jump_full_distance * height / jump_charge.full_height
			var sideways := jump_charge.launch_direction * (distance / flight_time)
			velocity.x = sideways.x
			velocity.z = sideways.z
			_start_flight()
			jumped.emit()
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


func _start_flight() -> void:
	_airborne = true
	air_steer.begin_flight()


## Turns the torso aim toward the camera aim. The last part of each turn is slower.
## At the end of a turn the aim settles: it swings past the aim, swings to the other side,
## then snaps onto the aim and locks in. The torso aim stays inside the torso twist limits.
func _turn_torso(delta: float) -> void:
	var error := wrapf(input.aim_yaw - _aim_yaw, -PI, PI)
	var gap := absf(error)
	if _settle_time >= 0.0:
		if gap <= deg_to_rad(turn_settle_swing_deg * 2.0 + 1.0):
			_update_settle(delta)
			return
		# The aim moved away: a new turn starts.
		_settle_time = -1.0
	if gap < deg_to_rad(0.1) and _turn_velocity == 0.0:
		_turn_start_error = 0.0
	_turn_start_error = maxf(_turn_start_error, gap)

	var max_speed := deg_to_rad(turn_speed_deg)
	if gap < _turn_start_error * turn_slow_zone:
		max_speed *= turn_slow_multiplier
	var accel := deg_to_rad(turn_acceleration_deg)
	# Brake in time to stop on the aim.
	var desired := signf(error) * minf(max_speed, sqrt(2.0 * accel * gap))
	_turn_velocity = move_toward(_turn_velocity, desired, accel * delta)

	var step := _turn_velocity * delta
	if signf(step) == signf(error) and absf(step) >= gap:
		_aim_yaw = wrapf(_aim_yaw + error, -PI, PI)
		_turn_velocity = 0.0
		if turn_settle_swing_deg > 0.0 and _turn_start_error >= deg_to_rad(turn_settle_min_turn_deg):
			_settle_time = 0.0
			_settle_sign = signf(error)
		_turn_start_error = 0.0
	else:
		_aim_yaw = wrapf(_aim_yaw + step, -PI, PI)


## Plays the settle swings relative to the live aim: past the aim, to the other side, then snap to the aim.
func _update_settle(delta: float) -> void:
	_settle_time += delta
	var swing := deg_to_rad(turn_settle_swing_deg) * _settle_sign
	var first := turn_settle_first_time
	var second := first + turn_settle_second_time
	var end := second + turn_settle_snap_time
	var offset := 0.0
	if _settle_time < first:
		offset = lerpf(0.0, swing, smoothstep(0.0, 1.0, _settle_time / first))
	elif _settle_time < second:
		offset = lerpf(swing, -swing, smoothstep(0.0, 1.0, (_settle_time - first) / turn_settle_second_time))
	elif _settle_time < end:
		offset = lerpf(-swing, 0.0, (_settle_time - second) / turn_settle_snap_time)
	else:
		_settle_time = -1.0
	_aim_yaw = wrapf(input.aim_yaw + offset, -PI, PI)


## The legs (the mech root) turn to face where the torso faces, at a steady speed (slower when
## standing still). Moving, they always follow. Standing, they start to turn when the torso is more
## than legs_follow_standing_deg off, then turn all the way (steps in place).
func _turn_legs(delta: float) -> void:
	leg_turn_rate = 0.0
	if landing_recovery.is_recovering() or kneel.is_kneeling or dodge.is_busy():
		return
	var error := wrapf(_aim_yaw - rotation.y, -PI, PI)
	var moving := get_horizontal_speed() > footsteps.min_speed
	if moving or absf(error) > deg_to_rad(legs_follow_standing_deg):
		_legs_following = true
	if not _legs_following:
		return
	var speed := deg_to_rad(leg_turn_speed_deg if moving else leg_turn_speed_standing_deg)
	var step := clampf(error, -speed * delta, speed * delta)
	leg_turn_rate = step / delta
	rotation.y = wrapf(rotation.y + step, -PI, PI)
	if absf(error - step) < deg_to_rad(0.5):
		_legs_following = moving


## Keeps the torso aim inside the twist limits of the current leg heading.
func _clamp_torso_aim() -> void:
	var twist := clampf(wrapf(_aim_yaw - rotation.y, -PI, PI),
			-deg_to_rad(torso_twist_right_deg), deg_to_rad(torso_twist_left_deg))
	_aim_yaw = wrapf(rotation.y + twist, -PI, PI)


## Bounces the mech off walls (buildings, platforms, map edge), then slows it down.
func _check_bump(velocity_before: Vector3) -> void:
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if absf(normal.y) > 0.5:
			continue  # Floor or ceiling.
		normal.y = 0.0
		normal = normal.normalized()
		var horizontal := Vector3(velocity_before.x, 0.0, velocity_before.z)
		var into_wall := -horizontal.dot(normal)
		if into_wall < bump_min_speed:
			continue
		var impact := clampf((into_wall - bump_min_speed) / (bump_full_speed - bump_min_speed), 0.0, 1.0)
		var restitution := lerpf(bump_restitution_min, bump_restitution_max, impact)
		var keep := 1.0 - bump_slowdown_max * impact
		var bounced := (horizontal + normal * into_wall * (1.0 + restitution)) * keep
		velocity.x = bounced.x
		velocity.z = bounced.z
		_stop_deceleration = 0.0
		_exit_deceleration = 0.0
		if not is_on_floor():
			air_steer.rebase()
		bumped.emit(into_wall)
		return


func _check_landing(fall_speed: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		if _in_exit_leap:
			# Landed the boost exit leap on one leg: 2 medium steps, then 2 small steps.
			_in_exit_leap = false
			footsteps.start_stride_plan(boost_exit_strides)
			_exit_deceleration = 0.0
		else:
			is_skidding = false
			# Landing with sideways speed from a jump: walk it out in a set number of steps.
			_landing_stop = get_horizontal_speed() > footsteps.min_speed
			is_exiting_boost = false
		_stop_deceleration = 0.0
		landed.emit(fall_speed)
	if on_floor:
		_airborne = false
	_was_on_floor = on_floor
