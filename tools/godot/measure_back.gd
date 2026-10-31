extends SceneTree
## Measures the Sagigilid's back for a backpack (2026-10-31): the chest bone, and the torso armor's back face in
## that bone's frame (the deepest points per height band), and the back pack part (HP, hit boxes). Prints the numbers.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_back.gd

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(60)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var mech := switcher.mech
	var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var names := []
	for b in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(b))
	print("bones: ", names)
	var meshes := []
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			meshes.append(c.name)
	print("meshes: ", meshes)
	await skeleton.skeleton_updated
	var to_mech := mech.global_transform.affine_inverse()
	for mesh_name in ["Torso"]:
		var mesh := skeleton.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh == null:
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var bands := {}
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for v in verts.size():
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var idx := bones[v * per + best]
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(idx))
			var p := to_mech * (skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (mesh.skin.get_bind_pose(idx) * verts[v]))
			lo = lo.min(p)
			hi = hi.max(p)
			var band := int(floor(p.y * 2.0))
			if absf(p.x) < 0.9:
				bands[band] = maxf(float(bands.get(band, -INF)), p.z)
		print("Torso box in mech space: ", lo.snappedf(0.01), " .. ", hi.snappedf(0.01))
		var keys := bands.keys()
		keys.sort()
		for k in keys:
			print("  back z at y %.1f-%.1f (|x|<0.9): %.2f" % [k / 2.0, k / 2.0 + 0.5, bands[k]])
	for bone_name in ["spine", "spine_01", "spine_02", "spine_03", "chest", "torso", "Spine", "Chest"]:
		var b := skeleton.find_bone(bone_name)
		if b >= 0:
			print(bone_name, " at ", (to_mech * (skeleton.global_transform * skeleton.get_bone_global_pose(b))).origin.snappedf(0.01))
	# The back pack part (BackPackMount): its HP and hit box.
	await _frames(5)
	print("Back Pack HP: ", mech.health.max_hp.get("Back Pack", "none"), ", hit boxes: ", mech.health.hitboxes.get("Back Pack", []).size())
	quit()
