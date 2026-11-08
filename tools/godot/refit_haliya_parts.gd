extends SceneTree
## Haliya HLY-101 with its legs aligned to the SGG-101 skeleton (user choice 2026-11-08, "Legs only"; DESIGN "HLY refit decision").
## Reads the light-rig export of haliya.blend (models/mechs/haliya/source_light_rig/, written by tools/blender/export_mech_parts.py)
## and writes the part files models/mechs/haliya/haliya_{head,core,arm_l,arm_r,legs}.glb on the legs-aligned rest
## (tools/godot/haliya_legs_aligned_rest.gd: SGG leg chain, Haliya's own offsets everywhere else). The rig file is make_haliya_rig.gd.
##   godot --headless --path . --script res://tools/godot/refit_haliya_parts.gd
## Then import (godot --headless --path . --import) and rebuild the mech scene (MECH=haliya build_sanggigilid.gd).
##
## Every piece keeps its bone and its shape; only its place changes, except on the thighs and shins:
##   head, core, arms  move with their bone (the pelvis is 0.04 m lower); shapes, the hip width, waist, neck, shoulders and arm
##                     lengths stay Haliya's own.
##   pelvis, skirts    move with their bone.
##   thighs, shins     fit the SGG lengths along the bone (thigh 2.98 -> 2.75 m, shin 2.26 -> 2.18 m): the ends at the joints stay
##                     rigid (HIP_RIGID, THIGH_KNEE_RIGID, SHIN_KNEE_RIGID, SHIN_ANKLE_RIGID), the span between them gets shorter.
##   feet              stay on the ground; the ankle wheel and guards go up with the ankle joint (0.80 -> 1.05 m), and a new
##                     ankle block fills the gap (haliya_connectors.gd).

const Refit := preload("res://tools/godot/preview_refit_parts.gd")
const Connectors := preload("res://tools/godot/haliya_connectors.gd")
const Rest := preload("res://tools/godot/haliya_legs_aligned_rest.gd")
const SOURCE_DIR := "res://models/mechs/haliya/source_light_rig/"
const OUT_DIR := "res://models/mechs/haliya/"
const SGG_RIG := "res://models/mechs/sgg/sgg_rig.glb"
const PARTS: Array[String] = ["head", "core", "arm_l", "arm_r", "legs"]
## Foot pieces around the ankle joint: they go up with the joint. The other foot pieces keep the sole on the ground.
const ANKLE_PIECES: Array[String] = ["Legs_ankle", "Legs_ankle_guard", "Legs_ankle_guard_in"]
## Thigh: length (m) from the hip joint down that stays rigid (the hip ball, Legs_hip).
const HIP_RIGID := 0.30
## Thigh: length (m) up from the knee joint that stays rigid (the knee end of the thigh armor).
const THIGH_KNEE_RIGID := 0.30
## Shin: length (m) from the knee joint down that stays rigid (the knee ball, caps and block).
const SHIN_KNEE_RIGID := 0.30
## Shin: length (m) up from the ankle joint that stays rigid (the ankle cap).
const SHIN_ANKLE_RIGID := 0.45

## Bone -> global rest of the light-rig export (HLY) and of the legs-aligned rest (target).
var _h: Dictionary
var _t: Dictionary
## Part -> Array of pieces {name, bone, surfaces: [{arrays, material}], bind_names}.
var _pieces: Dictionary = {}
## Piece name -> its box at the target rest after the refit.
var _boxes: Dictionary = {}
## Material name -> Material, from the source files.
var _materials: Dictionary = {}


func _initialize() -> void:
	var rig := (load(SGG_RIG) as PackedScene).instantiate()
	var source_rig := load_glb(SOURCE_DIR + "haliya_rig.glb")
	var haliya := Rest.skeleton_of(source_rig)
	_h = Refit.read_rest(haliya)
	Rest.apply(rig.find_child("Skeleton3D", true, false) as Skeleton3D, haliya)
	_t = Refit.read_rest(rig.find_child("Skeleton3D", true, false) as Skeleton3D)
	source_rig.free()
	for part in PARTS:
		var source := load_glb(SOURCE_DIR + "haliya_%s.glb" % part)
		var skeleton := Rest.skeleton_of(source)
		_pieces[part] = []
		for mi in Refit.skeleton_meshes(skeleton):
			(_pieces[part] as Array).append(_refit_piece(part, mi))
		source.free()
	_print_deltas()
	if OS.has_environment("BOXES"):
		for name: String in _boxes:
			if name.matchn(OS.get_environment("BOXES")):
				var b: AABB = _boxes[name]
				print("box %-24s %s .. %s" % [name, b.position.snapped(Vector3.ONE * 0.01), b.end.snapped(Vector3.ONE * 0.01)])
	var added := Connectors.build(_boxes, _t, _materials)
	for part: String in added:
		for piece: Dictionary in added[part]:
			(_pieces[part] as Array).append(piece)
			_boxes[piece.name] = _box_of(piece)
	for part in PARTS:
		_write_part(rig, part)
	rig.free()
	quit()


## Loads a .glb from a folder Godot does not import. The skins get bone names, as in an imported file.
static func load_glb(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		push_error("cannot read %s: %s" % [path, error_string(err)])
		return null
	var scene := doc.generate_scene(state)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var skeleton := mi.get_parent() as Skeleton3D
		if mi.skin == null or skeleton == null:
			continue
		var named := Skin.new()
		for i in mi.skin.get_bind_count():
			var bind_name := mi.skin.get_bind_name(i)
			if bind_name == &"":
				bind_name = StringName(skeleton.get_bone_name(mi.skin.get_bind_bone(i)))
			named.add_named_bind(bind_name, mi.skin.get_bind_pose(i))
		mi.skin = named
	return scene


func _refit_piece(part: String, mi: MeshInstance3D) -> Dictionary:
	var name := String(mi.name)
	var bone := _main_bone(mi)
	var map := _rule(part, name, bone)
	var piece := {"name": name, "bone": bone, "surfaces": [], "bind_names": []}
	for i in mi.skin.get_bind_count():
		(piece.bind_names as Array).append(String(mi.skin.get_bind_name(i)))
	for s in mi.mesh.get_surface_count():
		var rs := Refit.rest_surface(mi, s, _h)
		var arrays: Array = rs.arrays
		var vertices: PackedVector3Array = rs.vertices
		var normals: PackedVector3Array = rs.normals
		var new_v := PackedVector3Array()
		var new_n := PackedVector3Array()
		new_v.resize(vertices.size())
		new_n.resize(normals.size())
		for v in vertices.size():
			var r: Array = map.apply(vertices[v])
			new_v[v] = r[0]
			if normals.size() > 0:
				new_n[v] = map.apply_normal(normals[v], r[1]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = new_v
		arrays[Mesh.ARRAY_NORMAL] = new_n if normals.size() > 0 else null
		arrays[Mesh.ARRAY_TANGENT] = null
		var material := mi.mesh.surface_get_material(s)
		if material != null and not _materials.has(material.resource_name):
			_materials[material.resource_name] = material
		(piece.surfaces as Array).append({"arrays": arrays, "material": material})
	_boxes[name] = _box_of(piece)
	return piece


## The bone with the most weight in a mesh (the Haliya pieces are rigid: one bone each).
func _main_bone(mi: MeshInstance3D) -> String:
	var totals := {}
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in bones.size():
			var bone_name := String(mi.skin.get_bind_name(bones[i]))
			totals[bone_name] = float(totals.get(bone_name, 0.0)) + weights[i]
	var best := ""
	for bone_name: String in totals:
		if best == "" or totals[bone_name] > totals[best]:
			best = bone_name
	return best


## The map of one piece from the HLY rest to the target rest.
func _rule(part: String, name: String, bone: String) -> Refit.BoneWarp:
	if not _t.has(bone):
		push_error("no bone %s for %s %s" % [bone, part, name])
		return _shift(Vector3.ZERO)
	if part == "legs":
		if bone.begins_with("thigh_"):
			return _limb(bone, "shin_" + bone.right(1), HIP_RIGID, THIGH_KNEE_RIGID)
		if bone.begins_with("shin_"):
			return _limb(bone, "foot_" + bone.right(1), SHIN_KNEE_RIGID, SHIN_ANKLE_RIGID)
		if bone.begins_with("foot_"):
			var d := _delta(bone)
			return _shift(d if _base_name(name) in ANKLE_PIECES else Vector3(d.x, 0.0, d.z))
	return _shift(_delta(bone))


## The piece name without its side (Legs_ankle_guard_in_L -> Legs_ankle_guard_in).
static func _base_name(name: String) -> String:
	for tag in ["_L", "_R"]:
		var at := name.rfind(tag)
		if at >= 0 and (at + 2 == name.length() or name.substr(at + 2).is_valid_int()):
			return name.substr(0, at)
	return name


func _delta(bone: String) -> Vector3:
	return (_t[bone] as Transform3D).origin - (_h[bone] as Transform3D).origin


func _shift(d: Vector3) -> Refit.BoneWarp:
	var m := Refit.BoneWarp.new()
	m.to_origin = d
	return m


## A limb piece: it moves with its joint and fits the target length along the bone (local Y). The first `top` m from the joint and
## the last `low` m before the child joint stay rigid; the span between them takes the change of length.
func _limb(bone: String, child: String, top: float, low: float) -> Refit.BoneWarp:
	var m := Refit.BoneWarp.new()
	m.frame = (_h[bone] as Transform3D).basis
	m.from_origin = (_h[bone] as Transform3D).origin
	m.to_origin = (_t[bone] as Transform3D).origin
	var l_h := ((_h[child] as Transform3D).origin - (_h[bone] as Transform3D).origin).length()
	var l_t := ((_t[child] as Transform3D).origin - (_t[bone] as Transform3D).origin).length()
	m.y = Refit.Warp1D.make([[0.0, 0.0], [top, top], [l_h - low, l_t - low], [l_h, l_t]])
	return m


func _box_of(piece: Dictionary) -> AABB:
	var box := AABB()
	var first := true
	for surface: Dictionary in piece.surfaces:
		for p: Vector3 in (surface.arrays as Array)[Mesh.ARRAY_VERTEX]:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	return box


func _print_deltas() -> void:
	for bone in ["pelvis", "torso", "head", "upper_arm_L", "upper_arm_R", "thigh_L", "thigh_R", "shin_L", "foot_L", "foot_R"]:
		print("delta %-12s %s" % [bone, _delta(bone).snapped(Vector3.ONE * 0.001)])
	for side in ["L", "R"]:
		var thigh := ((_t["shin_" + side] as Transform3D).origin - (_t["thigh_" + side] as Transform3D).origin).length()
		var shin := ((_t["foot_" + side] as Transform3D).origin - (_t["shin_" + side] as Transform3D).origin).length()
		print("legs %s: thigh %.3f shin %.3f ankle %.3f m" % [side, thigh, shin, (_t["foot_" + side] as Transform3D).origin.y])


## Writes one part file: the rig at the target rest with the part's pieces (no clips).
func _write_part(rig: Node, part: String) -> void:
	var root := rig.duplicate() as Node3D
	root.name = "haliya_" + part
	for player in root.find_children("*", "AnimationPlayer", true, false):
		player.get_parent().remove_child(player)
		player.free()
	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	for child in skeleton.get_children():
		skeleton.remove_child(child)
		child.free()
	for piece: Dictionary in _pieces[part]:
		var mesh := ArrayMesh.new()
		for surface: Dictionary in piece.surfaces:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, surface.material)
		mesh.resource_name = piece.name
		var skin := Skin.new()
		for bind_name: String in piece.bind_names:
			skin.add_named_bind(bind_name, (_t[bind_name] as Transform3D).affine_inverse())
		var mi := MeshInstance3D.new()
		mi.name = piece.name
		mi.mesh = mesh
		mi.skin = skin
		skeleton.add_child(mi)
		mi.owner = root
		mi.skeleton = NodePath("..")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	var path := OUT_DIR + "haliya_%s.glb" % part
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	print("wrote %s: %d pieces, %s" % [path, (_pieces[part] as Array).size(), error_string(err)])
	root.free()
