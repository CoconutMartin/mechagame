extends SceneTree
## Mirrors a retargeted Sanggigilid clip left to right (user request 2026-10-15: melee clips play to
## either side, for example a hook toward the right from the Mixamo hook toward the left). Writes a new
## Animation and, when a travel curve is given, a mirrored copy of it.
##
## How: for each frame the world rotation change of each bone from its rest pose is mirrored across
## the model's YZ plane (left and right swap: +X is the mech's left) and given to the bone of the other
## side (_L <-> _R), on top of that bone's own rest pose. So the two sides need no mirrored rest poses.
## The pelvis position is mirrored in X.
##
## Run: godot --headless --path . --script res://tools/godot/mirror_clip.gd -- <in anim .res> <out anim .res> [<in travel .tres> <out travel .tres>]

const MODEL := "res://models/new_mech/new_mech_exploded.glb"
const FPS := 30.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	get_root().add_child(model)
	await process_frame
	for player in model.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).active = false
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var source := load(args[0]) as Animation
	var rest_global: Array[Quaternion] = []
	for b in skeleton.get_bone_count():
		rest_global.append(skeleton.get_bone_global_rest(b).basis.get_rotation_quaternion())

	var out := Animation.new()
	out.length = source.length
	out.step = 1.0 / FPS
	var rotation_tracks := {}
	var position_tracks := {}
	for track in source.get_track_count():
		var bone_name := String(source.track_get_path(track).get_concatenated_subnames())
		var other := _other_side(bone_name)
		var new_track := out.add_track(source.track_get_type(track))
		out.track_set_path(new_track, NodePath("MechRig/Skeleton3D:" + other))
		if source.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			rotation_tracks[other] = [track, new_track]
		elif source.track_get_type(track) == Animation.TYPE_POSITION_3D:
			position_tracks[other] = [track, new_track]

	var frames := int(ceil(source.length * FPS))
	for frame in frames + 1:
		var time := minf(frame / FPS, source.length)
		# World rotation of every bone in the source pose (bones with no track keep their rest).
		var source_global := {}
		for b in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(b)
			var local := skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
			var track := _track_of(source, skeleton.get_bone_name(b), Animation.TYPE_ROTATION_3D)
			if track >= 0:
				local = source.rotation_track_interpolate(track, time)
			source_global[b] = (source_global[parent] * local if parent >= 0 else local) as Quaternion
		# Mirrored world rotations, bone by bone from the root, turned back into local rotations.
		var mirrored_global := {}
		for b in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(b)
			var from := skeleton.find_bone(_other_side(name))
			var change: Quaternion = source_global[from] * rest_global[from].inverse()
			# Reflection across the YZ plane: (x, y, z, w) -> (x, -y, -z, w).
			var mirrored_change := Quaternion(change.x, -change.y, -change.z, change.w)
			mirrored_global[b] = (mirrored_change * rest_global[b]).normalized()
			if rotation_tracks.has(name):
				var parent := skeleton.get_bone_parent(b)
				var parent_global: Quaternion = mirrored_global[parent] if parent >= 0 else Quaternion.IDENTITY
				out.rotation_track_insert_key(rotation_tracks[name][1], time, (parent_global.inverse() * mirrored_global[b]).normalized())
		for name: String in position_tracks:
			var position := source.position_track_interpolate(position_tracks[name][0], time)
			out.position_track_insert_key(position_tracks[name][1], time, _mirror_local_position(skeleton, name, position))
	print("save anim ", ResourceSaver.save(out, args[1]))
	if args.size() >= 4:
		var curve := (load(args[2]) as Curve).duplicate() as Curve
		var direction: Vector3 = curve.get_meta(&"travel_direction", Vector3.BACK)
		curve.set_meta(&"travel_direction", Vector3(-direction.x, direction.y, direction.z))
		print("save curve ", ResourceSaver.save(curve, args[3]))
	quit()


## Bone of the other side (thigh_L <-> thigh_R); a center bone is its own mirror.
static func _other_side(bone: String) -> String:
	if bone.ends_with("_L"):
		return bone.trim_suffix("_L") + "_R"
	if bone.ends_with("_R"):
		return bone.trim_suffix("_R") + "_L"
	return bone


static func _track_of(animation: Animation, bone: String, type: int) -> int:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == type and String(animation.track_get_path(track).get_concatenated_subnames()) == bone:
			return track
	return -1


## A bone position in its parent's space, mirrored in model X (the parent of the pelvis is the root).
static func _mirror_local_position(skeleton: Skeleton3D, bone: String, position: Vector3) -> Vector3:
	var b := skeleton.find_bone(bone)
	var parent := skeleton.get_bone_parent(b)
	var to_model := skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
	var model_position := to_model * position
	model_position.x = -model_position.x
	return to_model.affine_inverse() * model_position
