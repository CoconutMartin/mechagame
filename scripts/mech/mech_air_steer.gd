class_name MechAirSteer
extends Node
## Free steering in the air, with no energy cost.
## A move key can shift the landing point by up to budget meters in any direction.
## When the budget is used, more steering fires the boosters and uses energy (Mech handles that).

@export var mech: Mech
## Largest free change of the landing point, in meters.
@export var budget: float = 5.0
## Top free steering speed, in m/s.
@export var max_speed: float = 8.0
## How fast the free steering speed changes (m/s per second).
@export var acceleration: float = 10.0
## Extra seconds added to the time left in the air, so the steering speed does not drop just before landing.
@export var landing_margin: float = 0.15

var _base_velocity: Vector3 = Vector3.ZERO
var _drift: Vector3 = Vector3.ZERO
var _remaining: float = 0.0
var _launch_y: float = 0.0


## Call when the mech leaves the ground.
func begin_flight() -> void:
	_base_velocity = Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	_drift = Vector3.ZERO
	_remaining = budget
	_launch_y = mech.global_position.y


## Call after the boosters change the velocity, so free steering starts from the new velocity.
func rebase() -> void:
	_base_velocity = Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	_drift = Vector3.ZERO


func has_budget() -> bool:
	return _remaining > 0.05


func get_remaining() -> float:
	return _remaining


## Returns the new horizontal velocity for this frame.
func steer(wish: Vector3, delta: float) -> Vector3:
	# Spread the budget over the time left, so it lasts until the landing.
	# The small margin keeps the speed up in the last frames. The mech lands with this speed.
	var allowed := minf(max_speed, _remaining / (_get_time_to_land() + landing_margin))
	if wish.length_squared() > 0.001:
		_drift = _drift.move_toward(wish * allowed, acceleration * delta)
		_drift = _drift.limit_length(allowed)
	_remaining = maxf(_remaining - _drift.length() * delta, 0.0)
	return _base_velocity + _drift


## Time until the mech falls back to its launch height.
func _get_time_to_land() -> float:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * mech.gravity_scale
	var height := maxf(mech.global_position.y - _launch_y, 0.0)
	var up := mech.velocity.y
	return (up + sqrt(up * up + 2.0 * gravity * height)) / gravity
