extends SceneTree
## Head against chest test (user request 2026-11-02: aiming down must not tilt the head down into the chest). The head mesh
## points inside the chest hull (Torso mesh, one convex hull per bone) at rest (the neck hollow, the baseline) and while the
## player aims down (PITCH, default -30) and fires: a one-hand gun (heavy_rifle) and the Beam Rifle in the sniping stance.
## Prints the largest count per case. Exit code 1 when a case has more than the baseline plus 10 percent.
## Environment: DISABLE=1 turns HeadSteady off (the old head), PITCH (degrees), DOWN, UP and TILT (degrees: override
## HeadSteady.parallel_max_down_deg, parallel_max_up_deg and parallel_neck_tilt_deg, to find the limits that keep the head out of the chest),
## CASES (comma list of rest, heavy_rifle, smg, auto_cannon, beam_rifle, beam_sniper; default rest, heavy_rifle and beam_rifle).
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_head_clip.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## MECH=haliya runs the test on Haliya (tools/godot/test_mech_choice.gd).
const MechChoice := preload("res://tools/godot/test_mech_choice.gd")
const LAYER := 1 << 19

var _failures := 0
var _base := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var pitch := float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else -30.0
	var cases := (OS.get_environment("CASES") if OS.get_environment("CASES") != "" else "rest,heavy_rifle,beam_rifle").split(",", false)
	for case_name in cases:
		if case_name == "rest":
			await _case(switcher, "rest", "", 0.0)
		else:
			await _case(switcher, "%s aim down" % case_name, case_name, pitch)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _case(switcher: LoadoutSwitcher, label: String, weapon: String, pitch: float) -> void:
	var loadout := MechChoice.apply(switcher.current_loadout.duplicate() as Loadout)
	loadout.weapon_left = null
	loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon) as WeaponData if weapon != "" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var steady := player.find_child("HeadSteady", true, false) as SkeletonModifier3D
	if steady != null and OS.has_environment("DISABLE"):
		steady.active = false
	if steady is SkeletalHeadSteady:
		if OS.get_environment("DOWN") != "":
			(steady as SkeletalHeadSteady).parallel_max_down_deg = float(OS.get_environment("DOWN"))
		if OS.get_environment("UP") != "":
			(steady as SkeletalHeadSteady).parallel_max_up_deg = float(OS.get_environment("UP"))
		if OS.get_environment("TILT") != "":
			(steady as SkeletalHeadSteady).parallel_neck_tilt_deg = float(OS.get_environment("TILT"))
	var rig := player.get_node("CameraRig") as MechCameraRig
	if weapon != "":
		Input.action_press("aim")
		rig._target_pitch = deg_to_rad(pitch)
		rig._pitch_spring.value = deg_to_rad(pitch)
		await _frames(60)
		rig._target_pitch = deg_to_rad(pitch)
		Input.action_press("use_right_arm")
	var worst := 0
	for frame in 150:
		await _frames(1)
		rig._target_pitch = maxf(deg_to_rad(pitch), rig.get_min_pitch()) if weapon != "" else rig._target_pitch
		if frame % 5 == 0:
			worst = maxi(worst, await _head_in_chest(skeleton))
	Input.action_release("use_right_arm")
	Input.action_release("aim")
	var ok := true
	if label == "rest":
		_base = worst
	else:
		ok = worst <= int(_base * 1.1)
	print(("ok   " if ok else "FAIL ") + "%s: head points in the chest hull %d (rest baseline %d)" % [label, worst, _base])
	if not ok:
		_failures += 1


func _head_in_chest(skeleton: Skeleton3D) -> int:
	await skeleton.skeleton_updated
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone))
	var head_points := PackedVector3Array()
	# Chest hulls: the SGG Torso mesh, one per bone; on a mech made of many pieces (Haliya: Head_*, Core_* on the torso bone)
	# one per piece.
	var chest: Array[PackedVector3Array] = []
	var torso_bone := skeleton.find_bone("torso")
	for node in skeleton.get_children():
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.skin == null or not mesh.visible:
			continue
		var mesh_name := String(mesh.name)
		if mesh_name == "Head_001" or mesh_name.begins_with("Head_"):
			for points: PackedVector3Array in _posed(skeleton, mesh, poses).values():
				head_points.append_array(points)
		elif mesh_name == "Torso":
			for points: PackedVector3Array in _posed(skeleton, mesh, poses).values():
				chest.append(points)
		elif mesh_name.begins_with("Core_"):
			var posed := _posed(skeleton, mesh, poses)
			if posed.has(torso_bone):
				chest.append(posed[torso_bone])
	var bodies: Array[StaticBody3D] = []
	for points: PackedVector3Array in chest:
		if points.size() < 4:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		shape.shape = convex
		body.add_child(shape)
		root.add_child(body)
		bodies.append(body)
	await physics_frame
	var space := skeleton.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = LAYER
	var count := 0
	for p in head_points:
		query.position = p
		if not space.intersect_point(query, 1).is_empty():
			count += 1
	for body in bodies:
		body.free()
	return count


## Mesh vertices posed by their strongest bone: {bone: PackedVector3Array}.
func _posed(skeleton: Skeleton3D, mesh: MeshInstance3D, poses: Array[Transform3D]) -> Dictionary:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var out := {}
	if vertices.is_empty():
		return out
	var per := bones.size() / vertices.size()
	for v in vertices.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		var index := bones[v * per + best]
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(index))
		if bone < 0:
			continue
		if not out.has(bone):
			out[bone] = PackedVector3Array()
		var list: PackedVector3Array = out[bone]
		list.append(poses[bone] * (mesh.skin.get_bind_pose(index) * vertices[v]))
		out[bone] = list
	return out
