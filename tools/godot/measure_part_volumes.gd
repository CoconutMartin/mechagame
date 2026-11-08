extends SceneTree
## Part weight from part volume (user decision 2026-11-08, DESIGN "HLY refit decision", rule A): weight = density x volume, where the
## volume is the voxel union of the part's meshes (overlapping plates count once) and there is one density per part type (head,
## core, arm, legs), fitted so that the SGG-101 parts keep the weights in their PartData (the two arms together).
##   godot --headless --path . --script res://tools/godot/measure_part_volumes.gd            prints the table
##   WRITE=1 godot --headless --path . --script res://tools/godot/measure_part_volumes.gd    also writes weight_t into the parts
## Parts that get their weight this way: TARGETS (the Haliya HLY-101 parts), or PARTS=<comma list of PartData .tres> for others.
## A new part gets its weight the same way: add it to TARGETS (or pass it in PARTS) and run with WRITE=1. The SGG parts are the
## reference and are never written. Also writes OUT (JSON, default user://part_volumes.json) with volumes and densities.
##
## Volume method: per mesh surface, at the rest pose of the part's own skeleton. Vertices at the same place are welded (flat shaded
## meshes repeat them). When every directed edge of the welded surface has as many opposite edges as it has copies (the surface is
## closed and consistently wound) the volume is the sum of signed tetrahedra (exact). Otherwise the surface is open and its volume
## comes from a voxel fill: a voxel is inside when at least two of the three axis rays through it cross the surface an odd number
## of times (VOXEL_SIZE). The union is the same voxel fill over all surfaces of the part, a voxel counted once. The plain sum of the
## surface volumes is printed too, for comparison.

const Refit := preload("res://tools/godot/preview_refit_parts.gd")
const TYPES: Array[String] = ["head", "core", "arm", "legs"]
## The reference parts (their weights set the densities; never written).
const SGG_DATA: Array[String] = [
	"res://data/parts/sanggigilid/sanggigilid_head.tres", "res://data/parts/sanggigilid/sanggigilid_core.tres",
	"res://data/parts/sanggigilid/sanggigilid_arm_l.tres", "res://data/parts/sanggigilid/sanggigilid_arm_r.tres",
	"res://data/parts/sanggigilid/sanggigilid_legs.tres",
]
## The parts whose weight comes from their volume.
const TARGETS: Array[String] = [
	"res://data/parts/haliya/haliya_head.tres", "res://data/parts/haliya/haliya_core.tres",
	"res://data/parts/haliya/haliya_arm_l.tres", "res://data/parts/haliya/haliya_arm_r.tres",
	"res://data/parts/haliya/haliya_legs.tres",
]
## Edge length (m) of the voxels for open surfaces and for the union.
const VOXEL_SIZE := 0.05
## Welding precision: positions are rounded to this step (m) to find the same vertex.
const WELD_STEP := 0.0001
## Weights are written rounded to this step (t).
const WEIGHT_STEP := 0.01


func _initialize() -> void:
	var targets: Array[String] = TARGETS.duplicate()
	if OS.has_environment("PARTS"):
		targets.assign(OS.get_environment("PARTS").split(",", false))
	var write := OS.get_environment("WRITE") == "1"
	var json := {"parts": {}}
	var reference := {}
	for path in SGG_DATA + targets:
		var part := load(path) as PartData
		var st := _measure(part)
		reference[path] = st
		json.parts[path] = {"type": part_type(part), "weight_t": part.weight_t, "union_m3": st.union, "sum_m3": st.volume,
				"surfaces": st.surfaces, "open": st.open}
	# Densities (t per m3) per type: SGG weight over SGG volume, for the union (rule A) and the plain sum.
	var density := {"union": {}, "sum": {}}
	for type in TYPES:
		var weight := 0.0
		var union := 0.0
		var total := 0.0
		for path in SGG_DATA:
			var part := load(path) as PartData
			if part_type(part) == type:
				weight += part.weight_t
				union += reference[path].union
				total += reference[path].volume
		density.union[type] = weight / union
		density.sum[type] = weight / total
	print("Density (t/m3), rule A (union): head %.3f core %.3f arm %.3f legs %.3f" % [density.union.head, density.union.core, density.union.arm, density.union.legs])
	print("Density (t/m3), plain sum:      head %.3f core %.3f arm %.3f legs %.3f" % [density.sum.head, density.sum.core, density.sum.arm, density.sum.legs])
	print("%-46s | %-5s | %-7s | %-9s %-7s | %-7s %-7s" % ["part", "type", "data t", "union m3", "rule A t", "sum m3", "sum t"])
	var totals := {}
	for path: String in SGG_DATA + targets:
		var part := load(path) as PartData
		var st: Dictionary = reference[path]
		var type := part_type(part)
		var weight_a := snappedf(float(density.union[type]) * float(st.union), WEIGHT_STEP)
		var weight_b: float = float(density.sum[type]) * float(st.volume)
		json.parts[path]["rule_a_t"] = weight_a
		print("%-46s | %-5s | %-7.2f | %-9.2f %-7.2f | %-7.2f %-7.2f" % [path.get_file(), type, part.weight_t, st.union, weight_a, st.volume, weight_b])
		var group := "SGG" if path in SGG_DATA else "targets"
		totals[group] = Vector2(totals.get(group, Vector2.ZERO).x + part.weight_t, totals.get(group, Vector2.ZERO).y + weight_a)
		if write and not (path in SGG_DATA):
			part.weight_t = weight_a
			print("  write %s weight_t %.2f: %s" % [path, weight_a, error_string(ResourceSaver.save(part, path))])
	for group: String in totals:
		print("total %-8s data %.2f t, rule A %.2f t" % [group, totals[group].x, totals[group].y])
	json["density"] = density
	var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "user://part_volumes.json"
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(json, "  "))
	file.close()
	print("wrote ", out)
	quit()


## The part type of a PartData: head, core, arm or legs.
static func part_type(part: PartData) -> String:
	if part is HeadPart:
		return "head"
	if part is CorePart:
		return "core"
	if part is ArmPart:
		return "arm"
	if part is LegPart:
		return "legs"
	return ""


## Volumes of a part's model at the rest pose of its own skeleton.
func _measure(part: PartData) -> Dictionary:
	var scene := part.scene.instantiate()
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var result := _part_volume(skeleton, Refit.read_rest(skeleton))
	scene.free()
	return result


## Volume of all meshes of a part: plain sum of the surfaces and the voxel union.
func _part_volume(skeleton: Skeleton3D, rest: Dictionary) -> Dictionary:
	var result := {"volume": 0.0, "surfaces": 0, "closed": 0, "open": 0, "union": 0.0}
	var soups: Array = []
	for mi in Refit.skeleton_meshes(skeleton):
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = Refit.rest_surface(mi, s, rest).vertices
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			soups.append([vertices, indices])
			var r := surface_volume(vertices, indices)
			result.surfaces += 1
			result.volume += r.volume
			if r.closed:
				result.closed += 1
			else:
				result.open += 1
	result.union = _union_volume(soups)
	return result


## Voxel volume of the union of all surfaces of a part (overlapping pieces count once).
static func _union_volume(soups: Array) -> float:
	var box := AABB()
	var first := true
	for soup: Array in soups:
		if (soup[0] as PackedVector3Array).is_empty():
			continue
		var b := _box_of(soup[0])
		box = b if first else box.merge(b)
		first = false
	box = box.grow(VOXEL_SIZE)
	var total := PackedByteArray()
	total.resize(_grid(box).x * _grid(box).y * _grid(box).z)
	for soup: Array in soups:
		if (soup[0] as PackedVector3Array).is_empty():
			continue
		var cells := _voxel_inside(soup[0], soup[1], box)
		for i in cells.size():
			if cells[i] == 1:
				total[i] = 1
	var count := 0
	for v in total:
		count += v
	return count * VOXEL_SIZE * VOXEL_SIZE * VOXEL_SIZE


## Returns {"volume": m3, "closed": bool} for one surface (triangles, any winding).
static func surface_volume(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size():
			indices[i] = i
	# Weld.
	var ids := {}
	var welded := PackedInt32Array()
	welded.resize(vertices.size())
	for i in vertices.size():
		var v := vertices[i]
		var key := Vector3i(roundi(v.x / WELD_STEP), roundi(v.y / WELD_STEP), roundi(v.z / WELD_STEP))
		if not ids.has(key):
			ids[key] = ids.size()
		welded[i] = ids[key]
	# Edge pairing.
	var edges := {}
	var signed := 0.0
	for t in range(0, indices.size() - 2, 3):
		var a := welded[indices[t]]
		var b := welded[indices[t + 1]]
		var c := welded[indices[t + 2]]
		if a == b or b == c or a == c:
			continue
		for e in [[a, b], [b, c], [c, a]]:
			var key := Vector2i(e[0], e[1])
			edges[key] = edges.get(key, 0) + 1
		var pa := vertices[indices[t]]
		var pb := vertices[indices[t + 1]]
		var pc := vertices[indices[t + 2]]
		signed += pa.dot(pb.cross(pc)) / 6.0
	var closed := true
	for key: Vector2i in edges:
		if edges[key] != edges.get(Vector2i(key.y, key.x), 0):
			closed = false
			break
	if closed:
		return {"volume": absf(signed), "closed": true}
	return {"volume": _voxel_volume(vertices, indices), "closed": false, "signed_about_centre": _signed_about_centre(vertices, indices)}


## Signed tetrahedron volume about the middle of the box: a cross-check for open surfaces (the error of a hole is smallest there).
static func _signed_about_centre(vertices: PackedVector3Array, indices: PackedInt32Array) -> float:
	if vertices.is_empty():
		return 0.0
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	var centre := box.get_center()
	var sum := 0.0
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size():
			indices[i] = i
	for t in range(0, indices.size() - 2, 3):
		var a := vertices[indices[t]] - centre
		sum += a.dot((vertices[indices[t + 1]] - centre).cross(vertices[indices[t + 2]] - centre)) / 6.0
	return absf(sum)


## Voxel volume of an open triangle surface: a voxel is inside when at least two of the three axis rays through its centre
## cross the surface an odd number of times.
static func _voxel_volume(vertices: PackedVector3Array, indices: PackedInt32Array) -> float:
	if vertices.is_empty():
		return 0.0
	var box := _box_of(vertices).grow(VOXEL_SIZE)
	var inside := _voxel_inside(vertices, indices, box)
	var count := 0
	for v in inside:
		count += v
	return count * VOXEL_SIZE * VOXEL_SIZE * VOXEL_SIZE


static func _box_of(vertices: PackedVector3Array) -> AABB:
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	return box


## Grid size of a box.
static func _grid(box: AABB) -> Vector3i:
	return Vector3i(ceili(box.size.x / VOXEL_SIZE), ceili(box.size.y / VOXEL_SIZE), ceili(box.size.z / VOXEL_SIZE))


## Voxel grid of a box (1 = inside) for one triangle surface.
static func _voxel_inside(vertices: PackedVector3Array, indices: PackedInt32Array, box: AABB) -> PackedByteArray:
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size():
			indices[i] = i
	var n := _grid(box)
	var votes := PackedByteArray()
	votes.resize(n.x * n.y * n.z)
	for axis in 3:
		var u := (axis + 1) % 3
		var w := (axis + 2) % 3
		# Crossings per ray (u, w cell): list of positions along the axis.
		var crossings := {}
		for t in range(0, indices.size() - 2, 3):
			var pa := vertices[indices[t]]
			var pb := vertices[indices[t + 1]]
			var pc := vertices[indices[t + 2]]
			var min_u := minf(pa[u], minf(pb[u], pc[u]))
			var max_u := maxf(pa[u], maxf(pb[u], pc[u]))
			var min_w := minf(pa[w], minf(pb[w], pc[w]))
			var max_w := maxf(pa[w], maxf(pb[w], pc[w]))
			var iu0 := maxi(0, floori((min_u - box.position[u]) / VOXEL_SIZE))
			var iu1 := mini(n[u] - 1, floori((max_u - box.position[u]) / VOXEL_SIZE))
			var iw0 := maxi(0, floori((min_w - box.position[w]) / VOXEL_SIZE))
			var iw1 := mini(n[w] - 1, floori((max_w - box.position[w]) / VOXEL_SIZE))
			for iu in range(iu0, iu1 + 1):
				for iw in range(iw0, iw1 + 1):
					var pu := box.position[u] + (iu + 0.5) * VOXEL_SIZE
					var pw := box.position[w] + (iw + 0.5) * VOXEL_SIZE
					var hit := _ray_hit(pa, pb, pc, axis, u, w, pu, pw)
					if is_nan(hit):
						continue
					var key := iu * 100000 + iw
					var list: PackedFloat32Array = crossings.get(key, PackedFloat32Array())
					list.append(hit)
					crossings[key] = list
		for key: int in crossings:
			var hits: PackedFloat32Array = crossings[key]
			hits.sort()
			var iu := key / 100000
			var iw := key % 100000
			for h in range(0, hits.size() - 1, 2):
				var i0 := maxi(0, ceili((hits[h] - box.position[axis]) / VOXEL_SIZE - 0.5))
				var i1 := mini(n[axis] - 1, floori((hits[h + 1] - box.position[axis]) / VOXEL_SIZE - 0.5))
				for ia in range(i0, i1 + 1):
					var idx := Vector3i.ZERO
					idx[axis] = ia
					idx[u] = iu
					idx[w] = iw
					votes[(idx.x * n.y + idx.y) * n.z + idx.z] += 1
	for i in votes.size():
		votes[i] = 1 if votes[i] >= 2 else 0
	return votes


## Position along the axis where the ray (u = pu, w = pw) crosses the triangle, or NAN.
static func _ray_hit(a: Vector3, b: Vector3, c: Vector3, axis: int, u: int, w: int, pu: float, pw: float) -> float:
	var a2 := Vector2(a[u] - pu, a[w] - pw)
	var b2 := Vector2(b[u] - pu, b[w] - pw)
	var c2 := Vector2(c[u] - pu, c[w] - pw)
	var d := (b2 - a2).cross(c2 - a2)
	if absf(d) < 1e-12:
		return NAN
	var l0 := (b2).cross(c2) / d
	var l1 := (c2).cross(a2) / d
	var l2 := 1.0 - l0 - l1
	if l0 < 0.0 or l1 < 0.0 or l2 < 0.0:
		return NAN
	return l0 * a[axis] + l1 * b[axis] + l2 * c[axis]
