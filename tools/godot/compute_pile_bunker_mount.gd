extends SceneTree
## Pile Bunker place on the forearm bone (user request 2026-10-29: "sits on top of the dorsal part of the forearm,
## no clipping; side view: lower it to match the edge of the forearm; all pile bunkers the same"). Holds the Pile
## Bunker with the fist at the 90-degree elbow place (2.18, 1.16, -2.76 in torso space) and reads the forearm armor in
## the forearm bone's frame, with the arm modifiers (during the skeleton update): the armor axis (elbow to wrist) and
## the world up. The model stands upright; its plain side lies GAP from the armor's outer (dorsal) face, its bottom is
## level with the armor's bottom and its butt is on the elbow. The model is mirrored in the right hand (bone_mirror_right)
## so its detailed side faces out on both arms. Prints PileBunkerWeapon.bone_mount_right / bone_mount_left. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/compute_pile_bunker_mount.gd

const MODEL := "res://models/pile_bunker/pile_bunker.glb"
## Gap between the armor's outer face and the model's plain side (m).
const GAP := 0.03
## The torso-space fist place with the elbow at 90 degrees (the guard place).
const FIST_90 := Vector3(2.18, 1.16, -2.76)
## Mirror per hand: the same values as bone_mirror_right / bone_mirror_left in the scene.
const MIRROR := {"R": true, "L": false}


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	var model_points := _model_points()
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for side in ["R", "L"]:
		var loadout := switcher.current_loadout.duplicate() as Loadout
		var data := (load("res://data/weapons/pile_bunker.tres") as WeaponData).duplicate() as WeaponData
		data.rest_transform = Transform3D(Basis.IDENTITY, FIST_90)
		loadout.weapon_right = data if side == "R" else null
		loadout.weapon_left = data if side == "L" else null
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(120)
		var skeleton := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
		var bone := skeleton.find_bone("forearm_" + side)
		# The pose with the arm modifiers: read during the skeleton update (they are undone after it).
		await skeleton.skeleton_updated
		var frame := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var points := _armor_points(skeleton, side, bone, frame)
		var along := _armor_axis(points)
		var up := frame.basis.inverse() * Vector3.UP
		up = (up - along * up.dot(along)).normalized()
		var z := -along
		var x := up.cross(z).normalized()
		# Mount +X is the outer side of the right arm, the inner side of the left arm.
		var out := x if side == "R" else -x
		var armor_out := -INF
		var armor_bottom := INF
		for p in points:
			armor_out = maxf(armor_out, p.dot(out))
			armor_bottom = minf(armor_bottom, p.dot(up))
		# The model in Mount space (mirrored for this hand): its extent toward the arm and its bottom.
		var mirror := Basis.from_scale(Vector3(-1.0, 1.0, 1.0)) if MIRROR[side] else Basis.IDENTITY
		var inner := -INF
		var bottom := INF
		var out_sign := 1.0 if side == "R" else -1.0
		for q in model_points:
			var m := mirror * q
			inner = maxf(inner, -m.x * out_sign)
			bottom = minf(bottom, m.y)
		var origin := out * (armor_out + GAP + inner) + up * (armor_bottom - bottom)
		var place := Transform3D(Basis(x, up, z), origin)
		print("%s armor along %s, outer face %.3f, bottom %.3f; model inner side %.3f, bottom %.3f" % [side, along,
				armor_out, armor_bottom, inner, bottom])
		print("bone_mount_%s = %s" % ["right" if side == "R" else "left", _tscn(place)])
	quit()


## Vertices of the model's meshes (the stakes too) in the model's own space.
func _model_points() -> PackedVector3Array:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var out := PackedVector3Array()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var place := model.global_transform.affine_inverse() * mesh.global_transform
		for v in mesh.mesh.get_faces():
			out.append(place * v)
	model.free()
	return out


## The forearm armor vertices that follow the forearm bone, in that bone's frame.
func _armor_points(skeleton: Skeleton3D, side: String, bone: int, frame: Transform3D) -> Array[Vector3]:
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
	return points


## Armor axis: from the middle of the elbow-end fifth to the middle of the wrist-end fifth (bone +Y runs along it).
func _armor_axis(points: Array[Vector3]) -> Vector3:
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
	return (far / far_n - near / near_n).normalized()


func _tscn(t: Transform3D) -> String:
	var b := t.basis
	return "Transform3D(%.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f, %.5f)" % [b.x.x, b.y.x, b.z.x,
			b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z]
