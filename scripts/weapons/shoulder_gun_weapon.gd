class_name ShoulderGunWeapon
extends GunWeapon
## A gun on top of a shoulder (Shoulder Cannon, new mech; Q = left, E = right). The root is the turn
## point at the bottom of its mount; it turns to the mech aim point within its limits and fires while
## the key is held.

## Largest turn from the mount's rest direction, degrees.
@export var max_yaw_deg: float = 35.0
@export var max_pitch_up_deg: float = 30.0
@export var max_pitch_down_deg: float = 20.0
## Turn speed, degrees per second.
@export var turn_speed_deg: float = 120.0

var _rest: Transform3D
var _rested: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0


func _update(delta: float) -> void:
	_turn(delta)
	if trigger_held and can_use():
		_fire()


func _turn(delta: float) -> void:
	var parent := get_parent_node_3d()
	if parent == null:
		return
	if not _rested:
		_rest = transform
		_rested = true
	var target := _rest.affine_inverse() * parent.to_local(controller.mech_aim.aim_point)
	var muzzle_height := _muzzle.position.y
	var flat := Vector2(target.x, target.z).length()
	var yaw := clampf(atan2(-target.x, -target.z), -deg_to_rad(max_yaw_deg), deg_to_rad(max_yaw_deg))
	var pitch := clampf(atan2(target.y - muzzle_height, flat), -deg_to_rad(max_pitch_down_deg), deg_to_rad(max_pitch_up_deg))
	var step := deg_to_rad(turn_speed_deg) * delta
	_yaw = move_toward(_yaw, yaw, step)
	_pitch = move_toward(_pitch, pitch, step)
	transform = _rest * Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), Vector3.ZERO)
