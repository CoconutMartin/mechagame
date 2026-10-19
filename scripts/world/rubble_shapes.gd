class_name RubbleShapes
extends RefCounted
## Rough rubble pieces (phase 5b, user choice 2026-10-19: jagged pieces in place of plain boxes).
## A few unit-size chunks are made once: a box whose 8 corners move in and out at random, each face
## split along a random diagonal, flat shaded. Rubble picks one at random and scales it to the piece size.

## Number of shapes made.
const VARIANTS := 8
## How far a corner moves (part of the box size).
const JITTER := 0.22

static var _meshes: Array[ArrayMesh] = []


## A random rough unit piece (about 1 x 1 x 1 m, center at the origin).
static func pick() -> ArrayMesh:
	if _meshes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in VARIANTS:
			_meshes.append(_make(rng))
	return _meshes[randi() % _meshes.size()]


static func _make(rng: RandomNumberGenerator) -> ArrayMesh:
	var corners: Array[Vector3] = []
	for i in 8:
		var corner := Vector3(0.5 if i & 1 else -0.5, 0.5 if i & 2 else -0.5, 0.5 if i & 4 else -0.5)
		corners.append(corner + Vector3(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER),
				rng.randf_range(-JITTER, JITTER)))
	# Faces of the box as corner index quads (_tri turns each triangle to face out).
	var quads := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for quad: Array in quads:
		var a: Vector3 = corners[quad[0]]
		var b: Vector3 = corners[quad[1]]
		var c: Vector3 = corners[quad[2]]
		var d: Vector3 = corners[quad[3]]
		# Split each face along a random diagonal: the bent faces look broken.
		if rng.randf() < 0.5:
			_tri(tool, a, b, c)
			_tri(tool, a, c, d)
		else:
			_tri(tool, a, b, d)
			_tri(tool, b, c, d)
	tool.generate_normals()
	return tool.commit()


## One triangle facing out of the piece (Godot's front faces: (b - a) x (c - a) points inward).
static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).dot(a + b + c) > 0.0:
		var swap := b
		b = c
		c = swap
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
