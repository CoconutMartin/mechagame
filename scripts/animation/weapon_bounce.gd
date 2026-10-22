class_name WeaponBounce
extends Node
## A two-hand weapon at rest swings with the body's motion (user request 2026-10-13): it lags behind
## when the torso speeds up, slows down or bobs with the steps (a spring pulls it back), and it bounces
## off the body: it may come no closer to the chest than body_gap, and there its speed toward the body
## turns around (restitution). WeaponPose adds offset to the weapon; the arms follow the weapon (their
## IK targets are on it). Fades out while aiming.

## The weapon frame node (torso space: -Z forward, so +Z is toward the body).
@export var torso: Node3D
@export var weapons: WeaponController
@export var weapon_pose: WeaponPose
## How much of the torso's acceleration pushes the weapon the other way (1 = a free weight).
@export var inertia: float = 0.6
## Spring back to the rest place (1 / s^2) and its damping (1 / s). Heavy and damped (user report
## 2026-10-22, "the left arm makes a pounding motion while walking"): damping 11 is about critical for
## stiffness 30 (2 x sqrt(30)), so the weapon and the left hand on it settle without a bounce.
@export var stiffness: float = 30.0
@export var damping: float = 11.0
## How far the weapon may come toward the body (meters, the rest gap), and the speed kept on a bounce.
@export var body_gap: float = 0.07
@export_range(0.0, 1.0) var restitution: float = 0.0
## Largest swing each way (meters, torso space: x along the body, y up and down, z away from the
## body). The weapon bounces at these limits too (the chest slopes and the legs are below it).
@export var max_swing: Vector3 = Vector3(0.04, 0.05, 0.2)
## Torso accelerations are smoothed over this time (seconds): the steps, not frame noise.
@export var smoothing: float = 0.12

## Offset of the weapon now (torso space).
var offset: Vector3 = Vector3.ZERO
var _speed: Vector3 = Vector3.ZERO
var _last_position: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _acceleration: Vector3 = Vector3.ZERO
var _started := false


func _ready() -> void:
	# Before WeaponPose (priority 5) reads the offset.
	process_physics_priority = 4


func _physics_process(delta: float) -> void:
	if torso == null or delta <= 0.0:
		return
	var position := torso.global_position
	if not _started:
		_started = true
		_last_position = position
		return
	var velocity := (position - _last_position) / delta
	var acceleration := (velocity - _last_velocity) / delta
	_last_position = position
	_last_velocity = velocity
	_acceleration = _acceleration.lerp(acceleration, clampf(delta / maxf(smoothing, delta), 0.0, 1.0))
	if not _active():
		offset = offset.move_toward(Vector3.ZERO, 2.0 * delta)
		_speed = Vector3.ZERO
		return
	var push := torso.global_basis.orthonormalized().inverse() * (-_acceleration * inertia)
	_speed += (push - offset * stiffness - _speed * damping) * delta
	offset += _speed * delta
	# The body: no closer than body_gap; the speed toward it bounces back. The same at the swing limits.
	var low := -max_swing
	var high := Vector3(max_swing.x, max_swing.y, minf(body_gap, max_swing.z))
	for axis in 3:
		if offset[axis] > high[axis] or offset[axis] < low[axis]:
			offset[axis] = clampf(offset[axis], low[axis], high[axis])
			if signf(_speed[axis]) == signf(offset[axis]):
				_speed[axis] = -_speed[axis] * restitution


## Swings only for a two-hand weapon, and less while aiming.
func amount() -> float:
	if weapon_pose == null:
		return 0.0
	return 1.0 - smoothstep(0.0, 1.0, weapon_pose.aim_amount)


func _active() -> bool:
	return weapons != null and weapons.right_weapon != null and weapons.two_handed_left_grip()
