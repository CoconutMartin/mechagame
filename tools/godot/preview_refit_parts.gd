extends SceneTree
## PREVIEW ONLY (user request 2026-11-08: "align skeleton with SGG's ... show me before and after and seek confirmation").
## Since the refit (tools/godot/refit_haliya_parts.gd, which uses the library part of this script) haliya_rig.glb has the SGG offsets,
## so the tool part of this script maps SGG onto SGG; the pictures it made are in docs/hly_refit_preview_*.png.
## Re-skins the Haliya (HLY-101) part meshes onto the SGG-101 skeleton and renders HLY now / HLY refit / SGG side by side.
## It changes no game data. Run it with a window (needs a renderer, so xvfb on a server):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tools/godot/preview_refit_parts.gd
## Headless (no pictures): prints the joint landing check and the box of every refit part.
## Writes docs/hly_refit_preview_front.png, _side.png, _back34.png and _closeup.png (OUT_DIR env overrides docs).
##
## The refit, for every vertex v with bone weights w_i (skeleton space at rest):
##   v' = sum_i w_i * T_i(v)
## where T_i maps the vertex from HLY bone i to SGG bone i: u = Frame_i^-1 (v - HLY_origin_i), u' = Warp_i(u),
## v' = SGG_origin_i + Frame_i u'. Warp_i stretches the bone's own axis in pieces (a piecewise linear map with slope 1 outside
## the knots), so thickness stays and only the length between the joints changes. With one knot pair [0 -> 0, L_hly -> L_sgg]
## this is the plain stretch matrix SGG_rest_i * Stretch_i * inverse(HLY_rest_i) of the brief, clamped to the bone segment:
## a piece that sits beyond the child joint (a knee cap, a hand guard) is carried, not stretched. Normals use the inverse
## transpose of the warp slope.

const SGG_RIG := "res://models/mechs/sgg/sgg_rig.glb"
const HLY_RIG := "res://models/mechs/haliya/haliya_rig.glb"
const PART_NAMES: Array[String] = ["head", "core", "arm_l", "arm_r", "legs"]
## Height of the ground in the rig files (the soles of both leg parts are at Y = 0).
const GROUND_Y := 0.0
## Pelvis: the middle block up to this half width (m) keeps its size, everything outside spreads to the SGG hip joint.
const HIP_CENTER_KEEP := 0.30
## Torso: the chest keeps its size up to this fraction of the shoulder joint distance, then widens to the SGG shoulder joint.
const SHOULDER_KEEP_FRACTION := 0.5
## Torso: the waist zone (torso Y, m, HLY units) that stretches to close the gap to the pelvis (SGG pelvis to torso is longer).
const WAIST_LOW := -0.15
const WAIST_HIGH := 0.25
## Bones with no mesh of their own that carry plates: they follow another joint instead of their own offset.
const FOLLOW: Dictionary = {
	"sleeve_L": "upper_arm_L", "sleeve_R": "upper_arm_R",
	"skirt_side_L": "thigh_L", "skirt_side_R": "thigh_R",
	"skirt_front_L": "thigh_L", "skirt_front_R": "thigh_R",
	"skirt_back_L": "thigh_L", "skirt_back_R": "thigh_R",
}
## Limb bones that stretch along their own axis to the joint of their child.
const LIMB_CHILD: Dictionary = {
	"upper_arm_L": "forearm_L", "upper_arm_R": "forearm_R",
	"forearm_L": "hand_L", "forearm_R": "hand_R",
	"thigh_L": "shin_L", "thigh_R": "shin_R",
	"shin_L": "foot_L", "shin_R": "foot_R",
}

# Render settings.
## Camera view height (m) of the three-mech pictures (orthographic).
const VIEW_HEIGHT := 13.2
## Distance (m) between the mechs in the row.
const ROW_SPACING := 8.0
## View yaw (degrees) of the mechs for front, side and the 3/4 back picture.
const VIEWS: Dictionary = {"front": 0.0, "side": 90.0, "back34": 145.0}


## A piecewise linear map of one coordinate. Slope 1 outside the first and last knot.
class Warp1D:
	var ins := PackedFloat32Array()
	var outs := PackedFloat32Array()

	## Returns Vector2(mapped value, slope).
	func map(v: float) -> Vector2:
		var n := ins.size()
		if n == 0:
			return Vector2(v, 1.0)
		if v <= ins[0]:
			return Vector2(outs[0] + v - ins[0], 1.0)
		if v >= ins[n - 1]:
			return Vector2(outs[n - 1] + v - ins[n - 1], 1.0)
		for i in range(1, n):
			if v <= ins[i]:
				var k := (outs[i] - outs[i - 1]) / (ins[i] - ins[i - 1])
				return Vector2(outs[i - 1] + (v - ins[i - 1]) * k, k)
		return Vector2(v, 1.0)


	static func make(pairs: Array) -> Warp1D:
		var w := Warp1D.new()
		for pair: Array in pairs:
			w.ins.append(pair[0])
			w.outs.append(pair[1])
		return w


## The map of one bone from the HLY rest to the SGG rest.
class BoneWarp:
	var frame := Basis.IDENTITY
	var from_origin := Vector3.ZERO
	var to_origin := Vector3.ZERO
	var x_pos: Warp1D
	var x_neg: Warp1D
	var y: Warp1D
	var z: Warp1D

	## Returns [point, slope vector] for a point in skeleton space.
	func apply(p: Vector3) -> Array:
		var u := frame.transposed() * (p - from_origin)
		var slope := Vector3.ONE
		var ux := u.x
		var wx := x_pos if u.x >= 0.0 else x_neg
		if wx != null:
			var r := wx.map(absf(u.x))
			ux = r.x * signf(u.x)
			slope.x = r.y
		var uy := u.y
		if y != null:
			var r := y.map(u.y)
			uy = r.x
			slope.y = r.y
		var uz := u.z
		if z != null:
			var r := z.map(u.z)
			uz = r.x
			slope.z = r.y
		return [to_origin + frame * Vector3(ux, uy, uz), slope]


	func apply_normal(n: Vector3, slope: Vector3) -> Vector3:
		var l := frame.transposed() * n
		l = Vector3(l.x / slope.x, l.y / slope.y, l.z / slope.z)
		return frame * l


# ---------------------------------------------------------------------------------------------------------------------
# Library part (also used by measure_part_volumes.gd through preload).
# ---------------------------------------------------------------------------------------------------------------------

## Loads a scene and returns {"root": Node, "skeleton": Skeleton3D}.
static func load_scene(path: String) -> Dictionary:
	var root_node := (load(path) as PackedScene).instantiate()
	var skeleton := root_node.find_child("Skeleton3D", true, false) as Skeleton3D
	return {"root": root_node, "skeleton": skeleton}


## Bone name -> global rest transform.
static func read_rest(skeleton: Skeleton3D) -> Dictionary:
	var rest := {}
	for i in skeleton.get_bone_count():
		rest[skeleton.get_bone_name(i)] = skeleton.get_bone_global_rest(i)
	return rest


## The mesh instances under the skeleton.
static func skeleton_meshes(skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	return meshes


## Builds the bone maps (bone name -> BoneWarp) from the two rest poses.
static func build_maps(hly: Dictionary, sgg: Dictionary) -> Dictionary:
	var maps := {}
	for bone: String in hly:
		var m := BoneWarp.new()
		var follow: String = FOLLOW.get(bone, bone)
		m.from_origin = (hly[follow] as Transform3D).origin
		m.to_origin = (sgg[follow] as Transform3D).origin
		maps[bone] = m
	# Limbs: stretch along the own axis (bone frame) up to the child joint.
	for bone: String in LIMB_CHILD:
		var m: BoneWarp = maps[bone]
		var child: String = LIMB_CHILD[bone]
		m.frame = (hly[bone] as Transform3D).basis
		var l_h: float = ((hly[child] as Transform3D).origin - (hly[bone] as Transform3D).origin).length()
		var l_s: float = ((sgg[child] as Transform3D).origin - (sgg[bone] as Transform3D).origin).length()
		m.y = Warp1D.make([[0.0, 0.0], [l_h, l_s]])
	# Foot: the sole stays on the ground, the part below the ankle stretches to the SGG ankle height.
	for side in ["L", "R"]:
		var m: BoneWarp = maps["foot_" + side]
		var h: float = (hly["foot_" + side] as Transform3D).origin.y - GROUND_Y
		var s: float = (sgg["foot_" + side] as Transform3D).origin.y - GROUND_Y
		m.y = Warp1D.make([[-h, -s], [0.0, 0.0]])
	# Pelvis: the hips spread to the SGG hip joints.
	var pelvis: BoneWarp = maps["pelvis"]
	pelvis.x_pos = _lateral_warp(hly, sgg, "pelvis", "thigh_L", HIP_CENTER_KEEP, true)
	pelvis.x_neg = _lateral_warp(hly, sgg, "pelvis", "thigh_R", HIP_CENTER_KEEP, true)
	# Torso: shoulders spread, the chest and neck stretch between the joints, the waist stretches to meet the pelvis.
	var torso: BoneWarp = maps["torso"]
	torso.x_pos = _lateral_warp(hly, sgg, "torso", "upper_arm_L", SHOULDER_KEEP_FRACTION, false)
	torso.x_neg = _lateral_warp(hly, sgg, "torso", "upper_arm_R", SHOULDER_KEEP_FRACTION, false)
	var t_h: Vector3 = (hly["torso"] as Transform3D).origin
	var t_s: Vector3 = (sgg["torso"] as Transform3D).origin
	var shoulder_h: float = (hly["upper_arm_L"] as Transform3D).origin.y - t_h.y
	var shoulder_s: float = (sgg["upper_arm_L"] as Transform3D).origin.y - t_s.y
	var head_h: float = (hly["head"] as Transform3D).origin.y - t_h.y
	var head_s: float = (sgg["head"] as Transform3D).origin.y - t_s.y
	var gap_h: float = t_h.y - (hly["pelvis"] as Transform3D).origin.y
	var gap_s: float = t_s.y - (sgg["pelvis"] as Transform3D).origin.y
	# The torso's front-back place comes from the shoulder joints (the SGG torso bone sits 0.12 m forward of its shoulders, HLY's does not).
	var shoulder_dz := 0.5 * (((sgg["upper_arm_L"] as Transform3D).origin.z - (hly["upper_arm_L"] as Transform3D).origin.z)
			+ ((sgg["upper_arm_R"] as Transform3D).origin.z - (hly["upper_arm_R"] as Transform3D).origin.z))
	torso.to_origin.z = torso.from_origin.z + shoulder_dz
	torso.y = Warp1D.make([[WAIST_LOW, WAIST_LOW - (gap_s - gap_h)], [WAIST_HIGH, WAIST_HIGH],
			[shoulder_h, shoulder_s], [head_h, head_s]])
	return maps


## Lateral (X) warp of a bone for the side of the child joint. Distances are |x| from the bone origin.
static func _lateral_warp(hly: Dictionary, sgg: Dictionary, bone: String, child: String, keep: float, absolute: bool) -> Warp1D:
	var dx_h := absf((hly[child] as Transform3D).origin.x - (hly[bone] as Transform3D).origin.x)
	var dx_s := absf((sgg[child] as Transform3D).origin.x - (sgg[bone] as Transform3D).origin.x)
	var start := keep if absolute else keep * dx_h
	return Warp1D.make([[start, start], [dx_h, dx_s]])


## Skeleton-space rest vertices and normals of one surface of a skinned mesh: sum_i w_i (G_i bind_i) v.
static func rest_surface(mi: MeshInstance3D, surface: int, rest: Dictionary) -> Dictionary:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var skin := mi.skin
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_v.resize(vertices.size())
	if normals.size() == vertices.size():
		out_n.resize(vertices.size())
	var cache := {}
	for v in vertices.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var total := 0.0
		if bones.size() == vertices.size() * 4 and skin != null:
			for k in 4:
				var w := weights[v * 4 + k]
				if w <= 0.0:
					continue
				var bi := bones[v * 4 + k]
				if not cache.has(bi):
					cache[bi] = (rest[skin.get_bind_name(bi)] as Transform3D) * skin.get_bind_pose(bi)
				var xf: Transform3D = cache[bi]
				p += w * (xf * vertices[v])
				if out_n.size() > 0:
					n += w * (xf.basis * normals[v])
				total += w
		if total <= 0.0:
			p = vertices[v]
			n = normals[v] if out_n.size() > 0 else Vector3.ZERO
		else:
			p /= total
		out_v[v] = p
		if out_n.size() > 0:
			out_n[v] = n.normalized()
	return {"vertices": out_v, "normals": out_n, "arrays": arrays}


## Returns an ArrayMesh with the refit vertices (skeleton space). Bones, weights, UV and materials stay.
static func refit_mesh(mi: MeshInstance3D, hly_rest: Dictionary, maps: Dictionary) -> ArrayMesh:
	var result := ArrayMesh.new()
	var skin := mi.skin
	for surface in mi.mesh.get_surface_count():
		var rs := rest_surface(mi, surface, hly_rest)
		var arrays: Array = rs.arrays
		var vertices: PackedVector3Array = rs.vertices
		var normals: PackedVector3Array = rs.normals
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var new_v := PackedVector3Array()
		var new_n := PackedVector3Array()
		new_v.resize(vertices.size())
		if normals.size() > 0:
			new_n.resize(vertices.size())
		for v in vertices.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var total := 0.0
			for k in 4:
				var w := weights[v * 4 + k]
				if w <= 0.0:
					continue
				var bone_map: BoneWarp = maps[skin.get_bind_name(bones[v * 4 + k])]
				var r: Array = bone_map.apply(vertices[v])
				p += w * (r[0] as Vector3)
				if normals.size() > 0:
					n += w * bone_map.apply_normal(normals[v], r[1])
				total += w
			new_v[v] = p / total
			if normals.size() > 0:
				new_n[v] = n.normalized()
		arrays[Mesh.ARRAY_VERTEX] = new_v
		arrays[Mesh.ARRAY_NORMAL] = new_n if normals.size() > 0 else null
		arrays[Mesh.ARRAY_TANGENT] = null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, mi.mesh.surface_get_material(surface))
	result.resource_name = String(mi.name)
	return result


## A skin whose bind poses are the inverse SGG rest, so the refit vertices (skeleton space) show at the SGG rest unchanged.
static func sgg_skin(mi: MeshInstance3D, sgg_rest: Dictionary) -> Skin:
	var skin := Skin.new()
	for i in mi.skin.get_bind_count():
		var bone_name := mi.skin.get_bind_name(i)
		skin.add_named_bind(bone_name, (sgg_rest[bone_name] as Transform3D).affine_inverse())
	return skin


# ---------------------------------------------------------------------------------------------------------------------
# Tool part.
# ---------------------------------------------------------------------------------------------------------------------

var _hly_rest: Dictionary
var _sgg_rest: Dictionary
var _maps: Dictionary


func _initialize() -> void:
	var hly_rig := load_scene(HLY_RIG)
	var sgg_rig := load_scene(SGG_RIG)
	_hly_rest = read_rest(hly_rig.skeleton)
	_sgg_rest = read_rest(sgg_rig.skeleton)
	hly_rig.root.free()
	sgg_rig.root.free()
	_maps = build_maps(_hly_rest, _sgg_rest)
	_print_landing_check()
	_print_part_boxes()
	if DisplayServer.get_name() == "headless":
		print("headless: no pictures (run with xvfb-run and --rendering-driver opengl3)")
		quit()
		return
	await _render_all()
	quit()


## Where the HLY child joint lands when the parent bone's map is applied, against the SGG child joint. Hand and finger bones
## keep their size on purpose and the plate bones (sleeves, skirts) follow another joint, so they are left out.
func _print_landing_check() -> void:
	print("Joint landing: child joint of the HLY rig moved by the parent's map, error to the SGG joint (m)")
	var rig := load_scene(SGG_RIG)
	var skeleton: Skeleton3D = rig.skeleton
	var worst := 0.0
	for bone: String in _hly_rest:
		var parent := skeleton.get_bone_parent(skeleton.find_bone(bone))
		if parent < 0 or FOLLOW.has(bone):
			continue
		var parent_name := skeleton.get_bone_name(parent)
		if not _maps.has(parent_name) or not (parent_name in ["pelvis", "torso", "upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R",
				"thigh_L", "thigh_R", "shin_L", "shin_R"]):
			continue
		var landed: Vector3 = (_maps[parent_name] as BoneWarp).apply((_hly_rest[bone] as Transform3D).origin)[0]
		var err := landed.distance_to((_sgg_rest[bone] as Transform3D).origin)
		worst = maxf(worst, err)
		print("  %-12s on %-12s error %.2f" % [bone, parent_name, err])
	print("  worst %.2f m: torso on pelvis is the longer SGG waist, closed by the stretch of the torso's lower zone (WAIST_LOW..WAIST_HIGH);" % worst
			+ " head and shoulders differ by the Z offset of SGG's torso, which the maps do not move")
	rig.root.free()


func _print_part_boxes() -> void:
	for part in PART_NAMES:
		var scene := load_scene("res://models/mechs/haliya/haliya_%s.glb" % part)
		var now := AABB()
		var after := AABB()
		var first := true
		for mi in skeleton_meshes(scene.skeleton):
			var refit := refit_mesh(mi, _hly_rest, _maps)
			for s in mi.mesh.get_surface_count():
				for p in rest_surface(mi, s, _hly_rest).vertices:
					now = AABB(p, Vector3.ZERO) if first else now.expand(p)
					first = false
			var f2 := true
			for s in refit.get_surface_count():
				for p: Vector3 in refit.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					after = AABB(p, Vector3.ZERO) if (f2 and after.size == Vector3.ZERO and after.position == Vector3.ZERO) else after.expand(p)
					f2 = false
		print("%-6s HLY now %s -> refit %s" % [part, now, after])
		scene.root.free()


# Rendering ------------------------------------------------------------------------------------------------------------

var _camera: Camera3D
var _label: Label
var _mechs: Array[Node3D] = []


## One mech: a node with the rig's skeleton at rest and the given part meshes. Returns the Node3D.
func _make_mech(rig_path: String, mech_name: String, refit: bool, parts_mech: String) -> Node3D:
	var rig := load_scene(rig_path)
	var skeleton: Skeleton3D = rig.skeleton
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			skeleton.remove_child(child)
			child.free()
	for anim in rig.root.find_children("*", "AnimationPlayer", true, false):
		anim.free()
	for part in PART_NAMES:
		var scene := load_scene("res://models/mechs/%s/%s_%s.glb" % [parts_mech, parts_mech, part])
		for mi in skeleton_meshes(scene.skeleton):
			var added := MeshInstance3D.new()
			added.name = mi.name
			if refit:
				added.mesh = refit_mesh(mi, _hly_rest, _maps)
				added.skin = sgg_skin(mi, _sgg_rest)
			else:
				added.mesh = mi.mesh
				added.skin = mi.skin
			skeleton.add_child(added)
			added.skeleton = NodePath("..")
		scene.root.free()
	rig.root.name = mech_name
	var holder := Node3D.new()
	holder.name = mech_name + "_holder"
	holder.add_child(rig.root)
	return holder


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.82, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 28, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, -150, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.63, 0.65)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	# Height lines on a backdrop behind the row: every 2 m, a thicker one at 10 m.
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.35, 0.37, 0.42)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for h in range(0, 13, 2):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(40, 0.03 if h != 10 else 0.14, 0.02)
		line.mesh = box
		line.material_override = lm
		line.position = Vector3(0, h + 0.02, -9)
		root.add_child(line)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = VIEW_HEIGHT
	_camera.far = 200.0
	root.add_child(_camera)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	_label.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	_label.add_theme_constant_override("outline_size", 8)
	_label.position = Vector2(20, 14)
	layer.add_child(_label)
	var labels := Control.new()
	labels.name = "RowLabels"
	layer.add_child(labels)


func _render_all() -> void:
	var out_dir := OS.get_environment("OUT_DIR") if OS.has_environment("OUT_DIR") else ProjectSettings.globalize_path("res://docs")
	_build_stage()
	var specs := [
		["HLY now", HLY_RIG, "haliya", false],
		["HLY on SGG skeleton (preview)", SGG_RIG, "haliya", true],
		["SGG", SGG_RIG, "sgg", false],
	]
	for i in specs.size():
		var spec: Array = specs[i]
		var holder := _make_mech(spec[1], spec[0], spec[3], spec[2])
		holder.position = Vector3((i - 1) * ROW_SPACING, 0, 0)
		root.add_child(holder)
		_mechs.append(holder)
	await process_frame
	await process_frame
	for view: String in VIEWS:
		_set_view(VIEWS[view])
		_camera.size = VIEW_HEIGHT
		_camera.position = Vector3(0, VIEW_HEIGHT * 0.5 - 1.0, 40)
		_camera.rotation_degrees = Vector3.ZERO
		_set_row_labels(true)
		_label.text = "View: %s   (lines every 2 m, thick line at 10 m)" % view
		await _snap("%s/hly_refit_preview_%s.png" % [out_dir, view])
	await _render_closeup(out_dir)


func _set_view(yaw_deg: float) -> void:
	for holder in _mechs:
		holder.rotation_degrees = Vector3(0, yaw_deg, 0)


## Text under each mech: three Labels placed from the projected foot position.
func _set_row_labels(visible_on: bool) -> void:
	var labels: Control = _label.get_parent().get_node("RowLabels")
	for c in labels.get_children():
		c.queue_free()
	if not visible_on:
		return
	var names := ["HLY now", "HLY on SGG skeleton (preview)", "SGG"]
	for i in names.size():
		var l := Label.new()
		l.text = names[i]
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		l.add_theme_color_override("font_outline_color", Color(1, 1, 1))
		l.add_theme_constant_override("outline_size", 6)
		var screen := _camera.unproject_position(Vector3((i - 1) * ROW_SPACING, 0, 0))
		l.position = Vector2(screen.x - 200, 848)
		l.size = Vector2(400, 40)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(l)


func _snap(path: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if path != "":
		image.save_png(path)
		print("wrote ", path, " ", image.get_size())
	return image


## Close-ups where the refit stretches the most: rows forearm and hand, neck and shoulders, hips and waist.
## Left column HLY now, right column the refit. Each cell is a full render, the sheet is 1600 x 1350.
func _render_closeup(out_dir: String) -> void:
	_label.add_theme_font_size_override("font_size", 44)
	_set_view(0.0)
	_set_row_labels(false)
	# [title, bone a, bone b, offset, view height]: the camera looks at the middle of the two bones.
	var regions := [
		["Forearm and hand (left arm)", "forearm_L", "hand_L", Vector3(0, 0, 0), 3.6],
		["Neck and shoulders", "head", "head", Vector3(0, -0.9, 0), 4.2],
		["Hips and waist", "pelvis", "pelvis", Vector3(0, -0.3, 0), 3.8],
		["Knee, ankle and foot (left leg)", "shin_L", "foot_L", Vector3(0, -0.2, 0), 4.4],
	]
	var sheet := Image.create(1600, 450 * regions.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color.WHITE)
	# Cell column: HLY now (mech 0, at -ROW_SPACING) and the refit (mech 1, at 0), each alone in the picture.
	var cells := [[0, _hly_rest], [1, _sgg_rest]]
	for r in regions.size():
		var region: Array = regions[r]
		for c in cells.size():
			var mech_index: int = cells[c][0]
			var rest: Dictionary = cells[c][1]
			for i in _mechs.size():
				_mechs[i].visible = i == mech_index
			var a: Vector3 = (rest[region[1]] as Transform3D).origin
			var b: Vector3 = (rest[region[2]] as Transform3D).origin
			var centre: Vector3 = (a + b) * 0.5 + (region[3] as Vector3)
			var x_offset := (mech_index - 1) * ROW_SPACING
			_camera.size = region[4]
			_camera.rotation_degrees = Vector3.ZERO
			_camera.position = Vector3(centre.x + x_offset, centre.y, 40)
			_label.text = "%s   %s" % [region[0], "HLY now" if c == 0 else "HLY on SGG skeleton (preview)"]
			var image := await _snap("")
			image.resize(800, 450, Image.INTERPOLATE_BILINEAR)
			image.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(image, Rect2i(0, 0, 800, 450), Vector2i(c * 800, r * 450))
	for holder in _mechs:
		holder.visible = true
	sheet.save_png("%s/hly_refit_preview_closeup.png" % out_dir)
	print("wrote ", out_dir, "/hly_refit_preview_closeup.png")
