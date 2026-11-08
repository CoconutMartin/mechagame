extends SceneTree
## Haliya HLY-101 on the SGG-101 skeleton (user decision 2026-11-08, DESIGN "HLY refit decision"). Reads the light-rig export of
## haliya.blend (models/mechs/haliya/source_light_rig/, written by tools/blender/export_mech_parts.py) and writes the part files
## models/mechs/haliya/haliya_{head,core,arm_l,arm_r,legs}.glb on the SGG bone offsets. The rig file is make_haliya_rig.gd.
##   godot --headless --path . --script res://tools/godot/refit_haliya_parts.gd
## Then import (godot --headless --path . --import) and rebuild the mech scene (MECH=haliya build_sanggigilid.gd).
##
## Every piece keeps its bone and its shape; only its place changes, except where the skeleton is longer:
##   head            moves with the head joint.
##   core            moves with the shoulder joints (the chest holds the shoulder balls): left pieces with the left shoulder, right
##                   pieces with the right one, middle pieces with the middle. The dark centre block widens to fill the slot.
##   arms            pauldrons, shoulder balls, elbows and wrists move with their joints; the upper arm and forearm armor stretch
##                   along the bone to the SGG joint (forearm 1.45 -> 1.98 m); hands and fingers move with their own bones.
##   legs            thighs and shins stretch along the bone; the skirts move with the hip joints; the pelvis spreads to the SGG
##                   hip width outside its middle block; the feet stay on the ground, and the ankle wheel and guards go up
##                   with the ankle joint (0.80 -> 1.05 m).
## New pieces fill the longer spans (haliya_connectors.gd): the waist between the pelvis and the chest, the neck between the
## chest and the head, and an ankle block on each foot.

const Refit := preload("res://tools/godot/preview_refit_parts.gd")
const Kit := preload("res://tools/godot/haliya_mesh_kit.gd")
const Connectors := preload("res://tools/godot/haliya_connectors.gd")
const SOURCE_DIR := "res://models/mechs/haliya/source_light_rig/"
const OUT_DIR := "res://models/mechs/haliya/"
const SGG_RIG := "res://models/mechs/sgg/sgg_rig.glb"
const PARTS: Array[String] = ["head", "core", "arm_l", "arm_r", "legs"]
## Core pieces that fill the slot between the left and right chest pieces: they widen by the shoulder spread.
const FILL_PIECES: Array[String] = ["Core_center"]
## Foot pieces around the ankle joint: they go up with the joint. The other foot pieces keep the sole on the ground.
const ANKLE_PIECES: Array[String] = ["Legs_ankle", "Legs_ankle_guard", "Legs_ankle_guard_in"]
## Forearm pieces at the elbow (they move with the elbow, no stretch) and at the wrist (they move with the wrist).
const ELBOW_PIECES: Array[String] = ["Arm_elbow"]
const WRIST_PIECES: Array[String] = ["Arm_wrist"]
## Pelvis pieces that move with the pelvis and do not spread.
const PELVIS_RIGID: Array[String] = ["Skirt_back_tip", "Skirt_back_top"]

var _h: Dictionary
var _s: Dictionary
var _pelvis_map: Refit.BoneWarp
var _limb_maps: Dictionary
## Part -> Array of pieces {name, bone, surfaces: [{arrays, material}], bind_names}.
var _pieces: Dictionary = {}
## Piece name -> its box at the SGG rest after the refit.
var _boxes: Dictionary = {}
## Material name -> Material, from the source files.
var _materials: Dictionary = {}


func _initialize() -> void:
	var sgg := (load(SGG_RIG) as PackedScene).instantiate()
	_s = Refit.read_rest(sgg.find_child("Skeleton3D", true, false) as Skeleton3D)
	for part in PARTS:
		var source := load_glb(SOURCE_DIR + "haliya_%s.glb" % part)
		var skeleton := source.find_child("*", true, false) as Skeleton3D
		for node in source.find_children("*", "Skeleton3D", true, false):
			skeleton = node
		if _h.is_empty():
			_h = Refit.read_rest(skeleton)
			var maps := Refit.build_maps(_h, _s)
			_pelvis_map = maps["pelvis"]
			_limb_maps = maps
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
	var added := Connectors.build(_boxes, _s, _materials)
	for part: String in added:
		for piece: Dictionary in added[part]:
			(_pieces[part] as Array).append(piece)
			_boxes[piece.name] = _box_of(piece)
	for part in PARTS:
		_write_part(sgg, part)
	sgg.free()
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
	if map.has_meta(&"fill"):
		_set_fill(map, mi)
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


## The map of one piece from the HLY rest to the SGG rest.
func _rule(part: String, name: String, bone: String) -> Refit.BoneWarp:
	var side := _side(name, bone)
	var base := _base_name(name)
	match part:
		"head":
			return _shift(_delta("head"))
		"core":
			var mid := (_delta("upper_arm_L") + _delta("upper_arm_R")) * 0.5
			if base in FILL_PIECES:
				return _fill(mid, (_delta("upper_arm_L").x - _delta("upper_arm_R").x) * 0.5)
			if side == "":
				return _shift(mid)
			return _shift(_delta("upper_arm_" + side))
		"arm_l", "arm_r":
			if bone.begins_with("sleeve_"):
				return _shift(_delta("upper_arm_" + side))
			if bone.begins_with("upper_arm_"):
				return _limb_maps[bone]
			if bone.begins_with("forearm_"):
				if base in ELBOW_PIECES:
					return _limb_end(bone, false)
				if base in WRIST_PIECES:
					return _limb_end(bone, true)
				return _limb_maps[bone]
			return _shift(_delta(bone))
		"legs":
			if bone == "pelvis":
				return _shift(_delta("pelvis")) if base in PELVIS_RIGID else _pelvis_map
			if bone.begins_with("skirt_side_"):
				return _shift(_delta("thigh_" + side))
			if bone.begins_with("thigh_") or bone.begins_with("shin_"):
				return _limb_maps[bone]
			if bone.begins_with("foot_"):
				var d := _delta(bone)
				return _shift(d if base in ANKLE_PIECES else Vector3(d.x, 0.0, d.z))
	push_error("no refit rule for %s %s on %s" % [part, name, bone])
	return _shift(Vector3.ZERO)


## "L", "R" or "" from the piece name (Core_rib_back_L0, Arm_upper_core_L) or else its bone.
static func _side(name: String, bone: String) -> String:
	for tag in ["L", "R"]:
		var at := name.rfind("_" + tag)
		if at >= 0 and (at + 2 == name.length() or name.substr(at + 2).is_valid_int()):
			return tag
	if bone.ends_with("_L") or bone.ends_with("_R"):
		return bone.right(1)
	return ""


## The piece name without its side (Legs_ankle_guard_in_L -> Legs_ankle_guard_in).
static func _base_name(name: String) -> String:
	for tag in ["_L", "_R"]:
		var at := name.rfind(tag)
		if at >= 0 and (at + 2 == name.length() or name.substr(at + 2).is_valid_int()):
			return name.substr(0, at)
	return name


func _delta(bone: String) -> Vector3:
	return (_s[bone] as Transform3D).origin - (_h[bone] as Transform3D).origin


func _shift(d: Vector3) -> Refit.BoneWarp:
	var m := Refit.BoneWarp.new()
	m.to_origin = d
	return m


## A limb piece at one end of its bone: it moves with the elbow (wrist false) or with the wrist (wrist true), with no stretch.
func _limb_end(bone: String, wrist: bool) -> Refit.BoneWarp:
	var m := Refit.BoneWarp.new()
	var stretch: Refit.BoneWarp = _limb_maps[bone]
	m.frame = stretch.frame
	m.from_origin = stretch.from_origin
	m.to_origin = stretch.to_origin
	if wrist:
		var child := "hand_" + bone.right(1)
		var l_h := ((_h[child] as Transform3D).origin - (_h[bone] as Transform3D).origin).length()
		var l_s := ((_s[child] as Transform3D).origin - (_s[bone] as Transform3D).origin).length()
		m.y = Refit.Warp1D.make([[0.0, l_s - l_h]])
	return m


## A middle piece that fills the slot between the side pieces: it moves with the middle and gets wider by spread on each side.
func _fill(mid: Vector3, spread: float) -> Refit.BoneWarp:
	var m := Refit.BoneWarp.new()
	m.to_origin = mid
	m.set_meta(&"fill", spread)
	return m


## A fill piece widens about its own middle: its half width comes from its rest vertices.
func _set_fill(map: Refit.BoneWarp, mi: MeshInstance3D) -> void:
	var box := AABB()
	var first := true
	for s in mi.mesh.get_surface_count():
		for p: Vector3 in Refit.rest_surface(mi, s, _h).vertices:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	var spread: float = map.get_meta(&"fill")
	var half := box.size.x * 0.5
	var centre := Vector3(box.get_center().x, 0.0, 0.0)
	map.from_origin = centre
	map.to_origin = centre + map.to_origin
	map.x_pos = Refit.Warp1D.make([[0.0, 0.0], [half, half + spread]])
	map.x_neg = Refit.Warp1D.make([[0.0, 0.0], [half, half + spread]])


func _box_of(piece: Dictionary) -> AABB:
	var box := AABB()
	var first := true
	for surface: Dictionary in piece.surfaces:
		for p: Vector3 in (surface.arrays as Array)[Mesh.ARRAY_VERTEX]:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	return box


func _print_deltas() -> void:
	for bone in ["pelvis", "torso", "head", "upper_arm_L", "upper_arm_R", "thigh_L", "thigh_R", "foot_L", "foot_R"]:
		print("delta %-12s %s" % [bone, _delta(bone).snapped(Vector3.ONE * 0.001)])


## Writes one part file: the SGG rig at rest with the part's pieces (no clips).
func _write_part(sgg: Node, part: String) -> void:
	var root := sgg.duplicate() as Node3D
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
			skin.add_named_bind(bind_name, (_s[bind_name] as Transform3D).affine_inverse())
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
