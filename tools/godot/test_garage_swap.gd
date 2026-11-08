extends SceneTree
## Swaps parts between SGG and Haliya the way the garage does (LoadoutSwitcher.rebuild with a mixed loadout) and checks that the legs pick the
## mech scene, that the core and arm offsets come from their parts, that the core's waist ball sits on the legs' waist socket (DESIGN "Waist ball
## joint": at rest and in walk; SGG's white ball mesh with it), and that a mixed mech stands and walks. SWAP_OUT=<folder> also saves pictures
## (run with a window). Prints "RESULT: <n> failures"; exit code 1 on a failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_garage_swap.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const FOLDERS := {"s": "res://data/parts/sanggigilid/sanggigilid_", "h": "res://data/parts/haliya/haliya_"}
## Head, core, left arm, right arm, legs: s = SGG, h = Haliya.
const MIXES: Array[String] = ["sssss", "hhhhh", "ssssh", "hhhhs", "sshhs", "hhssh", "shhss", "hsshh"]
const CATALOG := "res://data/garage_catalog.tres"

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
	var catalog := load(CATALOG) as GarageCatalog
	_check(catalog.heads.size() == 2 and catalog.cores.size() == 2 and catalog.arms_left.size() == 2 and catalog.arms_right.size() == 2 and catalog.legs.size() == 2, "garage lists both mechs in each frame slot")
	var before := switcher.mech
	var press := InputEventKey.new()
	press.keycode = KEY_2
	press.physical_keycode = KEY_2
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(5)
	_check(switcher.mech == before, "key 2 picks no mech")
	var slots := ["head", "core", "arm_l", "arm_r", "legs"]
	var props := [&"head", &"core", &"arm_left", &"arm_right", &"legs"]
	for mix in MIXES:
		var loadout := switcher.current_loadout.duplicate() as Loadout
		loadout.mech_scene = null
		for i in 5:
			loadout.set(props[i], load(FOLDERS[mix[i]] + slots[i] + ".tres"))
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(40)
		var mech := switcher.mech
		_check(mech.name_code == ("HLY-101" if mix[4] == "h" else "SGG-101"), "%s: the legs pick the scene (%s)" % [mix, mech.name_code])
		var skeleton := (mech.get_node("SkeletalHitboxes") as SkeletalHitboxes).skeleton
		for i in [1, 2, 3]:
			var source := (load(FOLDERS[mix[i]] + slots[i] + ".tres") as PartData).scene.instantiate()
			var rig := source.find_child("Skeleton3D", true, false) as Skeleton3D
			var side := "L" if i == 2 else "R"
			var bone_name: String = "head" if i == 1 else "forearm_" + side
			var got := skeleton.get_bone_rest(skeleton.find_bone(bone_name)).origin
			var want := rig.get_bone_rest(rig.find_bone(bone_name)).origin
			_check(got.distance_to(want) < 0.002, "%s: %s offset from its part (%.3f m off)" % [mix, bone_name, got.distance_to(want)])
			source.free()
		var core := load(FOLDERS[mix[1]] + "core.tres") as CorePart
		var legs := load(FOLDERS[mix[4]] + "legs.tres") as LegPart
		var torso_rest := skeleton.get_bone_rest(skeleton.find_bone(&"torso")).origin
		_check(torso_rest.distance_to(legs.waist_socket) < 0.002, "%s: torso offset is the legs' waist socket (%.3f m off)" % [mix, torso_rest.distance_to(legs.waist_socket)])
		_check_waist(skeleton, core, legs, mix, "rest")
		_check_shoulders(skeleton, mix, "rest")
		await _picture(mech, mix, "stand")
		Input.action_press(&"move_forward")
		await _frames(60)
		_check_waist(skeleton, core, legs, mix, "walk")
		_check_shoulders(skeleton, mix, "walk")
		await _picture(mech, mix, "walk")
		Input.action_release(&"move_forward")
		await _frames(20)
		_check(is_instance_valid(mech) and mech.global_position.y > -1.0 and mech.global_position.y < 3.0, "%s: walks on the ground" % mix)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## The waist ball (core) on the waist socket (legs) in the current pose, and SGG's ball mesh (Waist_Joint) drawn on it.
func _check_waist(skeleton: Skeleton3D, core: CorePart, legs: LegPart, mix: String, state: String) -> void:
	var ball := skeleton.get_bone_global_pose(skeleton.find_bone(&"torso")) * core.waist_ball
	var socket := skeleton.get_bone_global_pose(skeleton.find_bone(&"pelvis")) * legs.waist_socket
	_check(ball.distance_to(socket) < 0.03, "%s %s: waist ball on the legs' socket (%.3f m off)" % [mix, state, ball.distance_to(socket)])
	var mesh := skeleton.get_node_or_null(^"Waist_Joint") as MeshInstance3D
	if mesh == null or mesh.skin == null:
		return
	var drawn := Vector3.ZERO
	for i in mesh.skin.get_bind_count():
		if mesh.skin.get_bind_name(i) == &"torso" or mesh.skin.get_bind_name(i) == &"pelvis":
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(i))
			var arrays := mesh.mesh.surface_get_arrays(0)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			if bones.size() > 0 and bones[0] == i:
				drawn = skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(i) * mesh.get_aabb().get_center()
	_check(drawn.distance_to(socket) < 0.03, "%s %s: SGG waist ball mesh on the socket (%.3f m off)" % [mix, state, drawn.distance_to(socket)])



## SGG's shoulder ball meshes (Arm_L/R_Shoulder_Joint) drawn on their shoulder joint (upper arm bone) in the current pose (user report
## 2026-11-08: "HLY body + SGG arms = disconnected and floating arms").
func _check_shoulders(skeleton: Skeleton3D, mix: String, state: String) -> void:
	for side in ["L", "R"]:
		var mesh := skeleton.get_node_or_null(NodePath("Arm_%s_Shoulder_Joint" % side)) as MeshInstance3D
		if mesh == null or mesh.skin == null:
			continue
		var bones: PackedInt32Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES]
		var bind := bones[0]
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
		var drawn := skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * mesh.get_aabb().get_center()
		var joint := skeleton.get_bone_global_pose(skeleton.find_bone("upper_arm_" + side)).origin
		_check(drawn.distance_to(joint) < 0.03, "%s %s: SGG %s shoulder ball on the shoulder joint (%.3f m off)" % [mix, state, side, drawn.distance_to(joint)])


func _picture(mech: Mech, mix: String, state: String) -> void:
	if not OS.has_environment("SWAP_OUT"):
		return
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.global_position = mech.global_position + Vector3(9.0, 6.0, -19.0)
	camera.look_at(mech.global_position + Vector3(0.0, 5.0, 0.0))
	camera.current = true
	await _frames(3)
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [OS.get_environment("SWAP_OUT"), mix, state])
	camera.queue_free()
