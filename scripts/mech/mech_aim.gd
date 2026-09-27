class_name MechAim
extends Node
## Finds two points in the world:
## camera_target: where the camera crosshair (screen center) points.
## aim_point: where the mech really aims. It follows the body turn, and shakes while the mech walks or boosts.

@export var mech: Mech
@export var camera: Camera3D
## Start point of the mech's aim (the weapon stock at the shoulder).
@export var aim_origin: Node3D
@export var max_range: float = 1500.0
## Physics layers the aim rays hit (1 = world, 3 = props).
@export_flags_3d_physics var collision_mask: int = 5

@export_group("Jitter")
## Aim shake at full walk speed, in degrees.
@export var walk_jitter_deg: float = 0.6
## Aim shake while boosting = walk jitter x this value.
@export var boost_jitter_multiplier: float = 2.0
## Aim shake in the air = boost jitter x this value.
@export var air_jitter_multiplier: float = 2.0
## Small aim shake when standing still, in degrees.
@export var idle_jitter_deg: float = 0.05
## How fast the shake moves.
@export var jitter_speed: float = 2.0

var camera_target: Vector3 = Vector3.ZERO
var aim_point: Vector3 = Vector3.ZERO
var aim_direction: Vector3 = Vector3.FORWARD

var _noise := FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	_noise.frequency = 1.0
	# Run after movement and before the weapon pose.
	process_physics_priority = 4


func _physics_process(delta: float) -> void:
	_time += delta * jitter_speed
	var origin := aim_origin.global_position
	camera_target = _cast(camera.global_position, -camera.global_basis.z)

	# The mech aims at the camera target, but only as far as the body has turned.
	var direction := (camera_target - origin).normalized()
	var body_error := wrapf(mech.rotation.y - mech.input.aim_yaw, -PI, PI)
	direction = direction.rotated(Vector3.UP, body_error)

	var jitter := deg_to_rad(_get_jitter_deg())
	var right := direction.cross(Vector3.UP).normalized()
	direction = direction.rotated(Vector3.UP, jitter * _noise.get_noise_2d(_time, 0.0))
	direction = direction.rotated(right, jitter * _noise.get_noise_2d(_time, 50.0)).normalized()

	aim_direction = direction
	aim_point = _cast(origin, direction)


func _get_jitter_deg() -> float:
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
