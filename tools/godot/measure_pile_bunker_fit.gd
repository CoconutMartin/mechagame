extends SceneTree
## Pile Bunker fit probe (2026-10-26, new model): holds the Pile Bunker (SIDE=R or L), standing, and prints in the
## Mount space: the fist, the wrist pin and the elbow, the nose and the model's bracket axis. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_pile_bunker_fit.gd

const Probe := preload("res://tools/godot/measure_arms_probe.gd")


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var side := OS.get_environment("SIDE") if OS.has_environment("SIDE") else "R"
	var data := load("res://data/weapons/pile_bunker.tres") as WeaponData
	loadout.weapon_right = data if side == "R" else null
	loadout.weapon_left = data if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(120)
	var weapons := switcher.mech.find_child("WeaponController", true, false) as WeaponController
	var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
	var mount := bunker.get_model()
	var inv := mount.global_transform.affine_inverse()
	var control := switcher.mech.find_child("MechHandControl", true, false) as MechHandControl
	var hand := control._sides[side].hand as MechHand
	print("%s fist (hand origin) in Mount space: %s" % [side, inv * hand.global_position])
	print("%s forearm joint origin in Mount space: %s" % [side, inv * mount.get_parent().global_position])
	print("%s nose in Mount space: %s" % [side, inv * bunker._nose.global_position])
	# The front of the fist: the hand mesh point furthest forward (-Z) in the Mount space.
	var front := INF
	for mesh: MeshInstance3D in hand.find_children("*", "MeshInstance3D", true, false):
		var aabb := mesh.get_aabb()
		for i in 8:
			front = minf(front, (inv * (mesh.global_transform * aabb.get_endpoint(i))).z)
	print("%s fist front (z) in Mount space: %.3f" % [side, front])
	var model := mount.get_node_or_null("Model") as Node3D
	if model:
		var back := -INF
		var body_front := INF
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if String(mesh.name).begins_with("Stake"):
				continue
			var aabb := mesh.get_aabb()
			for i in 8:
				var z := (inv * (mesh.global_transform * aabb.get_endpoint(i))).z
				back = maxf(back, z)
				body_front = minf(body_front, z)
		print("%s model body z in Mount space: back %.3f, front %.3f" % [side, back, body_front])
	# The forearm armor (posed vertices) in the Mount space: its arm_box, and the pile bunker points inside it.
	var skeleton := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var armor := skeleton.get_node("Arm_%s_02" % side) as MeshInstance3D
	var arrays := armor.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var arm_box := AABB()
	var under_points: Array[Vector3] = []
	for v in vertices.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		var index := bones[v * per + best]
		var bone := skeleton.find_bone(armor.skin.get_bind_name(index))
		var p := inv * (skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (armor.skin.get_bind_pose(index) * vertices[v]))
		arm_box = AABB(p, Vector3.ZERO) if v == 0 else arm_box.expand(p)
		under_points.append(p)
	print("%s forearm armor arm_box in Mount space: x %.3f..%.3f, y %.3f..%.3f, z %.3f..%.3f" % [side, arm_box.position.x, arm_box.end.x,
			arm_box.position.y, arm_box.end.y, arm_box.position.z, arm_box.end.z])
	# Underside over the body width (x center +- 0.27), per 0.25 m along z: the lowest armor point.
	var cx := bunker._nose.global_position
	cx = inv * cx
	var line := ""
	for step in 8:
		var z0 := 0.75 + step * 0.25
		var low := INF
		for q in under_points:
			if absf(q.x - cx.x) < 0.27 and q.z >= z0 and q.z < z0 + 0.25:
				low = minf(low, q.y)
		line += " z%.2f:%.3f" % [z0, low]
	print("%s forearm underside y over the body width:%s" % [side, line])
	var probe := Probe.new()
	var clip := probe.clip_check(skeleton, mount)
	for mesh_name: String in clip:
		var entry: Array = clip[mesh_name]
		if entry[1] > 0:
			print("%s clip %s: depth %.3f m, %d points (%s)" % [side, mesh_name, entry[0], entry[1], entry[2]])
	print("%s clip done" % side)
	# Exact check: a convex hull per armor mesh and bone (posed), the Pile Bunker face points inside it.
	var space := switcher.mech.get_world_3d().direct_space_state
	var hulls: Array[StaticBody3D] = []
	var names := {}
	for mesh_name: String in ["Arm_%s_01" % side, "Arm_%s_02" % side, "Elbow_%s_Joint_01" % side, "Leg_%s_01" % side,
			"Leg_%s_02" % side, "Torso", "Pelvis"]:
		var node := skeleton.get_node_or_null(mesh_name) as MeshInstance3D
		if node == null or node.skin == null:
			continue
		var arr := node.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bone_ids: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var bone_weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var n := bone_ids.size() / verts.size()
		var per_bone := {}
		for v in verts.size():
			var best := 0
			for k in n:
				if bone_weights[v * n + k] > bone_weights[v * n + best]:
					best = k
			var index := bone_ids[v * n + best]
			var bone := skeleton.find_bone(node.skin.get_bind_name(index))
			var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (node.skin.get_bind_pose(index) * verts[v])
			if not per_bone.has(bone):
				per_bone[bone] = []
			(per_bone[bone] as Array).append(world)
		for bone: int in per_bone:
			var body := StaticBody3D.new()
			body.collision_layer = 1 << 19
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var convex := ConvexPolygonShape3D.new()
			convex.points = PackedVector3Array(per_bone[bone])
			shape.shape = convex
			body.add_child(shape)
			root.add_child(body)
			hulls.append(body)
			names[body.get_rid()] = "%s/%s" % [mesh_name, skeleton.get_bone_name(bone)]
	await _frames(2)
	var inside := {}
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = 1 << 19
	for mesh: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
		var faces := mesh.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			for q: Vector3 in [faces[i], faces[i + 1], faces[i + 2], (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0]:
				query.position = mesh.global_transform * q
				for hit in space.intersect_point(query, 8):
					var key := "%s <- %s" % [names.get(hit.rid, "?"), mesh.name]
					inside[key] = int(inside.get(key, 0)) + 1
	# Self check: the armor's own middle is inside its hull.
	query.position = (hulls[0].get_child(0).shape as ConvexPolygonShape3D).points[0].lerp(
			(hulls[0].get_child(0).shape as ConvexPolygonShape3D).points[(hulls[0].get_child(0).shape as ConvexPolygonShape3D).points.size() / 2], 0.5)
	var self_hits := space.intersect_point(query, 8).size()
	var centre := Vector3.ZERO
	for q in (hulls[1].get_child(0).shape as ConvexPolygonShape3D).points:
		centre += q
	query.position = centre / (hulls[1].get_child(0).shape as ConvexPolygonShape3D).points.size()
	print("%s hull self check: %d, centre %d (%s)" % [side, self_hits, space.intersect_point(query, 8).size(), names.values()])
	for key: String in inside:
		print("%s inside hull %s: %d points" % [side, key, inside[key]])
	print("%s hull check done (%d hulls)" % [side, hulls.size()])
	var axis := mount.find_child("Mount", true, false) as Node3D
	if axis:
		print("%s model bracket axis in Mount space: %s" % [side, inv * axis.global_position])
	# Meshes of the body that come within 0.25 m of the hand.
	var near := 0
	for mesh: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		if box.grow(0.25).has_point(hand.global_position):
			near += 1
			print("  near the fist: %s" % mesh.name)
	print("%s meshes near the fist: %d" % [side, near])
	quit()
