class_name MechDodge
extends Node
## Double tap Space for a dodge roll: the mech dives head-first toward the chosen direction, spins one
## full turn around its own length (a barrel roll), then comes back up onto its feet.
## Directions: A / D = side, W = forward, S or no key = back. Costs energy.
## The dive and roll are visual (the Roll node). The collision body only slides along the ground.

signal dodge_started
signal dodge_ended

@export var mech: Mech
@export var input: MechInput
@export var energy: MechEnergy
@export var landing_recovery: MechLandingRecovery
@export var kneel: MechKneel
## The node that rolls (between Visual and Upper).
@export var roll: Node3D
## Two Space presses closer than this (seconds) start a dodge.
@export var double_tap_window: float = 0.3
## Dodge length, in meters.
@export var distance: float = 14.0
## Dodge time, in seconds. The speed starts high and ends at zero.
@export var duration: float = 0.75
@export var energy_cost: float = 25.0
## After the dodge the mech cannot move for this long, in seconds.
@export var recovery_time: float = 0.25
## Height of the body center above the feet, in meters.
@export var body_center_height: float = 5.0
## Body center height while diving and rolling, in meters. About half the shoulder width,
## so the shoulders do not cut into the ground while the body spins.
@export var roll_center_height: float = 4.2
## How far the body leans into the dive, in degrees (90 = flat).
@export var dive_angle_deg: float = 80.0
## Parts of the dodge time: the dive ends at dive_end, the roll ends at roll_end, then the body rises.
@export_range(0.0, 1.0) var dive_end: float = 0.25
@export_range(0.0, 1.0) var roll_end: float = 0.75

var is_dodging: bool = false
## World direction of the current dodge.
var direction: Vector3 = Vector3.ZERO

var _clock: float = 0.0
var _last_press: float = -10.0
var _time: float = 0.0
var _recover_left: float = 0.0
## Axis the body leans around for the dive (the top turns toward the dodge direction).
var _dive_axis: Vector3 = Vector3.FORWARD
var _suppress_jump: bool = false


func _ready() -> void:
	# Before the jump charge (-5) and the Mech (0).
	process_physics_priority = -6


## True while dodging or recovering. The mech cannot move, boost, or turn.
func is_busy() -> bool:
	return is_dodging or _recover_left > 0.0


## True while the Space press that started the dodge is still held. The jump charge waits.
func blocks_jump() -> bool:
	return is_busy() or _suppress_jump


## Dodge speed now, in m/s. Starts at 2x the average speed and falls to zero.
func get_speed() -> float:
	var progress := clampf(_time / duration, 0.0, 1.0)
	return distance / duration * 2.0 * (1.0 - progress)


## 0 to 1: how much the legs tuck in (most at the middle of the roll).
func get_tuck() -> float:
	if not is_dodging:
		return 0.0
	return sin(clampf(_time / duration, 0.0, 1.0) * PI)


func _physics_process(delta: float) -> void:
	_clock += delta
	_recover_left = maxf(_recover_left - delta, 0.0)
	if not input.jump_held:
		_suppress_jump = false
	if input.jump_pressed:
		if _clock - _last_press <= double_tap_window and _can_start():
			_start()
		_last_press = _clock
	if is_dodging:
		_time += delta
		_update_roll()
		if _time >= duration:
			is_dodging = false
			roll.transform = Transform3D.IDENTITY
			_recover_left = recovery_time
			dodge_ended.emit()


func _can_start() -> bool:
	return mech.is_on_floor() and not is_busy() and not landing_recovery.is_recovering() \
			and not kneel.is_kneeling and not mech.is_skidding and energy.current >= energy_cost


func _start() -> void:
	energy.try_drain(energy_cost)
	# Direction in the leg frame: -Z forward, +X right.
	var local := Vector3(0.0, 0.0, 1.0)  # No key: back.
	if input.turn_input > 0.5:
		local = Vector3(-1.0, 0.0, 0.0)  # A: left.
	elif input.turn_input < -0.5:
		local = Vector3(1.0, 0.0, 0.0)  # D: right.
	elif input.forward_held:
		local = Vector3(0.0, 0.0, -1.0)  # W: forward.
	direction = (mech.global_basis * local).normalized()
	# Dive axis: the top of the body leans toward the move direction.
	_dive_axis = Vector3.UP.cross(local).normalized()
	is_dodging = true
	_time = 0.0
	_last_press = -10.0
	_suppress_jump = true
	dodge_started.emit()


func _update_roll() -> void:
	var progress := clampf(_time / duration, 0.0, 1.0)
	# Dive: 0 to 1 while leaning in, 1 during the roll, 1 to 0 while rising.
	var dive := 1.0
	if progress < dive_end:
		dive = smoothstep(0.0, dive_end, progress)
	elif progress > roll_end:
		dive = 1.0 - smoothstep(roll_end, 1.0, progress)
	# Barrel roll: one full turn around the body's own length, during the middle part.
	var spin := TAU * smoothstep(dive_end, roll_end, progress)
	var turn := Basis(_dive_axis, deg_to_rad(dive_angle_deg) * dive) * Basis(Vector3.UP, spin)
	# Keep the body center on a path that drops a little while diving, then rises again.
	var center := Vector3(0.0, lerpf(body_center_height, roll_center_height, dive), 0.0)
	roll.transform = Transform3D(turn, center - turn * Vector3(0.0, body_center_height, 0.0))
