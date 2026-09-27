class_name MechCameraRig
extends Node3D
## Over-the-shoulder camera. Stays behind the mech torso and turns with it.
## The mouse moves an aim target (yaw). The torso turns toward that target at its own turn speed,
## and the camera turns with the torso. Pitch follows the mouse on a spring.
## Node layout: MechCameraRig > Pitch > SpringArm3D > Camera3D.

@export var target: Node3D
## Height of the camera pivot above the mech's feet, in meters.
@export var pivot_height: float = 7.0
## Higher value = camera follows more tightly.
@export var follow_sharpness: float = 14.0
## Radians turned per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_deg: float = -27.5
@export var max_pitch_deg: float = 15.0

@export_group("Aim Spring")
## Oscillations per second. Lower = slower, heavier aim.
@export var aim_frequency: float = 1.75
## 1.0 = no overshoot. 0.5 gives about 14% overshoot (a fast 30 degree flick passes by about 4 degrees).
@export_range(0.1, 1.0) var aim_damping: float = 0.5
## Largest gap between the camera and the mouse aim, in degrees.
@export var max_aim_lag_deg: float = 25.0

## Mouse aim target in radians, after the spring. The torso turns toward this yaw.
var yaw: float = 0.0
var pitch: float = 0.0
## Multiplier on mouse sensitivity. CameraAds lowers it while aiming.
var sensitivity_scale: float = 1.0

var _target_yaw: float = 0.0

@export_group("Mech Limits")
## Camera drop when the mech kneels fully, in meters.
@export var kneel_height_drop: float = 1.74
var _target_pitch: float = 0.0
var _yaw_spring := AimSpring.new()
var _pitch_spring := AimSpring.new()

@onready var _pitch_node: Node3D = $Pitch


func _ready() -> void:
	top_level = true
	# This node moves in _process, so it must not use physics interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target_yaw = target.global_rotation.y
	_yaw_spring.value = _target_yaw
	global_position = _goal_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sensitivity := mouse_sensitivity * sensitivity_scale
		_target_yaw -= motion.relative.x * sensitivity
		_target_pitch -= motion.relative.y * sensitivity
		_target_pitch = clampf(_target_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	_clamp_to_torso_limits()
	var weight := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_goal_position(), weight)
	var max_lag := deg_to_rad(max_aim_lag_deg)
	_yaw_spring.update(_target_yaw, aim_frequency, aim_damping, max_lag, delta)
	_pitch_spring.update(_target_pitch, aim_frequency, aim_damping, max_lag, delta)
	yaw = _yaw_spring.value
	pitch = _pitch_spring.value
	# The camera stays behind the torso.
	var mech := target as Mech
	var view_yaw := mech.get_aim_yaw_interpolated() if mech != null else yaw
	rotation = Vector3(0.0, view_yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)


## The camera cannot look past the mech torso twist limits.
func _clamp_to_torso_limits() -> void:
	var mech := target as Mech
	if mech == null:
		return
	var offset := wrapf(_target_yaw - mech.rotation.y, -PI, PI)
	var limited := clampf(offset, -deg_to_rad(mech.torso_twist_right_deg), deg_to_rad(mech.torso_twist_left_deg))
	_target_yaw += limited - offset


func _goal_position() -> Vector3:
	var height := pivot_height
	var mech := target as Mech
	if mech != null:
		# The camera goes down and up with the kneel.
		height -= kneel_height_drop * smoothstep(0.0, 1.0, mech.kneel.amount)
	return target.get_global_transform_interpolated().origin + Vector3.UP * height
