extends SceneTree
## Self collision test for the melee clips (user request 2026-10-30: "add part collisions for the punching/fist/
## pilebunker animations", "head is clipping with the chest when the mech is about to punch"). Plays, on the player:
## the right fist held 1 s (charging clip) and released (punch), and the Pile Bunker attack with each punch clip
## (power 40 frames, release, charge, clip). Every 3rd frame, in the skeleton update (with the modifiers), it builds a
## convex hull per body mesh and bone and counts the points inside another part's hull:
##   head: the head mesh against the chest (Torso);
##   arms: the upper arm, forearm and jointed hand of each side against the chest, pelvis, legs and head;
##   weapon: the Pile Bunker model against every hull but its own forearm's.
## Prints the points per case and part pair. Exits with code 1 when a case has more than MAX_POINTS.
## CASES=fist,pb1,pb3,pb4,pb5 picks cases. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_clip_self.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## MECH=haliya runs the test on Haliya (tools/godot/test_mech_choice.gd).
const MechChoice := preload("res://tools/godot/test_mech_choice.gd")
const BUNKER := "res://data/weapons/pile_bunker.tres"
const LAYER := 1 << 19
const MAX_POINTS := 0
const BODY := ["Torso", "Pelvis", "Leg_L_01", "Leg_R_01", "Leg_R_02", "Leg_L_02", "Leg_R_03", "Head_001"]
## A mech made of many pieces (Haliya): each piece is its own hull, named after the SGG part of its bone (_piece_label). Its
## arms also count against these parts.
const PIECE_BODY_EXTRA := ["Leg_L_03", "Skirt"]
## Bone -> SGG part name, for the pieces of a mech made of many pieces.
const PIECE_PARTS := {"torso": "Torso", "pelvis": "Pelvis", "head": "Head_001", "thigh_L": "Leg_L_01", "thigh_R": "Leg_R_01",
		"shin_L": "Leg_L_02", "shin_R": "Leg_R_02", "foot_L": "Leg_L_03", "foot_R": "Leg_R_03", "upper_arm_L": "Arm_L_01",
		"upper_arm_R": "Arm_R_01", "forearm_L": "Arm_L_02", "forearm_R": "Arm_R_02"}

var _failures := 0
## The head's points in the chest hull at rest (the neck hollow), taken off the other cases.
var _head_base := 0


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
	var cases := (OS.get_environment("CASES") if OS.has_environment("CASES") else "fist,pb1,pb3,pb4,pb5").split(",", false)
	# The baseline first (no attack): the head sits in the chest hull's neck hollow even at rest.
	await _case(switcher, "rest")
	for case in cases:
		await _case(switcher, case)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _case(switcher: LoadoutSwitcher, case: String) -> void:
	var loadout := MechChoice.apply(switcher.current_loadout.duplicate() as Loadout)
	loadout.weapon_left = null
	loadout.weapon_right = load(BUNKER) if case.begins_with("pb") else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	var weapons := player.get_node("WeaponController") as WeaponController
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var bunker := weapons.right_weapon as PileBunkerWeapon
	if bunker != null:
		bunker.clip_number = int(case.substr(2))
	var found := {}
	# "rest": no attack (the baseline: hulls are convex, so a hollow in a part counts too).
	var attack := case != "rest"
	if attack:
		Input.action_press("use_right_arm")
	var hold := 60 if case == "fist" else 40
	for frame in hold + 240:
		if frame == hold and attack:
			Input.action_release("use_right_arm")
		await _frames(1)
		if frame % 3 == 0:
			var now := await _self_clip(player, skeleton, bunker)
			if OS.has_environment("TRACE"):
				var parts := []
				for key: String in now:
					if not key.begins_with("head"):
						parts.append("%s %d" % [key, now[key]])
				print("  f%d %s" % [frame, parts])
			for key: String in now:
				found[key] = maxi(int(found.get(key, 0)), int(now[key]))
	Input.action_release("use_right_arm")
	if case == "rest":
		_head_base = int(found.get("head <- Torso", 0))
		found.erase("head <- Torso")
	elif found.has("head <- Torso"):
		# The head counts only past its rest baseline (with a 10% margin).
		found["head <- Torso"] = maxi(0, int(found["head <- Torso"]) - int(_head_base * 1.1))
		if found["head <- Torso"] == 0:
			found.erase("head <- Torso")
	var total := 0
	for key: String in found:
		total += found[key]
	var keys := found.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return found[a] > found[b])
	var ok := total <= MAX_POINTS
	print(("ok   " if ok else "FAIL ") + "%s: %d (largest per frame, summed over pairs) %s" % [case, total,
			keys.slice(0, 6).map(func(k: String) -> String: return "%s %d" % [k, found[k]])])
	if not ok:
		_failures += 1
	await _frames(120)


## Points inside other parts' hulls now: {"part <- hull": count}.
func _self_clip(player: Mech, skeleton: Skeleton3D, bunker: PileBunkerWeapon) -> Dictionary:
	await skeleton.skeleton_updated
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone))
	# Posed points of every skinned mesh, per bone.
	var per_mesh := {}
	for node in skeleton.get_children():
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.skin == null or not mesh.visible:
			continue
		per_mesh[String(mesh.name)] = _posed(skeleton, mesh, poses)
	# Hand model points (the jointed hands ride bone attachments).
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	var hand_points := {}
	for side in ["R", "L"]:
		var hand := control.hand_right if side == "R" else control.hand_left
		var points := PackedVector3Array()
		if is_instance_valid(hand) and hand.visible:
			for m: MeshInstance3D in hand.find_children("*", "MeshInstance3D", true, false):
				var aabb := m.get_aabb()
				for i in 8:
					points.append(m.global_transform * (aabb.get_center().lerp(aabb.get_endpoint(i), 0.8)))
		hand_points[side] = points
	# Pieces of a mech made of many pieces get the name of their SGG part; their points are gathered under it.
	var labels := {}
	for mesh_name: String in per_mesh:
		labels[mesh_name] = _piece_label(mesh_name, per_mesh[mesh_name], skeleton)
	var by_label := {}
	for mesh_name: String in per_mesh:
		var label: String = labels[mesh_name]
		if label == mesh_name:
			continue
		if not by_label.has(label):
			by_label[label] = PackedVector3Array()
		var gathered: PackedVector3Array = by_label[label]
		gathered.append_array(_all(per_mesh[mesh_name]))
		by_label[label] = gathered
	# Hulls: one per body mesh and bone.
	var bodies: Array[StaticBody3D] = []
	var names := {}
	for mesh_name: String in per_mesh:
		for bone: int in per_mesh[mesh_name]:
			var points: PackedVector3Array = per_mesh[mesh_name][bone]
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
			names[body.get_rid()] = [labels[mesh_name], String(skeleton.get_bone_name(bone)), labels[mesh_name] != mesh_name]
	await physics_frame
	var space := skeleton.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = LAYER
	var found := {}
	var test := func(label: String, points: PackedVector3Array, allowed: Callable) -> void:
		for p in points:
			query.position = p
			for hit in space.intersect_point(query, 8):
				var info: Array = names.get(hit.rid, ["?", "?", false])
				if not allowed.call(info[0], info[1]) and not (info[2] and points_of_body(info[0], allowed)):
					continue
				var key := "%s <- %s" % [label, info[0]]
				found[key] = int(found.get(key, 0)) + 1
	# Head against the chest.
	if per_mesh.has("Head_001"):
		test.call("head", _all(per_mesh["Head_001"]), func(m: String, _b: String) -> bool: return m == "Torso")
	elif by_label.has("Head_001"):
		test.call("head", by_label["Head_001"], func(m: String, _b: String) -> bool: return m == "Torso")
	# Arms and hands against the body, legs and head.
	for side in ["R", "L"]:
		for part in [["upper_" + side, "Arm_%s_01" % side], ["fore_" + side, "Arm_%s_02" % side]]:
			if per_mesh.has(part[1]):
				test.call(part[0], _all(per_mesh[part[1]]), func(m: String, _b: String) -> bool: return m in BODY)
			elif by_label.has(part[1]):
				test.call(part[0], by_label[part[1]], func(m: String, _b: String) -> bool: return m in BODY)
		test.call("hand_" + side, hand_points[side], func(m: String, _b: String) -> bool: return m in BODY)
	# The Pile Bunker against everything but its own forearm and hand.
	if bunker != null and is_instance_valid(bunker.get_model()):
		var model := bunker.get_model()
		var attach := model.get_parent() as BoneAttachment3D
		var own := "Arm_%s_02" % ("L" if bunker.is_left else "R")
		var points := PackedVector3Array()
		var model_world := poses[attach.bone_idx] * model.transform if attach != null else model.global_transform
		var inverse := model.global_transform.affine_inverse()
		for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var place := model_world * (inverse * m.global_transform)
			var faces := m.mesh.get_faces()
			for i in range(0, faces.size() - 2, 3):
				points.append(place * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0))
		test.call("pile_bunker", points, func(m: String, _b: String) -> bool: return m != own)
	for body in bodies:
		body.free()
	return found


## The extra body parts of a mech made of many pieces count for the arm and hand tests (callable allowed is m in BODY).
func points_of_body(label: String, allowed: Callable) -> bool:
	return label in PIECE_BODY_EXTRA and allowed.call("Torso", "")


## A piece's SGG part name from the bone with most of its points (Arm_shoulder_* is the ball in the chest socket, left out).
## An SGG mesh (merged part) keeps its own name.
func _piece_label(mesh_name: String, per_bone: Dictionary, skeleton: Skeleton3D) -> String:
	if mesh_name in BODY or mesh_name.begins_with("Arm_L_0") or mesh_name.begins_with("Arm_R_0") or mesh_name == "Leg_L_03" \
			or mesh_name.contains("Joint"):
		return mesh_name
	if not (mesh_name.begins_with("Core_") or mesh_name.begins_with("Legs_") or mesh_name.begins_with("Head_")
			or mesh_name.begins_with("Arm_") or mesh_name.begins_with("Skirt_")):
		return mesh_name
	if mesh_name.begins_with("Arm_shoulder"):
		return "Arm_ball"
	var best := -1
	for bone: int in per_bone:
		if best < 0 or (per_bone[bone] as PackedVector3Array).size() > (per_bone[best] as PackedVector3Array).size():
			best = bone
	var bone_name := String(skeleton.get_bone_name(best))
	if bone_name.begins_with("skirt_"):
		return "Skirt"
	return PIECE_PARTS.get(bone_name, mesh_name)


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


func _all(per_bone: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for bone: int in per_bone:
		out.append_array(per_bone[bone])
	return out
