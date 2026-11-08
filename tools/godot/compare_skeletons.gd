extends SceneTree
## Skeleton comparison (user request 2026-11-08: "show me and compare the skeletons of SGG and HLY"). Loads both rig
## files (A, B: res paths; default models/mechs/sgg/sgg_rig.glb and models/mechs/haliya/haliya_rig.glb), reads each
## Skeleton3D's rest pose and writes OUT (JSON): per mech the bones with parent, local rest offset and rotation
## (degrees), global rest place, length to the first child. Prints the bones only in one rig, the bones whose parent
## differs and the bones whose rest rotation differs.
##   OUT=/tmp/skeletons.json godot --headless --path . --script res://tools/godot/compare_skeletons.gd

## Two bone offsets closer than this (m) count as the same.
const OFFSET_TOLERANCE := 0.001


func _initialize() -> void:
	var a := OS.get_environment("A") if OS.has_environment("A") else "res://models/mechs/sgg/sgg_rig.glb"
	var b := OS.get_environment("B") if OS.has_environment("B") else "res://models/mechs/haliya/haliya_rig.glb"
	var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "user://skeletons.json"
	var result := {"a": _read(a), "b": _read(b)}
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
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
	var offset_differ := []
	for name: String in ba:
		if bb.has(name) and _v(ba[name].offset).distance_to(_v(bb[name].offset)) > OFFSET_TOLERANCE:
			offset_differ.append("%s %.3f" % [name, _v(ba[name].offset).distance_to(_v(bb[name].offset))])
	print("parents differ: %s" % [parents_differ])
	print("rest rotations differ (deg): %s" % [rot_differ])
	print("offsets differ (m, more than %.3f): %d %s" % [OFFSET_TOLERANCE, offset_differ.size(), offset_differ])
	print("wrote ", out)
	quit()


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _read(path: String) -> Dictionary:
	var model := (load(path) as PackedScene).instantiate()
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
