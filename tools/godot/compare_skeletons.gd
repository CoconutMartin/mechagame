extends SceneTree
## Skeleton comparison (user request 2026-11-08: "show me and compare the skeletons of SGG and HLY"). Loads both rig
## files (A, B: res paths; default models/mechs/sgg/sgg_rig.glb and models/mechs/haliya/haliya_rig.glb), reads each
## Skeleton3D's rest pose and writes OUT (JSON): per mech the bones with parent, local rest offset and rotation
## (degrees), global rest place, length to the first child. Prints the bones only in one rig, the bones whose parent
## differs and the bones whose rest rotation differs.
## Also compares B with ORIGINAL (default: Haliya's light-rig export, models/mechs/haliya/source_light_rig/haliya_rig.glb, read
## without import; ORIGINAL="" skips it) and prints the leg chain of each rig (pelvis height, hip width, thigh, shin, ankle height),
## for the legs-only refit (user choice 2026-11-08): B should differ from A only above the pelvis, in the arms and in the hip width,
## and from ORIGINAL only in the leg chain.
##   OUT=/tmp/skeletons.json godot --headless --path . --script res://tools/godot/compare_skeletons.gd

## Two bone offsets closer than this (m) count as the same.
const OFFSET_TOLERANCE := 0.001
const DEFAULT_ORIGINAL := "res://models/mechs/haliya/source_light_rig/haliya_rig.glb"
## The leg chain the legs-only refit takes from SGG (DESIGN "HLY refit decision"): pelvis, thighs (all but the side offset), shins,
## feet and the leg IK helpers (moved with the hip width).
const LEG_CHAIN: Array[String] = ["pelvis", "thigh_L", "thigh_R", "shin_L", "shin_R", "foot_L", "foot_R", "foot_ctrl_L", "foot_ctrl_R",
		"knee_pole_L", "knee_pole_R"]


func _initialize() -> void:
	var a := OS.get_environment("A") if OS.has_environment("A") else "res://models/mechs/sgg/sgg_rig.glb"
	var b := OS.get_environment("B") if OS.has_environment("B") else "res://models/mechs/haliya/haliya_rig.glb"
	var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "user://skeletons.json"
	var result := {"a": _read(a), "b": _read(b)}
	var ba: Dictionary = result.a.bones
	var bb: Dictionary = result.b.bones
	var only_a := ba.keys().filter(func(n: String) -> bool: return not bb.has(n))
	var only_b := bb.keys().filter(func(n: String) -> bool: return not ba.has(n))
	print("A %s: %d bones, B %s: %d bones; only in A %s, only in B %s" % [a, ba.size(), b, bb.size(), only_a, only_b])
	var parents_differ := []
	var rot_differ := []
	for name: String in ba:
		if not bb.has(name):
			continue
		if ba[name].parent != bb[name].parent:
			parents_differ.append(name)
		var qa := Quaternion.from_euler(_v(ba[name].rest_rot_deg) * PI / 180.0)
		var qb := Quaternion.from_euler(_v(bb[name].rest_rot_deg) * PI / 180.0)
		var angle := rad_to_deg(qa.angle_to(qb))
		if angle > 0.5:
			rot_differ.append("%s %.1f" % [name, angle])
	print("parents differ: %s" % [parents_differ])
	print("rest rotations differ (deg): %s" % [rot_differ])
	_print_offsets("B vs A", ba, bb)
	var original := OS.get_environment("ORIGINAL") if OS.has_environment("ORIGINAL") else DEFAULT_ORIGINAL
	var bo := {}
	if original != "":
		result["original"] = _read(original)
		bo = result.original.bones
		_print_offsets("B vs ORIGINAL", bo, bb)
	var summaries := {"A": ba, "B": bb, "ORIGINAL": bo}
	for label: String in summaries:
		var bones: Dictionary = summaries[label]
		if not bones.is_empty():
			print("%-8s %s" % [label, _leg_summary(bones)])
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("wrote ", out)
	quit()


## Prints the bones whose local offset differs (second minus first, in the parent frame), split into the leg chain and the rest.
func _print_offsets(label: String, ba: Dictionary, bb: Dictionary) -> void:
	var legs := []
	var others := []
	for name: String in ba:
		if not bb.has(name):
			continue
		var d := _v(bb[name].offset) - _v(ba[name].offset)
		if d.length() > OFFSET_TOLERANCE:
			(legs if name in LEG_CHAIN else others).append("%s %.3f (%.3f, %.3f, %.3f)" % [name, d.length(), d.x, d.y, d.z])
	print("%s offsets differ (m, more than %.3f): leg chain %d %s" % [label, OFFSET_TOLERANCE, legs.size(), legs])
	print("%s offsets differ: other bones %d %s" % [label, others.size(), others])


## Pelvis height, hip width, thigh and shin length and ankle height (left / right), torso, head and shoulder height, m.
func _leg_summary(bones: Dictionary) -> String:
	var text := "pelvis %.3f hip width %.3f" % [_v(bones.pelvis.global).y, _v(bones.thigh_L.global).x - _v(bones.thigh_R.global).x]
	for side in ["L", "R"]:
		text += " | %s thigh %.3f shin %.3f ankle %.3f" % [side, _v(bones["shin_" + side].offset).length(),
				_v(bones["foot_" + side].offset).length(), _v(bones["foot_" + side].global).y]
	text += " | torso %.3f head %.3f shoulders %.3f" % [_v(bones.torso.global).y, _v(bones.head.global).y, _v(bones.upper_arm_L.global).y]
	return text


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _read(path: String) -> Dictionary:
	var model: Node
	if ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate()
	else:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_file(ProjectSettings.globalize_path(path), state)
		model = doc.generate_scene(state)
	root.add_child(model)
	var skeleton := model.find_child("*", true, false) as Skeleton3D
	if skeleton == null:
		for node in model.find_children("*", "Skeleton3D", true, false):
			skeleton = node as Skeleton3D
			break
	var bones := {}
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		var global := skeleton.get_bone_global_rest(i)
		var children := skeleton.get_bone_children(i)
		var length := skeleton.get_bone_rest(children[0]).origin.length() if children.size() > 0 else 0.0
		var parent := skeleton.get_bone_parent(i)
		var euler := rest.basis.get_euler() * 180.0 / PI
		bones[skeleton.get_bone_name(i)] = {
			"parent": skeleton.get_bone_name(parent) if parent >= 0 else "",
			"offset": [rest.origin.x, rest.origin.y, rest.origin.z],
			"offset_len": rest.origin.length(),
			"rest_rot_deg": [euler.x, euler.y, euler.z],
			"global": [global.origin.x, global.origin.y, global.origin.z],
			"length": length,
		}
	var scale := skeleton.transform.basis.get_scale()
	model.queue_free()
	return {"path": path, "skeleton_scale": [scale.x, scale.y, scale.z], "bones": bones}
