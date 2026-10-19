class_name ScorchMark
extends RefCounted
## Black burn mark on a building wall (phase 5b, user choice 2026-10-19): missile blasts and heavy
## shells leave one where they hit a chunk. A flat see-through quad on the wall face (a mesh, not a
## Decal: it shows in every renderer), a child of the chunk (it goes when the chunk breaks or falls).
## At most max_count marks in the level; the oldest goes first.

const TEXTURE := preload("res://assets/textures/decals/scorch.png")
## The mark stands this far out of the wall (m).
const LIFT := 0.04

static var max_count: int = 80
static var _all: Array = []
static var _mesh: QuadMesh
static var _material: StandardMaterial3D


## Puts a mark of size m (across) on chunk where a ray from `from` toward the chunk meets it. Does
## nothing when the ray misses the chunk.
static func add(chunk: UrbanChunk, from: Vector3, size: float) -> void:
	if from == Vector3.INF or not chunk.is_inside_tree():
		return
	# Toward each of its boxes, nearest first: the middle of a wall around a window is the opening.
	var hit := {}
	var space := chunk.get_world_3d().direct_space_state
	for target in _box_centers(chunk, from):
		var query := PhysicsRayQueryParameters3D.create(from, target + (target - from).normalized() * 2.0, chunk.collision_layer)
		hit = space.intersect_ray(query)
		if not hit.is_empty() and hit.collider == chunk:
			break
		hit = {}
	if hit.is_empty():
		return
	_setup()
	while _all.size() >= max_count:
		var oldest: Variant = _all.pop_front()
		if is_instance_valid(oldest):
			(oldest as Node).queue_free()
	var normal := hit.normal as Vector3
	var mark := MeshInstance3D.new()
	mark.name = "Scorch"
	mark.mesh = _mesh
	mark.material_override = _material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(mark)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-normal, up).rotated(normal, randf() * TAU)
	mark.global_transform = Transform3D(basis * Basis.from_scale(Vector3(size, size, 1.0)), (hit.position as Vector3) + normal * LIFT)
	_all.append(mark)
	mark.tree_exited.connect(func() -> void: _all.erase(mark))


## The middles of the chunk's collision boxes (world), nearest to `from` first.
static func _box_centers(chunk: UrbanChunk, from: Vector3) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for child in chunk.get_children():
		if child is CollisionShape3D:
			centers.append((child as CollisionShape3D).global_position)
	centers.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(from) < b.distance_squared_to(from))
	return centers


static func _setup() -> void:
	if _mesh != null:
		return
	_mesh = QuadMesh.new()
	_mesh.size = Vector2.ONE
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_texture = TEXTURE
	_material.roughness = 1.0
