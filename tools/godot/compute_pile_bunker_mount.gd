extends SceneTree
## Pile Bunker place on the forearm bone (user request 2026-10-26: "side view, arm at 90 degrees, the body
## along the underside of the forearm, no clipping"). Holds the Pile Bunker with the fist at the 90-degree
## elbow place (the guard place, 2.18, 1.16, -2.76 in torso space), then reads the forearm armor in the forearm
## bone's frame: the armor axis (elbow to wrist), the world down direction, the armor's middle across, and its
## lowest point over the body width. Prints PileBunkerWeapon.bone_mount_right / bone_mount_left: the butt on
## the elbow, the body top on the underside (CLEARANCE below it), the body centred under the armor. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/compute_pile_bunker_mount.gd

## Body top above the model origin (the model hangs upside down: its old bottom, 0.55 m x SIZE 0.8).
const BODY_TOP := 0.44
## Half the body width (the front housing, 0.33 m x 0.8) and its length (the butt to the nose).
const BODY_HALF_WIDTH := 0.264
const BODY_LENGTH := 2.7
## Gap between the forearm underside and the body top.
const CLEARANCE := 0.06
## Shift toward the outer side of the arm (away from the thigh, m; OUTSET overrides).
const OUTSET := 0.0


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
	for side in ["R", "L"]:
		var loadout := switcher.current_loadout.duplicate() as Loadout
		var data := (load("res://data/weapons/pile_bunker.tres") as WeaponData).duplicate() as WeaponData
		data.rest_transform = Transform3D(Basis.IDENTITY, Vector3(2.18, 1.16, -2.76))
		loadout.weapon_right = data if side == "R" else null
		loadout.weapon_left = data if side == "L" else null
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(120)
		var skeleton := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
		var bone := skeleton.find_bone("forearm_" + side)
		# The pose with the arm modifiers: read during the skeleton update (they are undone after it).
		await skeleton.skeleton_updated
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
			var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (armor.skin.get_bind_pose(index) * vertices[v])
			points.append(frame.affine_inverse() * world)
		# Armor axis: from the middle of the elbow-end fifth to the middle of the wrist-end fifth (bone +Y runs along it).
		var low := INF
		var high := -INF
		for p in points:
			low = minf(low, p.y)
			high = maxf(high, p.y)
		var near := Vector3.ZERO
		var far := Vector3.ZERO
		var near_n := 0
		var far_n := 0
		for p in points:
			if p.y < low + 0.2 * (high - low):
				near += p
				near_n += 1
			elif p.y > high - 0.2 * (high - low):
				far += p
				far_n += 1
		var along := (far / far_n - near / near_n).normalized()
		var down := frame.basis.inverse() * Vector3.DOWN
		down = (down - along * down.dot(along)).normalized()
		var across := along.cross(down).normalized()
		var side_low := INF
		var side_high := -INF
		for p in points:
			side_low = minf(side_low, p.dot(across))
			side_high = maxf(side_high, p.dot(across))
		var middle := (side_low + side_high) / 2.0
		var under := -INF
		for p in points:
			if absf(p.dot(across) - middle) < BODY_HALF_WIDTH and p.dot(along) > 0.0 and p.dot(along) < BODY_LENGTH:
				under = maxf(under, p.dot(down))
		var origin := across * middle + down * (under + CLEARANCE + BODY_TOP)
		var y := -down
		var z := -along
		var x := y.cross(z).normalized()
		# Mount +X is the outer side for the right arm, the inner side for the left arm.
		var outset := float(OS.get_environment("OUTSET")) if OS.has_environment("OUTSET") else OUTSET
		origin += x * outset * (1.0 if side == "R" else -1.0)
		var place := Transform3D(Basis(x, y, z), origin)
		print("%s armor along %s, across %.3f..%.3f, underside %.3f, length %.3f..%.3f" % [side, along, side_low, side_high, under, low, high])
		print("bone_mount_%s = %s" % ["right" if side == "R" else "left", _tscn(place)])
	quit()


func _tscn(t: Transform3D) -> String:
	var b := t.basis
	return "Transform3D(%.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f)" % [b.x.x, b.y.x, b.z.x,
			b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z]
