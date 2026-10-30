extends SceneTree
## Knuckle line probe (user request 2026-10-30, picture: "right hand knuckles should align with the red line", the
## edge of the forearm armor's end). Holds the Pile Bunker (SIDE=R or L), optional ACTIONS (e.g. use_right_arm = the
## power-up), and reads in the skeleton update: the forearm armor's cross-section (its points seen along the armor
## axis) and its smallest box (the face edges), and the fist's knuckle row (the hand's X axis) seen the same way.
## Prints the angle from the knuckle row to the nearest armor edge (degrees, about the armor axis toward the hand).
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_knuckle_line.gd

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
	var side := OS.get_environment("SIDE") if OS.has_environment("SIDE") else "R"
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var bunker := load("res://data/weapons/pile_bunker.tres")
	loadout.weapon_right = bunker if side == "R" else null
	loadout.weapon_left = bunker if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	for action in (OS.get_environment("ACTIONS") if OS.has_environment("ACTIONS") else "").split(",", false):
		Input.action_press(action)
	await _frames(60)
	var mech := switcher.mech
	var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var control := mech.find_child("MechHandControl", true, false) as MechHandControl
	var hand := control.hand_right if side == "R" else control.hand_left
	await skeleton.skeleton_updated
	var bone := skeleton.find_bone("forearm_" + side)
	var frame := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var armor := skeleton.get_node("Arm_%s_02" % side) as MeshInstance3D
	var arrays := armor.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var points: Array[Vector3] = []
	for v in vertices.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		var index := bones[v * per + best]
		if skeleton.find_bone(armor.skin.get_bind_name(index)) != bone:
			continue
		points.append(armor.skin.get_bind_pose(index) * vertices[v])
	# Armor axis = bone +Y (near enough); the cross-section plane is the bone's XZ plane.
	var axis := Vector3.UP
	var best_angle := 0.0
	var best_area := INF
	for step in 180:
		var angle := deg_to_rad(step * 0.5)
		var u := Vector3(cos(angle), 0.0, sin(angle))
		var w := axis.cross(u)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in points:
			var q := Vector2(p.dot(u), p.dot(w))
			lo = lo.min(q)
			hi = hi.max(q)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best_area:
			best_area = area
			best_angle = angle
	var edge := Vector3(cos(best_angle), 0.0, sin(best_angle))
	var knuckles := frame.basis.inverse() * hand.global_basis.x
	knuckles = Vector3(knuckles.x, 0.0, knuckles.z).normalized()
	var turn := rad_to_deg(knuckles.signed_angle_to(edge, axis))
	# The nearest edge: the box has edges every 90 degrees, a line has no direction (every 180).
	var off := wrapf(turn, -45.0, 45.0)
	print("%s knuckle row to the nearest armor edge: %.1f deg (about the forearm axis); armor box %.2f m2" % [side, off, best_area])
	quit()
