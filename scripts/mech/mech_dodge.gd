class_name MechDodge
extends Node
## Double tap Space for a dodge hop: a quick, low hop in the chosen direction.
## Directions: A / D = side, W = forward, S or no key = back. While boosting: always forward.
## While boosting, the first Space press waits for the double tap before the jump charge starts,
## so the boost does not stop. Costs energy.
## In the air the mech leans into the hop and tucks its legs a little. It lands in a small crouch and
## springs upright. Ending: a short skid (feet slide with dust, two small brake thrusters fire),
## then two steps to a stop.
## No landing delay.

signal dodge_started
signal dodge_ended

@export var mech: Mech
@export var input: MechInput
@export var energy: MechEnergy
@export var landing_recovery: MechLandingRecovery
@export var kneel: MechKneel
## Two Space presses closer than this (seconds) start a dodge.
@export var double_tap_window: float = 0.3
## Hop length, in meters.
@export var distance: float = 11.9
## Hop height, in meters.
@export var hop_height: float = 1.5
@export var energy_cost: float = 25.0
## Speed kept in the hop direction at the landing (m/s). The skid slows the mech down from it.
@export var landing_speed: float = 10.0
## Skid slowdown in m/s per second. The brake thrusters make it stronger than the boost skid (9.4):
## 23.5 gives a skid 60% shorter (about 1.8 m from 10 m/s down to 4 m/s).
@export var skid_slowdown: float = 23.5
## Stride lengths (meters) of the two steps after the skid.
@export var stop_strides: PackedFloat32Array = PackedFloat32Array([1.5, 1.5])
## After the landing the mech cannot move for this long, in seconds.
@export var recovery_time: float = 0.2

@export_group("Recovery")
## The mech leans into the hop and lands in a small crouch with the torso leaned toward the
## hop direction. Then one damped spring brings the body upright.
@export var recover_lean_deg: float = 10.0
## Knee crouch at the landing, in degrees of hip bend (knees bend twice as much).
@export var recover_crouch_deg: float = 20.0
## Spring speed (swings per second). Lower = slower recovery.
@export var recover_frequency: float = 1.2
## Spring damping. Lower = more swing past upright.
@export_range(0.05, 1.0) var recover_damping: float = 0.45
@export_group("")

var is_dodging: bool = false
## World direction of the current dodge.
var direction: Vector3 = Vector3.ZERO

var _clock: float = 0.0
var _last_press: float = -10.0
var _air_time: float = 0.0
var _flight_time: float = 1.0
var _recover_left: float = 0.0
var _suppress_jump: bool = false
## Dodge direction in the leg frame (-Z forward, +X right).
var _local_direction: Vector3 = Vector3.BACK
var _recover := AimSpring.new(0.0)
var _recovering: bool = false
## Time left in the double tap window after a Space press during a boost.
var _boost_tap_left: float = 0.0


func _ready() -> void:
	# Before the jump charge (-5) and the Mech (0).
	process_physics_priority = -6
	mech.landed.connect(_on_landed)


## True while hopping or recovering. The mech cannot move, boost, or turn.
func is_busy() -> bool:
	return is_dodging or _recover_left > 0.0


## True while the Space press that started the dodge is still held, or while a boost waits for
## the second tap. The jump charge waits.
func blocks_jump() -> bool:
	return is_busy() or _suppress_jump or _boost_tap_left > 0.0


## True while the hop or its recovery spring moves the body. InertiaSway pauses then.
func is_animating() -> bool:
	return is_dodging or _recovering


## 0 to 1: how much the legs tuck in (most at the top of the hop).
func get_tuck() -> float:
	if not is_dodging:
		return 0.0
	return 0.5 * sin(_get_air_progress() * PI)


## Recovery pose amount: grows toward 1 while the hop comes down, then springs to 0 after the
## landing (it can go a little below 0 on the swing past upright).
func get_recovery_pose() -> float:
	if is_dodging:
		return smoothstep(0.0, 1.0, _get_air_progress())
	return _recover.value


## Torso lean toward the hop direction now, in degrees: x = forward lean, y = roll (head left).
func get_recovery_lean() -> Vector2:
	var amount := get_recovery_pose() * recover_lean_deg
	return Vector2(-_local_direction.z * amount, -_local_direction.x * amount)


func _physics_process(delta: float) -> void:
	_clock += delta
	_recover_left = maxf(_recover_left - delta, 0.0)
	if is_dodging:
		_air_time += delta
	if _recovering:
		_recover.update(0.0, recover_frequency, recover_damping, 10.0, delta)
		if absf(_recover.value) < 0.002 and absf(_recover.velocity) < 0.01:
			_recover.value = 0.0
			_recovering = false
	_boost_tap_left = maxf(_boost_tap_left - delta, 0.0)
	if not input.jump_held:
		_suppress_jump = false
	if input.jump_pressed and mech.is_boosting and mech.is_on_floor() and _boost_tap_left <= 0.0:
		_boost_tap_left = double_tap_window
	if input.jump_pressed:
		if _clock - _last_press <= double_tap_window and _can_start():
			_start()
		_last_press = _clock


func _get_air_progress() -> float:
	return clampf(_air_time / _flight_time, 0.0, 1.0)


func _can_start() -> bool:
	return mech.is_on_floor() and not is_busy() and not landing_recovery.is_recovering() \
			and not kneel.is_kneeling and not mech.is_skidding and energy.current >= energy_cost


func _start() -> void:
	energy.try_drain(energy_cost)
	# Direction in the leg frame: -Z forward, +X right.
	var local := Vector3(0.0, 0.0, 1.0)  # No key: back.
	if mech.is_boosting:
		local = Vector3(0.0, 0.0, -1.0)  # Boosting: forward.
	elif input.turn_input > 0.5:
		local = Vector3(-1.0, 0.0, 0.0)  # A: left.
	elif input.turn_input < -0.5:
		local = Vector3(1.0, 0.0, 0.0)  # D: right.
	elif input.forward_held:
		local = Vector3(0.0, 0.0, -1.0)  # W: forward.
	_local_direction = local
	direction = (mech.global_basis * local).normalized()
	# Launch speeds for the hop height and length.
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * mech.gravity_scale
	var up_speed := sqrt(2.0 * gravity * hop_height)
	_flight_time = 2.0 * up_speed / gravity
	var side_speed := distance / _flight_time
	mech.velocity = direction * side_speed + Vector3.UP * up_speed
	is_dodging = true
	_air_time = 0.0
	_recovering = false
	_last_press = -10.0
	_boost_tap_left = 0.0
	_suppress_jump = true
	dodge_started.emit()


func _on_landed(_fall_speed: float) -> void:
	if not is_dodging:
		return
	is_dodging = false
	# Keep some speed in the hop direction. The braked skid slows it down, then two steps to a stop.
	var keep := direction * landing_speed
	mech.velocity.x = keep.x
	mech.velocity.z = keep.z
	mech.cancel_landing_steps()
	mech.start_skid(stop_strides, skid_slowdown, true)
	_recover_left = recovery_time
	# Start the recovery spring from the full landing pose.
	_recover.value = 1.0
	_recover.velocity = 0.0
	_recovering = true
	dodge_ended.emit()
