extends RefCounted
## Low poly mesh pieces for the Haliya HLY-101 refit tools (tools/godot/refit_haliya_parts.gd): faceted solids made from
## stacked rings, flat shaded, with the surface arrays of a skinned part mesh (one bone, full weight). Used through preload.
## Space: Godot skeleton space of the rig at rest (+X mech left, +Y up, +Z mech front), meters.


## A closed solid from rings of points. Each ring has the same point count and goes around the solid in the same turn
## direction; the first and the last ring are closed with a flat cap. Faces are flat shaded and point away from the middle.
## Returns the surface arrays (vertices, normals, UV) with no skin data.
static func loft(rings: Array) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var middle := Vector3.ZERO
	var count := 0
	for ring: PackedVector3Array in rings:
		for p in ring:
			middle += p
			count += 1
	middle /= float(count)
	var n: int = (rings[0] as PackedVector3Array).size()
	for r in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		for i in n:
			var j := (i + 1) % n
			_add_face(vertices, normals, uvs, [a[i], a[j], b[j], b[i]], middle)
	_add_face(vertices, normals, uvs, Array(rings[0]), middle)
	_add_face(vertices, normals, uvs, Array(rings[rings.size() - 1]), middle)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


## One flat polygon (convex, its points in order) as a triangle fan, wound so that Godot draws the side away from middle.
static func _add_face(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, points: Array, middle: Vector3) -> void:
	var centre := Vector3.ZERO
	for p: Vector3 in points:
		centre += p
	centre /= float(points.size())
	var normal := Vector3.ZERO
	for i in points.size():
		var p: Vector3 = points[i]
		var q: Vector3 = points[(i + 1) % points.size()]
		normal += (p - centre).cross(q - centre)
	if normal.length() < 1e-9:
		return
	normal = normal.normalized()
	var outward := normal.dot(centre - middle) >= 0.0
	if not outward:
		normal = -normal
	# Box UV on the main axis of the face (the PS1 skin reads the rest place, the UV only matters for textured materials).
	var axis := normal.abs().max_axis_index()
	for i in range(1, points.size() - 1):
		var tri: Array = [points[0], points[i], points[i + 1]]
		# Godot draws clockwise faces: (b - a) x (c - a) must point inward.
		if ((tri[1] as Vector3) - tri[0]).cross((tri[2] as Vector3) - tri[0]).dot(normal) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for p: Vector3 in tri:
			vertices.append(p)
			normals.append(normal)
			uvs.append(Vector2(p[(axis + 1) % 3], p[(axis + 2) % 3]) * 0.25)


## A ring of points around a centre in the XZ plane at height y: an octagon of half width hx and half depth hz with the
## corners cut by chamfer (0..1 of the smaller half size). Points go counterclockwise seen from above.
static func octagon(centre: Vector3, hx: float, hz: float, chamfer: float) -> PackedVector3Array:
	var c := chamfer * minf(hx, hz)
	var pts := PackedVector3Array()
	for p: Vector2 in [Vector2(hx, -hz + c), Vector2(hx, hz - c), Vector2(hx - c, hz), Vector2(-hx + c, hz), Vector2(-hx, hz - c),
			Vector2(-hx, -hz + c), Vector2(-hx + c, -hz), Vector2(hx - c, -hz)]:
		pts.append(centre + Vector3(p.x, 0.0, p.y))
	return pts


## A plate ring: a flat shape in a plane given by its own axes (u across, v up), points of a 2D outline mapped into 3D.
static func outline(origin: Vector3, u: Vector3, v: Vector3, points: Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p: Vector2 in points:
		pts.append(origin + u * p.x + v * p.y)
	return pts


## Moves every point of a ring.
static func shifted(ring: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p in ring:
		pts.append(p + offset)
	return pts


## Gives surface arrays full weight on one bone (index in the skin).
static func bind_one(arrays: Array, skin_bone: int) -> Array:
	var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(n * 4)
	weights.resize(n * 4)
	for i in n:
		bones[i * 4] = skin_bone
		weights[i * 4] = 1.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	return arrays
