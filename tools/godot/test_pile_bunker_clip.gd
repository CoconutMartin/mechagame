extends SceneTree
## Pile Bunker clipping test (user report 2026-10-26: the model clipped the forearm). Right and left hand: the face
## points of the Pile Bunker model against a convex hull per body armor mesh and bone (posed each sample), at rest,
## walking, powering up (the guard), through a whole attack on a target and while boosting. A point inside a hull is
## a clip. Prints the points per phase and the worst parts; exits with code 1 when a phase has more than MAX_POINTS.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_pile_bunker_clip.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
const BUNKER := "res://data/weapons/pile_bunker.tres"
## Points inside the body allowed per phase (the hulls are a little larger than the real armor).
const MAX_POINTS := 0
const LAYER := 1 << 19

var _failures := 0


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
	for side in ["R", "L"]:
		if OS.get_environment("CLIP_SIDE") in ["", side]:
			await _side(map, switcher, side)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _side(map: Node, switcher: LoadoutSwitcher, side: String) -> void:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(BUNKER) if side == "R" else null
	loadout.weapon_left = load(BUNKER) if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	var weapons := player.get_node("WeaponController") as WeaponController
	var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var button := "use_right_arm" if side == "R" else "use_left_arm"
	await _phase(side, "rest", skeleton, bunker, 30, [])
	await _phase(side, "walk", skeleton, bunker, 120, ["move_forward"])
	await _frames(90)
	await _phase(side, "power", skeleton, bunker, 90, [button])
	Input.action_release(button)
	await _frames(60)
	var forward := weapons.mech_aim.aim_point - player.global_position
	forward.y = 0.0
	var target := _make_target(map, player.global_position + forward.normalized() * 14.0, player)
	await _frames(20)
	for key: String in target.health.max_hp:
		target.health.max_hp[key] = 100000.0
		target.health.hp[key] = 100000.0
	Input.action_press(button)
	await _frames(60)
	Input.action_release(button)
	await _phase(side, "attack", skeleton, bunker, 150, [])
	target.queue_free()
	await _frames(240)
	await _phase(side, "boost", skeleton, bunker, 120, ["move_forward", "boost"])
	await _frames(120)


## Holds the actions for `frames` frames and checks every 3rd frame.
func _phase(side: String, phase: String, skeleton: Skeleton3D, bunker: PileBunkerWeapon, frames: int, actions: Array) -> void:
	for action: String in actions:
		Input.action_press(action)
	var total := 0
	var worst := {}
	for frame in frames:
		await _frames(1)
		if frame % 3 != 0:
			continue
		var found := await _clip(skeleton, bunker.get_model())
		for key: String in found:
			total += found[key]
			worst[key] = maxi(int(worst.get(key, 0)), int(found[key]))
	for action: String in actions:
		Input.action_release(action)
	var keys := worst.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return worst[a] > worst[b])
	var ok := total <= MAX_POINTS
	print(("ok   " if ok else "FAIL ") + "%s %s: %d points inside the body %s" % [side, phase, total, keys.slice(0, 4).map(func(k: String) -> String: return "%s %d" % [k, worst[k]])])
	if not ok:
		_failures += 1


## Points of the model inside the body hulls now: {"armor/bone <- part": count}. The bone poses are read during
## the skeleton update: the arm and hip modifiers (SkeletonModifier3D) change them only then, and the skin and the
## model's bone attachment use those poses.
func _clip(skeleton: Skeleton3D, model: Node3D) -> Dictionary:
	await skeleton.skeleton_updated
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone))
	var attach := model.get_parent() as BoneAttachment3D
	var model_world := poses[attach.bone_idx] * model.transform
	var bodies: Array[StaticBody3D] = []
	var names := {}
	for node in skeleton.get_children():
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.skin == null or not mesh.visible:
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty():
			continue
		var per := bones.size() / vertices.size()
		var per_bone := {}
		for v in vertices.size():
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var index := bones[v * per + best]
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(index))
			if bone < 0:
				continue
			var bone_name := String(skeleton.get_bone_name(bone))
			if bone_name.begins_with("hand") or bone_name.begins_with("index") or bone_name.begins_with("middle") \
					or bone_name.begins_with("ring") or bone_name.begins_with("pinky") or bone_name.begins_with("thumb"):
				continue
			if not per_bone.has(bone):
				per_bone[bone] = []
			(per_bone[bone] as Array).append(poses[bone] * (mesh.skin.get_bind_pose(index) * vertices[v]))
		for bone: int in per_bone:
			if (per_bone[bone] as Array).size() < 4:
				continue
			var body := StaticBody3D.new()
			body.collision_layer = LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var convex := ConvexPolygonShape3D.new()
			convex.points = PackedVector3Array(per_bone[bone])
			shape.shape = convex
			body.add_child(shape)
			root.add_child(body)
			bodies.append(body)
			names[body.get_rid()] = "%s/%s" % [mesh.name, skeleton.get_bone_name(bone)]
	await physics_frame
	var space := skeleton.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = LAYER
	var found := {}
	var model_inverse := model.global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var place := model_world * (model_inverse * mesh.global_transform)
		var faces := mesh.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			query.position = place * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0)
			for hit in space.intersect_point(query, 8):
				var key := "%s <- %s" % [names.get(hit.rid, "?"), mesh.name]
				found[key] = int(found.get(key, 0)) + 1
	for body in bodies:
		body.free()
	return found


## A mech in the crosshair: no input, no camera, a lockable enemy like the spawner's.
func _make_target(map: Node, place: Vector3, player: Mech) -> Mech:
	var target := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	target.position = place
	map.add_child(target)
	target.remove_from_group(&"player")
	target.add_to_group(&"lockable")
	for child_name in ["MechInput", "CameraRig"]:
		var node := target.find_child(child_name, true, false)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is Node3D:
				for camera in node.find_children("*", "Camera3D", true, false):
					(camera as Camera3D).current = false
	target.look_at(player.global_position, Vector3.UP)
	return target
