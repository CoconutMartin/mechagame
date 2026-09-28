class_name Blast
extends RefCounted
## Area damage (missile explosions). Everything with on_hit() inside the radius takes damage:
## full damage at the center, falling to 30% at the edge (by distance to the nearest shape).
## Each body is hit once.

## Layers a blast hits: 1 world, 3 props, 4 hitboxes.
const MASK := 1 | 4 | 8


static func apply(world: World3D, center: Vector3, radius: float, damage: float, exclude: Array[RID] = []) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = MASK
	query.exclude = exclude
	# Nearest distance to each body (a body with many shapes is hit once).
	var nearest := {}
	for result in world.direct_space_state.intersect_shape(query, 64):
		var body: Object = result.collider
		if body == null or not body.has_method(&"on_hit"):
			continue
		var distance := _distance_to_shape(body as CollisionObject3D, result.shape, center)
		nearest[body] = minf(nearest.get(body, INF), distance)
	for body: Object in nearest:
		var falloff := lerpf(1.0, 0.3, clampf(nearest[body] / radius, 0.0, 1.0))
		body.on_hit(damage * falloff)


## Distance from point to the surface of one shape of body (0 inside it). Boxes are exact; other
## shapes use their center.
static func _distance_to_shape(body: CollisionObject3D, shape_index: int, point: Vector3) -> float:
	var owner_id := body.shape_find_owner(shape_index)
	var shape_transform := body.global_transform * body.shape_owner_get_transform(owner_id)
	var shape := body.shape_owner_get_shape(owner_id, 0)
	var local := shape_transform.affine_inverse() * point
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		return (local - local.clamp(-half, half)).length()
	return local.length()
