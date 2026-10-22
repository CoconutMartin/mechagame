class_name MechCameraRig
extends Node3D
## Over-the-shoulder camera. Stays behind the mech torso and turns with it.
## The mouse moves an aim target (yaw). The torso turns toward that target at its own turn speed,
## and the camera turns with the torso. Pitch follows the mouse on a spring.
## The arrow keys aim like the mouse (key_aim_pixels_per_second).
## Press V (free_camera) for the free camera: hold RMB and move the mouse to turn the camera around the
## mech (the mech keeps its aim, its weapons do not raise); press V again to go back behind the mech.
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
## Mouse sensitivity factor per weight class (light 1.5, medium 1.3, heavy 1.0). Applies to the mouse,
## the aim keys and the free camera, and stacks with sensitivity_scale (ADS).
@export var class_tuning: AimClassTuning = AimClassTuning.new()
## Largest lead of the camera aim over the torso, in degrees. The torso turns slowly (Mech.turn_speed_deg):
## mouse motion past this lead is dropped, so the view stops when the mouse stops (user report
## 2026-10-15: "the camera is fighting me"; before, the aim ran up to 135 degrees ahead and the view
## kept turning for seconds).
@export var max_torso_lead_deg: float = 15.0
## Vertical mouse aim speed = mouse sensitivity x this value. 0.3 = 70% slower than horizontal.
@export var pitch_sensitivity_scale: float = 0.3
## Horizontal mouse aim speed = mouse sensitivity x this value (1.5 since 2026-10-22, user request: +50%).
@export var yaw_sensitivity_scale: float = 1.5
## Arrow keys (aim_left / aim_right / aim_up / aim_down) aim like a mouse moving this many pixels per
## second (user request 2026-10-13: an alternative to the mouse). 600 = about 86 deg/s sideways.
@export var key_aim_pixels_per_second: float = 600.0
## Up and down keys move this many times faster than the same mouse movement (the mouse's vertical
## aim is slowed by pitch_sensitivity_scale).
@export var key_pitch_scale: float = 2.0
@export var min_pitch_deg: float = -27.5
## Aim pitch at the start, in degrees. Negative = down. The camera also tilts down by the crosshair
## angle (about 21 degrees at FOV 65), so -3.1 gives a camera pitch of -24 degrees.
@export var start_pitch_deg: float = -3.1
@export var max_pitch_deg: float = 15.0
## While a two-hand rifle is raised (the sniping stance), the aim may not go lower than this pitch, in degrees
## (negative = down). Lower than about -16 the right arm reaches its swing limit, the rifle is dragged to the
## hand and its butt goes into the right forearm (mesh check 2026-10-22); -14 keeps a margin. The limit
## blends in with the raise (SkeletalAimStance.amount) and out with the lower. Not used by the free camera.
@export var ads_min_pitch_deg: float = -14.0

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
## 0 = camera behind the mech, 1 = free camera (turned by the mouse while RMB is held).
var free_camera_amount: float = 0.0
## 1 = the camera follows the mouse only (mech down), 0 = it stays behind the torso.
var _free_look: float = 0.0
## V toggles the free camera.
var free_camera_on: bool = false

@export_group("Free Camera")
## How fast the camera blends into and out of the free camera (1 / seconds).
@export var free_camera_speed: float = 3.0
## Free camera turn speed = mouse sensitivity x this value (both axes).
@export var free_camera_sensitivity_scale: float = 1.0
## Free camera pitch limits, in degrees (negative = looking down).
@export var free_camera_min_pitch_deg: float = -75.0
@export var free_camera_max_pitch_deg: float = 60.0
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
## Free camera turn (radians).
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
var _yaw_spring := AimSpring.new()
var _pitch_spring := AimSpring.new()
## The mech's sniping stance (found on first use); its amount raises the ADS look-down limit.
var _stance: SkeletalAimStance

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
	_add_wall_see_through()


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


## Turns a mouse movement (pixels) into free aim and camera turn. In the free camera with RMB held it
## turns the free camera only.
func apply_mouse_motion(relative: Vector2) -> void:
	var class_factor := class_tuning.get_sensitivity_factor(target as Mech) if class_tuning != null else 1.0
	if free_camera_on and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_BRACKETRIGHT)):
		var turn_speed := mouse_sensitivity * free_camera_sensitivity_scale * class_factor
		_free_yaw -= relative.x * turn_speed
		_free_pitch = clampf(_free_pitch - relative.y * turn_speed, deg_to_rad(free_camera_min_pitch_deg),
				deg_to_rad(free_camera_max_pitch_deg))
		return
	var sensitivity := mouse_sensitivity * sensitivity_scale * class_factor
	var turn := Vector2(-relative.x * sensitivity * yaw_sensitivity_scale, -relative.y * sensitivity * pitch_sensitivity_scale)
	if free_aim != null and free_camera_amount <= 0.0:
		# The mech aim moves first. The camera turns by the part past the box edge.
		turn = free_aim.take_motion(turn * rad_to_deg(1.0)) * deg_to_rad(1.0)
	_target_yaw += turn.x
	_target_pitch = clampf(_target_pitch + turn.y, get_min_pitch(), deg_to_rad(max_pitch_deg))


## Lowest aim pitch now (radians): min_pitch_deg, raised toward ads_min_pitch_deg by the sniping stance.
func get_min_pitch() -> float:
	var low := deg_to_rad(min_pitch_deg)
	if _stance == null or not is_instance_valid(_stance):
		_stance = null
		for node in target.find_children("*", "SkeletalAimStance", true, false):
			_stance = node as SkeletalAimStance
			break
	if _stance == null or _stance.amount <= 0.0:
		return low
	return lerpf(low, maxf(deg_to_rad(ads_min_pitch_deg), low), _stance.amount)


func _process(delta: float) -> void:
	var keys := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if keys != Vector2.ZERO:
		apply_mouse_motion(Vector2(keys.x, keys.y * key_pitch_scale) * key_aim_pixels_per_second * delta)
	if free_aim != null:
		# Recoil with no dead zone turns the camera (muzzle climb).
		var kick := free_aim.take_camera_kick() * deg_to_rad(1.0)
		_target_yaw += kick.x
		_target_pitch = clampf(_target_pitch + kick.y, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	# A raise (ads_min_pitch_deg) lifts the limit under a pitch that was set before: the aim comes up with it.
	_target_pitch = maxf(_target_pitch, get_min_pitch())
	_limit_torso_lead()
	var weight := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_goal_position(), weight)
	var max_lag := deg_to_rad(max_aim_lag_deg)
	_yaw_spring.update(_target_yaw, aim_frequency, aim_damping, max_lag, delta)
	_pitch_spring.update(_target_pitch, aim_frequency, aim_damping, max_lag, delta)
	# The view itself keeps the ADS limit too (the spring would lag below it while the raise lifts the limit).
	var floor_pitch := get_min_pitch()
	if _pitch_spring.value < floor_pitch:
		_pitch_spring.value = floor_pitch
		_pitch_spring.velocity = maxf(_pitch_spring.velocity, 0.0)
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
	if Input.is_action_just_pressed("free_camera"):
		free_camera_on = not free_camera_on
		if free_camera_on and free_camera_amount <= 0.0:
			# The free camera starts where the camera is now.
			_free_yaw = view_yaw
			_free_pitch = pitch
	free_camera_amount = move_toward(free_camera_amount, 1.0 if free_camera_on else 0.0, free_camera_speed * delta)
	var blend := smoothstep(0.0, 1.0, free_camera_amount)
	rotation = Vector3(0.0, lerp_angle(view_yaw, _free_yaw, blend), 0.0)
	_pitch_node.rotation = Vector3(lerpf(pitch, _free_pitch, blend), 0.0, 0.0)


## Keeps the camera aim within max_torso_lead_deg of the torso aim (not while the mech is down: the
## camera follows the mouse freely then).
func _limit_torso_lead() -> void:
	var mech := target as Mech
	if mech == null or mech.is_fallen or mech.is_wrecked or max_torso_lead_deg <= 0.0:
		return
	var torso_yaw := mech.get_aim_yaw()
	var lead := wrapf(_target_yaw - torso_yaw, -PI, PI)
	var limit := deg_to_rad(max_torso_lead_deg)
	if absf(lead) > limit:
		_target_yaw = torso_yaw + signf(lead) * limit


func _goal_position() -> Vector3:
	var height := pivot_height
	var mech := target as Mech
	if mech != null:
		# The camera goes down and up with the kneel.
		height -= kneel_height_drop * smoothstep(0.0, 1.0, mech.kneel.amount)
	return target.get_global_transform_interpolated().origin + Vector3.UP * height


## Hides building pieces between the camera and the mech (CameraWallSeeThrough).
func _add_wall_see_through() -> void:
	var camera: Camera3D = null
	for node in _pitch_node.find_children("*", "Camera3D", true, false):
		camera = node as Camera3D
		break
	if camera == null or target == null:
		return
	var see_through := CameraWallSeeThrough.new()
	see_through.name = "WallSeeThrough"
	see_through.camera = camera
	see_through.mech = target
	add_child(see_through)
