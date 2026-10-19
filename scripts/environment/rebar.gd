class_name Rebar
extends RefCounted
## Bent steel bars at concrete break edges (phase 5b, user choice 2026-10-19). When a concrete chunk
## breaks, each standing neighbor it touched gets a few bars on the shared face, sticking out into the
## hole and bent down at the end. The bars are children of the neighbor (they go when it breaks or falls).
## At most max_count bars in the level; the oldest goes first.

## Bar thickness (m).
const RADIUS := 0.05
const COLOR := Color(0.24, 0.16, 0.11)

static var max_count: int = 300
static var _all: Array = []
static var _mesh: CylinderMesh
static var _material: StandardMaterial3D


## Bars for the hole of a broken chunk. hole: its boxes, neighbors: [chunk, its boxes] pairs, all boxes
## in the space of `space` (the building). per_face: bars per shared face (a range).
static func spawn(space: Node3D, hole: Array[AABB], neighbors: Array, per_face: Vector2i, gap: float) -> void:
	_setup()
	for pair: Array in neighbors:
		var other := pair[0] as UrbanChunk
		if not is_instance_valid(other):
			continue
		for box_a: AABB in hole:
			for box_b: AABB in pair[1]:
				var shared := box_a.grow(gap).intersection(box_b.grow(gap))
				if not shared.has_volume():
					continue
				_bars_on_face(space, other, box_a, box_b, shared, randi_range(per_face.x, per_face.y))


## Bars on the face shared by the hole box and the neighbor box; they point from the neighbor into the hole.
static func _bars_on_face(space: Node3D, other: UrbanChunk, hole: AABB, keep: AABB, shared: AABB, count: int) -> void:
	# The face normal: the axis along which the two boxes are side by side.
	var out := hole.get_center() - keep.get_center()
	var axis := 0
	var thin := INF
	for i in 3:
		if shared.size[i] < thin:
			thin = shared.size[i]
			axis = i
	var direction := Vector3.ZERO
	direction[axis] = signf(out[axis]) if out[axis] != 0.0 else 1.0
	for i in count:
		while _all.size() >= max_count:
			var oldest: Variant = _all.pop_front()
			if is_instance_valid(oldest):
				(oldest as Node).queue_free()
		var start := shared.position + Vector3(randf(), randf(), randf()) * shared.size
		start[axis] = shared.get_center()[axis]
		var bar := Node3D.new()
		bar.name = "Rebar"
		other.add_child(bar)
		var length := randf_range(0.4, 0.9)
		var bend_length := randf_range(0.25, 0.6)
		var bend := deg_to_rad(randf_range(25.0, 70.0))
		var world_start := space.global_transform * start
		var world_dir := (space.global_basis * direction).normalized()
		var down := Vector3.DOWN if absf(world_dir.y) < 0.9 else world_dir.cross(Vector3.RIGHT).normalized()
		var tip := world_start + world_dir * length
		var bent_dir := (world_dir * cos(bend) + down * sin(bend)).normalized()
		_segment(bar, world_start, tip)
		_segment(bar, tip, tip + bent_dir * bend_length)
		_all.append(bar)
		bar.tree_exited.connect(func() -> void: _all.erase(bar))


## One straight piece of bar between two world points.
static func _segment(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = _mesh
	piece.material_override = _material
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)
	var along := b - a
	var y := along.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	piece.global_transform = Transform3D(Basis(x * RADIUS * 2.0, y * along.length(), z * RADIUS * 2.0), (a + b) * 0.5)


static func _setup() -> void:
	if _mesh != null:
		return
	_mesh = CylinderMesh.new()
	_mesh.top_radius = 0.5
	_mesh.bottom_radius = 0.5
	_mesh.height = 1.0
	_mesh.radial_segments = 5
	_mesh.rings = 1
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR
	_material.metallic = 0.4
	_material.roughness = 0.8
