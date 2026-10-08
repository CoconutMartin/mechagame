class_name MechCameraRig
extends Node3D
## Over-the-shoulder camera. Stays behind the mech torso and turns with it.
## The mouse moves an aim target (yaw). The torso turns toward that target at its own turn speed,
## and the camera turns with the torso. Pitch follows the mouse on a spring.
## Press V (front_view) to swing the camera around to the front of the mech; press V again to go back.
## With a FreeAim node the mouse first moves the mech aim inside a box. Only the movement past the
## box edge turns the camera.
## Node layout: MechCameraRig > Pitch > SpringArm3D > Camera3D.

@export var target: Node3D
## Optional. Free aim box for the mech aim (see FreeAim).
@export var free_aim: FreeAim
## Height of the camera pivot above the mech's feet, in meters. Above the head, so the camera looks down over it.
@export var pivot_height: float = 11.5
## Higher value = camera follows more tightly.
@export var follow_sharpness: float = 14.0
## Radians turned per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0025
## Vertical mouse aim speed = mouse sensitivity x this value. 0.3 = 70% slower than horizontal.
@export var pitch_sensitivity_scale: float = 0.3
@export var min_pitch_deg: float = -27.5
## Aim pitch at the start, in degrees. Negative = down. The camera also tilts down by the crosshair
## angle (about 21 degrees at FOV 65), so -3.1 gives a camera pitch of -24 degrees.
@export var start_pitch_deg: float = -3.1
@export var max_pitch_deg: float = 15.0

@export_group("Aim Spring")
## Oscillations per second. Lower = slower, heavier aim.
@export var aim_frequency: float = 1.75
## 1.0 = no overshoot. 0.5 gives about 14% overshoot (a fast 30 degree flick passes by about 4 degrees).
@export_range(0.1, 1.0) var aim_damping: float = 1.0
## Largest gap between the camera and the mouse aim, in degrees.
@export var max_aim_lag_deg: float = 25.0

## Mouse aim target in radians, after the spring. The torso turns toward this yaw.
var yaw: float = 0.0
var pitch: float = 0.0
## Multiplier on mouse sensitivity. CameraAds lowers it while aiming.
var sensitivity_scale: float = 1.0

var _target_yaw: float = 0.0
## 0 = camera behind the mech, 1 = camera in front, looking at the mech.
var front_view_amount: float = 0.0
## 1 = the camera follows the mouse only (mech down), 0 = it stays behind the torso.
var _free_look: float = 0.0
## V toggles the front view.
var front_view_on: bool = false

@export_group("Front View")
## How fast the camera swings to the front and back (1 / seconds).
@export var front_view_speed: float = 3.0
## After the mech gets up, the camera goes back behind the torso once the torso is this close to the
## mouse aim (degrees), blending over 1 / free_look_blend_speed seconds.
@export var free_look_release_deg: float = 3.0
@export var free_look_blend_speed: float = 2.0
@export_group("")

@export_group("Mech Limits")
## Camera drop when the mech kneels fully, in meters.
@export var kneel_height_drop: float = 1.74

@export_group("Mech Size")
## Scale the camera to the mech: pivot height, distance, side offset and kneel drop grow or shrink
## with the mech's shoulder height (its ShoulderL joint above the feet, from the parts' MechFrame).
@export var scale_with_mech: bool = true
## Shoulder height that keeps the values as set (the OG / Warden layout), in meters.
@export var reference_shoulder_height: float = 7.865
## Limits for the size scale.
@export var min_size_scale: float = 0.6
@export var max_size_scale: float = 2.0
@export_group("")

## Size scale in use (1 = a mech of the reference size).
var size_scale: float = 1.0
var _target_pitch: float = 0.0
var _yaw_spring := AimSpring.new()
var _pitch_spring := AimSpring.new()

@onready var _pitch_node: Node3D = $Pitch


func _ready() -> void:
	top_level = true
	# This node moves in _process, so it must not use physics interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if scale_with_mech:
		_fit_mech_size()
	_target_yaw = target.global_rotation.y
	_yaw_spring.value = _target_yaw
	_target_pitch = deg_to_rad(start_pitch_deg)
	_pitch_spring.value = _target_pitch
	global_position = _goal_position()


## Scales the camera to the mech size. MechAssembler (before this node) has already moved the frame
## joints to the parts' layout, so the shoulder height is known here.
func _fit_mech_size() -> void:
	var shoulder := target.find_child("ShoulderL", true, false) as Node3D
	if shoulder == null:
		return
	var height := shoulder.global_position.y - target.global_position.y
	size_scale = clampf(height / reference_shoulder_height, min_size_scale, max_size_scale)
	if is_equal_approx(size_scale, 1.0):
		return
	pivot_height *= size_scale
	kneel_height_drop *= size_scale
	var arm := _pitch_node.get_node_or_null(^"SpringArm") as SpringArm3D
	if arm != null:
		arm.spring_length *= size_scale
		arm.position *= size_scale
	for child in get_children():
		if child is CameraAds:
			(child as CameraAds).scale_distance(size_scale)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_motion((event as InputEventMouseMotion).relative)


## Turns a mouse movement (pixels) into free aim and camera turn.
func apply_mouse_motion(relative: Vector2) -> void:
	var sensitivity := mouse_sensitivity * sensitivity_scale
	var turn := Vector2(-relative.x * sensitivity, -relative.y * sensitivity * pitch_sensitivity_scale)
	if free_aim != null and front_view_amount <= 0.0:
		# The mech aim moves first. The camera turns by the part past the box edge.
		turn = free_aim.take_motion(turn * rad_to_deg(1.0)) * deg_to_rad(1.0)
	_target_yaw += turn.x
	_target_pitch = clampf(_target_pitch + turn.y, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	var weight := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_goal_position(), weight)
	var max_lag := deg_to_rad(max_aim_lag_deg)
	_yaw_spring.update(_target_yaw, aim_frequency, aim_damping, max_lag, delta)
	_pitch_spring.update(_target_pitch, aim_frequency, aim_damping, max_lag, delta)
	yaw = _yaw_spring.value
	pitch = _pitch_spring.value
	# The camera stays behind the torso. While the mech is down (fallen or wrecked) it follows the
	# mouse instead, and it stays there until the torso has turned back to it.
	var mech := target as Mech
	var view_yaw := yaw
	if mech != null:
		var torso_yaw := mech.get_aim_yaw_interpolated()
		if mech.is_fallen or mech.is_wrecked:
			_free_look = 1.0
		elif absf(wrapf(yaw - torso_yaw, -PI, PI)) < deg_to_rad(free_look_release_deg):
			_free_look = move_toward(_free_look, 0.0, free_look_blend_speed * delta)
		view_yaw = lerp_angle(torso_yaw, yaw, _free_look)
	if Input.is_action_just_pressed("front_view"):
		front_view_on = not front_view_on
	front_view_amount = move_toward(front_view_amount, 1.0 if front_view_on else 0.0, front_view_speed * delta)
	view_yaw += PI * smoothstep(0.0, 1.0, front_view_amount)
	rotation = Vector3(0.0, view_yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)


func _goal_position() -> Vector3:
	var height := pivot_height
	var mech := target as Mech
	if mech != null:
		# The camera goes down and up with the kneel.
		height -= kneel_height_drop * smoothstep(0.0, 1.0, mech.kneel.amount)
	return target.get_global_transform_interpolated().origin + Vector3.UP * height
