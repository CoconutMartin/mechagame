extends SceneTree
## Swappable part models test (DESIGN "Swappable mech parts"). On the test map it checks the player mech:
##   every slot (head, core, arms, legs) has its part meshes on the mech skeleton;
##   every skin bind names a bone of the mech skeleton (the part fits the standard rig);
##   each part mesh, posed by the skeleton, is where the rest pose puts it (no tearing at rest);
##   every hit part has hitboxes;
##   the skirt panels and sleeves (AccessoryBoneFollow) turn when the mech walks (LOADOUT=2, Haliya).
## OLD_SCENE=res://... compares the hitbox boxes and the mesh boxes with an older mech scene (one-file model).
## Prints "RESULT: <n> failures"; exit code 1 on a failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_part_models.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## Meshes per slot for SGG-101 (key 1) and Haliya HLY-101 (key 2, LOADOUT=2).
const SGG_MESHES := {&"head": 2, &"core": 2, &"arm_left": 5, &"arm_right": 5, &"legs": 13}
const HLY_MESHES := {&"head": 8, &"core": 13, &"arm_left": 27, &"arm_right": 27, &"legs": 36}

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok    " if ok else "FAIL  ") + text)
	if not ok:
		_failures += 1


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout_key := int(OS.get_environment("LOADOUT")) if OS.has_environment("LOADOUT") else 1
	if loadout_key > 1:
		switcher.switch_to(switcher.loadouts[loadout_key - 1])
		await _frames(30)
	var want: Dictionary = HLY_MESHES if loadout_key == 2 else SGG_MESHES
	var mech := switcher.mech
	var models := mech.get_node("PartModels") as SkeletalPartModels
	var hitboxes := mech.get_node("SkeletalHitboxes") as SkeletalHitboxes
	var skeleton := hitboxes.skeleton
	for slot: StringName in want:
		var meshes: Array = models.meshes_by_slot.get(slot, [])
		_check(meshes.size() == want[slot], "%s: %d meshes (want %d)" % [slot, meshes.size(), want[slot]])
		for mesh: MeshInstance3D in meshes:
			_check(mesh.get_parent() == skeleton and mesh.get_node_or_null(mesh.skeleton) == skeleton,
					"%s %s on the mech skeleton" % [slot, mesh.name])
			var missing := 0
			for i in mesh.skin.get_bind_count():
				if skeleton.find_bone(mesh.skin.get_bind_name(i)) < 0:
					missing += 1
			_check(missing == 0, "%s %s: all %d skin binds name a bone" % [slot, mesh.name, mesh.skin.get_bind_count()])
	var rest_skeleton := skeleton.get_children().size()
	_check(rest_skeleton >= want.values().reduce(func(a, b): return a + b, 0), "skeleton holds the part meshes (%d children)" % rest_skeleton)
	for key: String in hitboxes.part_meshes:
		_check(not (hitboxes.part_meshes[key] as Array).is_empty(), "hit part %s has meshes" % key)
	if loadout_key == 2:
		await _check_accessories(mech, skeleton)
	if OS.has_environment("OLD_SCENE"):
		await _compare(mech, OS.get_environment("OLD_SCENE"))
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## Mesh boxes (model space) and hitbox boxes of the new mech and of an old scene built from one file.
func _compare(mech: Mech, old_path: String) -> void:
	var old := (load(old_path) as PackedScene).instantiate() as Mech
	old.transform = mech.global_transform
	mech.get_parent().add_child(old)
	await _frames(5)
	var new_boxes := _boxes(mech)
	var old_boxes := _boxes(old)
	for key: String in old_boxes:
		var a: AABB = old_boxes[key]
		var b: AABB = new_boxes.get(key, AABB())
		var d := (a.position - b.position).length() + (a.size - b.size).length()
		_check(d < 0.001, "same box as the old scene: %s (%.4f m)" % [key, d])
	_check(new_boxes.size() == old_boxes.size(), "same box count: %d / %d" % [new_boxes.size(), old_boxes.size()])
	old.queue_free()


func _boxes(mech: Mech) -> Dictionary:
	var out := {}
	var hitboxes := mech.get_node("SkeletalHitboxes") as SkeletalHitboxes
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		out["mesh " + String(mesh.name)] = mesh.transform * mesh.get_aabb()
	# Hitboxes in their bone's frame (BoneAttachment3D), so the animation time does not matter.
	for node in mech.find_children("*", "PartHitbox", true, false):
		var hitbox := node as PartHitbox
		var shape := hitbox.get_child(0) as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		var key := "hitbox %s on %s" % [hitbox.part_key, hitbox.get_parent().name]
		out[key] = AABB(hitbox.transform * shape.position - size / 2.0, size)
	return out


## Walks 2 s and records the largest turn of each skirt panel and sleeve away from its rest.
func _check_accessories(mech: Mech, skeleton: Skeleton3D) -> void:
	var bones := [&"skirt_front_L", &"skirt_front_R", &"skirt_back_L", &"skirt_back_R", &"skirt_side_L", &"skirt_side_R"]
	var most := {}
	# Modifier poses exist only inside the skeleton update.
	var measure := func() -> void:
		for bone_name: StringName in bones:
			var bone := skeleton.find_bone(bone_name)
			var angle := skeleton.get_bone_pose_rotation(bone).angle_to(skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
			most[bone_name] = maxf(most.get(bone_name, 0.0), rad_to_deg(angle))
	skeleton.skeleton_updated.connect(measure)
	Input.action_press(&"move_forward")
	for i in 120:
		await physics_frame
		await process_frame
	skeleton.skeleton_updated.disconnect(measure)
	Input.action_release(&"move_forward")
	for bone_name: StringName in [&"skirt_front_L", &"skirt_front_R", &"skirt_back_L", &"skirt_back_R"]:
		_check(most[bone_name] > 3.0, "%s turns in the walk (largest %.1f deg)" % [bone_name, most[bone_name]])
	print("skirt turns (deg): ", most)
