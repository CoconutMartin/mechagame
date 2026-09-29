class_name MechAim
extends Node
## Finds two points in the world:
## camera_target: where the camera crosshair points (a little above the screen center).
## aim_point: where the mech really aims: the crosshair direction plus the free aim offset (FreeAim),
## turned with the body in slides.
## While the mech is down (fall, get-up) or in an Akira slide, the ring stays at its neutral place
## (the crosshair plus the free aim offset) and does not follow the torso or the body turn.

@export var mech: Mech
@export var camera: Camera3D
## Optional. While the camera looks at the front of the mech, the aim keeps its last pitch and
## follows the torso turn (the camera view is not used then).
@export var camera_rig: MechCameraRig
## Start point of the mech's aim (the weapon stock at the shoulder).
@export var aim_origin: Node3D
## Optional. The whole-body visual. When it turns (skid drift, Akira slide) the mech aim turns with it.
@export var body_visual: Node3D
@export var max_range: float = 1500.0
## The crosshair sits this far above the screen center, as a part of the screen height.
## The camera tilts down by the matching angle (CameraAds), so a higher crosshair shows more ground
## below the mech. 0.3 (revision 59) = the view about 12 degrees lower than 0.135, as the user drew.
@export var screen_offset_up: float = 0.3
## Layers the aim ray hits: 1 world, 3 props, 4 hitboxes (mech parts and dummies). The own mech is skipped.
@export_flags_3d_physics var collision_mask: int = 13
## How fast the ring moves to and from its neutral place (1 / seconds).
@export var neutral_blend_speed: float = 4.0
## After an Akira slide the ring follows the torso again when the body turn is below this, in degrees.
@export var akira_release_deg: float = 3.0

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


var camera_target: Vector3 = Vector3.ZERO
var aim_point: Vector3 = Vector3.ZERO
var aim_direction: Vector3 = Vector3.FORWARD
## Free aim offset of the mech aim from the crosshair, in degrees: x = yaw (left), y = pitch (up).
var shot_offset: Vector2 = Vector2.ZERO

## AI pilots aim here instead of through the camera (AIPilot sets it every frame).
var use_ai_target: bool = false
var ai_target: Vector3 = Vector3.ZERO

## 0 = the ring follows the torso, 1 = the ring stays at its neutral place.
var neutral_amount: float = 0.0

var _noise := FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_noise.frequency = 1.0
	# Run after movement and before the weapon pose.
	process_physics_priority = 4


func _physics_process(delta: float) -> void:
	_time += delta * jitter_speed
	# Akira slide: from the skid start until the body has turned back after it.
	var akira := mech.skid_akira and (mech.is_skidding or absf(get_body_turn()) > deg_to_rad(akira_release_deg))
	var neutral := mech.is_fallen or mech.is_wrecked or akira
	neutral_amount = move_toward(neutral_amount, 1.0 if neutral else 0.0, neutral_blend_speed * delta)
	var origin := aim_origin.global_position
	if use_ai_target:
		camera_target = ai_target
		shot_offset = Vector2.ZERO
		aim_direction = (ai_target - origin).normalized()
		aim_point = _cast(origin, aim_direction)
		return
	if camera_rig != null and camera_rig.front_view_amount > 0.0:
		var flat_yaw := atan2(-aim_direction.x, -aim_direction.z)
		aim_direction = aim_direction.rotated(Vector3.UP, wrapf(mech.get_aim_yaw() - flat_yaw, -PI, PI))
		aim_point = _cast(origin, aim_direction)
		return
	var screen_point := get_crosshair_screen_point()
	camera_target = _cast(camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point))
	shot_offset = camera_rig.free_aim.aim_offset if camera_rig != null and camera_rig.free_aim != null else Vector2.ZERO

	# The mech aims at what the camera sees under the blue ring (a camera ray through the ring), so
	# the shots land on the ring at any distance and on the edge of a target too.
	var ring := get_ring_screen_point()
	var ring_target := _cast(camera.project_ray_origin(ring), camera.project_ray_normal(ring))
	var direction := (ring_target - origin).normalized()

	var jitter := deg_to_rad(_get_jitter_deg())
	if jitter <= 0.0:
		aim_direction = direction
		aim_point = ring_target
		return
	var right := direction.cross(Vector3.UP).normalized()
	direction = direction.rotated(Vector3.UP, jitter * _noise.get_noise_2d(_time, 0.0))
	direction = direction.rotated(right, jitter * _noise.get_noise_2d(_time, 50.0)).normalized()
	aim_direction = direction
	aim_point = _cast(origin, direction)


## Screen position of the blue ring (the mech aim), in pixels: the crosshair, moved by the gap
## between the torso aim and the camera view (and the slide body turn), and by the free aim offset.
func get_ring_screen_point() -> Vector2:
	var focal := camera.get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	var point := get_crosshair_screen_point() + Vector2(-tan(get_ring_gap()) * focal, 0.0)
	return point + Vector2(-tan(deg_to_rad(shot_offset.x)) * focal, -tan(deg_to_rad(shot_offset.y)) * focal)


## Yaw gap between the torso aim (with the slide body turn) and the camera view, in radians.
## 0 while the ring is at its neutral place (neutral_amount).
func get_ring_gap() -> float:
	var forward := -camera.get_parent_node_3d().global_basis.z
	var camera_yaw := atan2(-forward.x, -forward.z)
	var gap := wrapf(mech.get_aim_yaw_interpolated() + get_body_turn() - camera_yaw, -PI, PI)
	return gap * (1.0 - smoothstep(0.0, 1.0, neutral_amount))


## Whole-body turn from a slide (radians, positive = left). The mech aim turns with the body.
func get_body_turn() -> float:
	return body_visual.rotation.y if body_visual != null else 0.0


## Recoil kick after a shot. The weapons call it. The kick goes to the free aim box.
## Negative values use the FreeAim defaults.
func kick_aim(up_deg: float = -1.0, side_deg: float = -1.0, jitter_scale: float = 1.0) -> void:
	if camera_rig != null and camera_rig.free_aim != null:
		camera_rig.free_aim.kick(up_deg, side_deg, jitter_scale)


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
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, mech.get_hit_exclude())
	var hit := mech.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else to
