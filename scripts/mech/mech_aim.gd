class_name MechAim
extends Node
## Finds two points in the world:
## camera_target: where the camera crosshair points (a little above the screen center).
## aim_point: where the mech really aims. It follows the body turn, and shakes while the mech walks or boosts.

@export var mech: Mech
@export var camera: Camera3D
## Optional. While the camera looks at the front of the mech, the aim keeps its last pitch and
## follows the torso turn (the camera view is not used then).
@export var camera_rig: MechCameraRig
## Start point of the mech's aim (the weapon stock at the shoulder).
@export var aim_origin: Node3D
@export var max_range: float = 1500.0
## The crosshair sits this far above the screen center, as a part of the screen height.
## 0.135 matches the reference screenshot (about 120 px above the center of a 900 px view).
## The camera tilts down by the matching angle (CameraAds), so a higher crosshair means a steeper view.
@export var screen_offset_up: float = 0.135
## Physics layers the aim rays hit (1 = world, 3 = props).
@export_flags_3d_physics var collision_mask: int = 5

@export_group("Jitter")
## Aim shake at full walk speed, in degrees.
@export var walk_jitter_deg: float = 0.0
## Aim shake while boosting = walk jitter x this value.
@export var boost_jitter_multiplier: float = 2.0
## Aim shake in the air = boost jitter x this value.
@export var air_jitter_multiplier: float = 2.0
## Aim shake while kneeling = normal aim shake x this value. 0.25 = 75% less.
@export var kneel_jitter_multiplier: float = 0.25
## Small aim shake when standing still, in degrees.
@export var idle_jitter_deg: float = 0.0
## How fast the shake moves.
@export var jitter_speed: float = 2.0

@export_group("Shot Kick")
## Each shot moves the mech aim this far off the camera crosshair, in a random direction (degrees).
## The aim stays there until the player re-aligns it. There is no automatic return.
@export var shot_kick_deg: float = 2.0
## Re-align: move the mouse (the view) in the opposite direction of the kick. The gap closes by
## this part of the view movement (0.5 = half). Moves in other directions move both together.
@export_range(0.0, 1.0) var realign_rate: float = 0.5
@export_group("")

var camera_target: Vector3 = Vector3.ZERO
var aim_point: Vector3 = Vector3.ZERO
var aim_direction: Vector3 = Vector3.FORWARD
## Shot kick offset of the mech aim from the crosshair, in degrees: x = yaw (left), y = pitch (up).
## Each shot sets it. Moving the view in the opposite direction brings it back to zero.
var _last_view: Vector2 = Vector2.ZERO
var shot_offset: Vector2 = Vector2.ZERO

var _noise := FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_noise.frequency = 1.0
	# Run after movement and before the weapon pose.
	process_physics_priority = 4


func _physics_process(delta: float) -> void:
	_time += delta * jitter_speed
	var origin := aim_origin.global_position
	if camera_rig != null and camera_rig.front_view_amount > 0.0:
		var flat_yaw := atan2(-aim_direction.x, -aim_direction.z)
		aim_direction = aim_direction.rotated(Vector3.UP, wrapf(mech.get_aim_yaw() - flat_yaw, -PI, PI))
		aim_point = _cast(origin, aim_direction)
		return
	var screen_point := get_crosshair_screen_point()
	camera_target = _cast(camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point))

	# The mech aims at the camera target, corrected for any gap between the torso and the camera.
	var direction := (camera_target - origin).normalized()
	var forward := -camera.global_basis.z
	var camera_yaw := atan2(-forward.x, -forward.z)
	var body_error := wrapf(mech.get_aim_yaw() - camera_yaw, -PI, PI)
	direction = direction.rotated(Vector3.UP, body_error)

	# Shot kick: the aim stays off the crosshair until the player re-centers it.
	_mouse_realign()
	var kick_right := direction.cross(Vector3.UP).normalized()
	direction = direction.rotated(Vector3.UP, deg_to_rad(shot_offset.x))
	direction = direction.rotated(kick_right, deg_to_rad(shot_offset.y)).normalized()

	var jitter := deg_to_rad(_get_jitter_deg())
	var right := direction.cross(Vector3.UP).normalized()
	direction = direction.rotated(Vector3.UP, jitter * _noise.get_noise_2d(_time, 0.0))
	direction = direction.rotated(right, jitter * _noise.get_noise_2d(_time, 50.0)).normalized()

	aim_direction = direction
	aim_point = _cast(origin, direction)


## View movement in the opposite direction of the kick closes the gap by realign_rate x that
## movement (like pulling a gun back down after its recoil).
func _mouse_realign() -> void:
	var view := Vector2(mech.get_aim_yaw(), camera_rig.pitch if camera_rig != null else 0.0)
	var moved := Vector2(rad_to_deg(wrapf(view.x - _last_view.x, -PI, PI)), rad_to_deg(view.y - _last_view.y))
	_last_view = view
	var gap := shot_offset.length()
	if gap < 0.0001:
		return
	var against := -moved.dot(shot_offset / gap)
	if against > 0.0:
		shot_offset -= shot_offset / gap * minf(against * realign_rate, gap)


## Moves the mech aim shot_kick_deg off the crosshair in a random direction. WeaponFire calls it
## after each shot.
func kick_aim() -> void:
	var angle := randf() * TAU
	shot_offset = Vector2(cos(angle), sin(angle)) * shot_kick_deg


## Screen position of the camera crosshair, in pixels.
func get_crosshair_screen_point() -> Vector2:
	var size := camera.get_viewport().get_visible_rect().size
	return Vector2(size.x * 0.5, size.y * (0.5 - screen_offset_up))


func _get_jitter_deg() -> float:
	return _get_base_jitter_deg() * lerpf(1.0, kneel_jitter_multiplier, mech.kneel.amount)


func _get_base_jitter_deg() -> float:
	var boost_jitter := walk_jitter_deg * boost_jitter_multiplier
	if not mech.is_on_floor():
		return boost_jitter * air_jitter_multiplier
	if mech.is_boosting:
		return boost_jitter
	var walk_ratio := clampf(mech.get_horizontal_speed() / mech.walk_speed, 0.0, 1.0)
	return maxf(walk_jitter_deg * walk_ratio, idle_jitter_deg)


func _cast(from: Vector3, direction: Vector3) -> Vector3:
	var to := from + direction * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var hit := mech.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else to
