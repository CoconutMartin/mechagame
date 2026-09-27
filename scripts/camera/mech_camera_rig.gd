class_name MechCameraRig
extends Node3D
## Over-the-shoulder camera. Follows the target and turns with the mouse.
## Node layout: MechCameraRig > Pitch > SpringArm3D > Camera3D.

@export var target: Node3D
## Height of the camera pivot above the mech's feet, in meters.
@export var pivot_height: float = 7.0
## Higher value = camera follows more tightly.
@export var follow_sharpness: float = 14.0
## Radians turned per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_deg: float = -55.0
@export var max_pitch_deg: float = 30.0

## Current look direction in radians. The mech reads yaw to know where to face.
var yaw: float = 0.0
var pitch: float = 0.0

@onready var _pitch_node: Node3D = $Pitch


func _ready() -> void:
	top_level = true
	# This node moves in _process, so it must not use physics interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	yaw = target.global_rotation.y
	global_position = _goal_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity
		pitch -= motion.relative.y * mouse_sensitivity
		pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	var weight := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_goal_position(), weight)
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)


func _goal_position() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * pivot_height
