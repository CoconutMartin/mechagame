extends SceneTree
## PREVIEW ONLY (user request 2026-11-08: "mech weight will now depend how thick the parts are").
## Volume of every mech part (head, core, left arm, right arm, legs) for SGG-101, HLY-101 now and HLY-101 refit onto the SGG
## skeleton (see preview_refit_parts.gd), and a weight rule: weight = density x volume, one density per part type, fitted so
## the SGG part weights in data/parts stay as they are. Prints a table and writes OUT (JSON, default user://part_volumes.json).
##   godot --headless --path . --script res://tools/godot/measure_part_volumes.gd
##
## Volume method: per mesh surface. Vertices at the same place are welded (flat shaded meshes repeat them). When every
## directed edge of the welded surface has as many opposite edges as it has copies (the surface is closed and consistently
## wound; a few doubled edges are fine) the volume is the sum of signed tetrahedra to the origin (exact for such a surface). Otherwise the surface is counted as open: its volume is estimated from a voxel fill, by the
## parity of the ray crossings along the three axes with the majority vote of the three (VOXEL_SIZE). Pieces that overlap
## each other count twice (no union), the same for every mech.

const Refit := preload("res://tools/godot/preview_refit_parts.gd")
const PART_NAMES: Array[String] = ["head", "core", "arm_l", "arm_r", "legs"]
## Part type of each part; one density per type.
const TYPE_OF: Dictionary = {"head": "head", "core": "core", "arm_l": "arm", "arm_r": "arm", "legs": "legs"}
## PartData files holding the weight (t) of each part.
const SGG_DATA: Dictionary = {
	"head": "res://data/parts/sanggigilid/sanggigilid_head.tres", "core": "res://data/parts/sanggigilid/sanggigilid_core.tres",
	"arm_l": "res://data/parts/sanggigilid/sanggigilid_arm_l.tres", "arm_r": "res://data/parts/sanggigilid/sanggigilid_arm_r.tres",
	"legs": "res://data/parts/sanggigilid/sanggigilid_legs.tres",
}
const HLY_DATA: Dictionary = {
	"head": "res://data/parts/haliya/haliya_head.tres", "core": "res://data/parts/haliya/haliya_core.tres",
	"arm_l": "res://data/parts/haliya/haliya_arm_l.tres", "arm_r": "res://data/parts/haliya/haliya_arm_r.tres",
	"legs": "res://data/parts/haliya/haliya_legs.tres",
}
## Edge length (m) of the voxels for open surfaces.
const VOXEL_SIZE := 0.05
## Welding precision: positions are rounded to this step (m) to find the same vertex.
const WELD_STEP := 0.0001


func _initialize() -> void:
	var sgg_rig := Refit.load_scene(Refit.SGG_RIG)
	var hly_rig := Refit.load_scene(Refit.HLY_RIG)
	var sgg_rest: Dictionary = Refit.read_rest(sgg_rig.skeleton)
	var hly_rest: Dictionary = Refit.read_rest(hly_rig.skeleton)
	sgg_rig.root.free()
	hly_rig.root.free()
	var maps: Dictionary = Refit.build_maps(hly_rest, sgg_rest)
	var rows := {}
	var stats := {}
	for part in PART_NAMES:
		var sgg_scene := Refit.load_scene("res://models/mechs/sgg/sgg_%s.glb" % part)
		var hly_scene := Refit.load_scene("res://models/mechs/haliya/haliya_%s.glb" % part)
		var v_sgg := _part_volume(sgg_scene.skeleton, sgg_rest, null)
		var v_now := _part_volume(hly_scene.skeleton, hly_rest, null)
		var v_refit := _part_volume(hly_scene.skeleton, hly_rest, maps)
		rows[part] = {"sgg": v_sgg.volume, "hly_now": v_now.volume, "hly_refit": v_refit.volume,
				"sgg_union": v_sgg.union, "hly_now_union": v_now.union, "hly_refit_union": v_refit.union}
		stats[part] = {"sgg": v_sgg, "hly_now": v_now, "hly_refit": v_refit}
		sgg_scene.root.free()
		hly_scene.root.free()
	print("")
	print("Closed-mesh check (surfaces closed / open, open volume share):")
	for part in PART_NAMES:
		for key in ["sgg", "hly_now", "hly_refit"]:
			var st: Dictionary = stats[part][key]
			print("  %-6s %-9s surfaces %3d closed %3d open %3d  open volume %.2f of %.2f m3 (cross-check signed about centre %.2f), union %.2f m3" % [part, key, st.surfaces, st.closed, st.open, st.open_volume, st.volume, st.open_signed, st.union])
	var json := {"volumes": rows}
	for method in ["", "_union"]:
		# Densities (t per m3): per type, SGG weight over SGG volume (arms: both arms together).
		var density := {}
		for type in ["head", "core", "arm", "legs"]:
			var weight := 0.0
			var volume := 0.0
			for part in PART_NAMES:
				if TYPE_OF[part] == type:
					weight += _weight(SGG_DATA[part])
					volume += rows[part]["sgg" + method]
			density[type] = weight / volume
		print("")
		print("== Volume method: %s ==" % ("sum of piece volumes" if method == "" else "voxel union (overlaps counted once)"))
		print("Density (t/m3) per type, fitted to SGG: head %.3f core %.3f arm %.3f legs %.3f" % [density.head, density.core, density.arm, density.legs])
		print("%-6s | %-6s %-8s %-8s | %-6s %-8s %-9s | %-8s %-8s" % ["part", "SGG t", "SGG m3", "SGG fit", "HLY t", "HLY m3", "HLY fit t", "refit m3", "refit t"])
		var totals := {"sgg_w": 0.0, "sgg_fit": 0.0, "hly_w": 0.0, "hly_fit": 0.0, "refit_fit": 0.0}
		for part in PART_NAMES:
			var d: float = density[TYPE_OF[part]]
			var sgg_w := _weight(SGG_DATA[part])
			var hly_w := _weight(HLY_DATA[part])
			var r: Dictionary = rows[part]
			var v_sgg: float = r["sgg" + method]
			var v_now: float = r["hly_now" + method]
			var v_refit: float = r["hly_refit" + method]
			print("%-6s | %-6.2f %-8.2f %-8.2f | %-6.2f %-8.2f %-9.2f | %-8.2f %-8.2f" % [part, sgg_w, v_sgg, d * v_sgg, hly_w, v_now, d * v_now, v_refit, d * v_refit])
			totals.sgg_w += sgg_w
			totals.sgg_fit += d * v_sgg
			totals.hly_w += hly_w
			totals.hly_fit += d * v_now
			totals.refit_fit += d * v_refit
		print("%-6s | %-6.2f %-8s %-8.2f | %-6.2f %-8s %-9.2f | %-8s %-8.2f" % ["total", totals.sgg_w, "", totals.sgg_fit, totals.hly_w, "", totals.hly_fit, "", totals.refit_fit])
		json["density" + method] = density
		json["totals" + method] = totals
	var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "user://part_volumes.json"
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(json, "  "))
	file.close()
	print("wrote ", out)
	quit()


func _weight(path: String) -> float:
	return float((load(path) as Resource).get("weight_t"))


## Volume of all meshes of a part. refit_maps null: the mesh as it is, else the refit mesh.
func _part_volume(skeleton: Skeleton3D, rest: Dictionary, refit_maps: Variant) -> Dictionary:
	var result := {"volume": 0.0, "surfaces": 0, "closed": 0, "open": 0, "open_volume": 0.0, "open_signed": 0.0, "union": 0.0}
	var soups: Array = []
	for mi in Refit.skeleton_meshes(skeleton):
		var mesh: Mesh = mi.mesh
		if refit_maps != null:
			mesh = Refit.refit_mesh(mi, rest, refit_maps)
		for s in mesh.get_surface_count():
			var vertices: PackedVector3Array
			var arrays := mesh.surface_get_arrays(s)
			if refit_maps != null:
				vertices = arrays[Mesh.ARRAY_VERTEX]
			else:
				vertices = Refit.rest_surface(mi, s, rest).vertices
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			soups.append([vertices, indices])
			var r := surface_volume(vertices, indices)
			result.surfaces += 1
			result.volume += r.volume
			if r.closed:
				result.closed += 1
			else:
				result.open += 1
				result.open_volume += r.volume
				result.open_signed += r.signed_about_centre
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
