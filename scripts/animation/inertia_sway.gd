class_name InertiaSway
extends Node
## Body inertia: the torso reacts to speed changes and leg turns, then swings back on springs.
## Slowing down leans it forward, speeding up leans it back, turns roll it to the side, and leg turns
## make it lag behind. When a movement ends, the springs let it sway to rest instead of stopping hard.
## TorsoPose adds these values to the torso.

@export var mech: Mech
## The inertia sway pauses while the dodge and its recovery move the body.
@export var dodge: MechDodge
## After a pause, the inertia sway fades back in over this time, in seconds.
@export var fade_in_time: float = 0.5
## Lean per m/s² of forward speed change, in degrees. Slowing down = lean forward.
@export var lean_per_accel_deg: float = 1.2
## Roll per m/s² of sideways speed change, in degrees.
@export var roll_per_accel_deg: float = 1.0
## Torso lag behind the leg turn, in seconds of turn (0.1 s x 60 deg/s = 6 deg).
@export var turn_lag_seconds: float = 0.1
## Largest inertia lean and roll, in degrees.
@export var max_angle_deg: float = 10.0
## Spring speed (swings per second). Lower = slower sway.
@export var frequency: float = 1.3
## Spring damping. Lower = more swings. 1.0 = no swing past rest.
@export_range(0.05, 1.0) var damping: float = 0.35
## Smoothing of the measured speed change (higher = follows faster).
@export var accel_smoothing: float = 8.0

## Inertia angles in degrees. Lean: positive = forward. Roll: positive = head to the left.
## Yaw: positive = torso turned left.
var lean_deg: float = 0.0
var roll_deg: float = 0.0
var yaw_deg: float = 0.0

var _lean := AimSpring.new(0.0)
var _roll := AimSpring.new(0.0)
var _yaw := AimSpring.new(0.0)
var _last_velocity: Vector3 = Vector3.ZERO
var _accel: Vector3 = Vector3.ZERO
var _fade: float = 1.0


func _ready() -> void:
	# After the Mech moves, before TorsoPose.
	process_physics_priority = 2


func _physics_process(delta: float) -> void:
	var velocity := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	var raw_accel := (velocity - _last_velocity) / delta
	_last_velocity = velocity
	if dodge != null and dodge.is_animating():
		_fade = 0.0
		raw_accel = Vector3.ZERO
		_accel = Vector3.ZERO
	else:
		_fade = move_toward(_fade, 1.0, delta / fade_in_time)
	_accel = _accel.lerp(raw_accel, 1.0 - exp(-accel_smoothing * delta))
	# Speed change in the leg frame: -Z forward, +X right.
	var local := mech.global_basis.inverse() * _accel
	var limit := max_angle_deg
	var lean_target := clampf(local.z * lean_per_accel_deg, -limit, limit) * _fade
	var roll_target := clampf(local.x * roll_per_accel_deg, -limit, limit) * _fade
	var yaw_target := clampf(-rad_to_deg(mech.leg_turn_rate) * turn_lag_seconds, -limit, limit) * _fade
	_lean.update(lean_target, frequency, damping, 90.0, delta)
	_roll.update(roll_target, frequency, damping, 90.0, delta)
	_yaw.update(yaw_target, frequency, damping, 90.0, delta)
	lean_deg = _lean.value
	roll_deg = _roll.value
	yaw_deg = _yaw.value
