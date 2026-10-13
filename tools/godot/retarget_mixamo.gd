extends SceneTree
## Retargets a Mixamo animation (FBX, "Without Skin") onto Sanggigilid's skeleton (user request
## 2026-10-13: the dodge animations). Writes an Animation for the Model's AnimationPlayer (tracks
## "MechRig/Skeleton3D:<bone>") and a Curve of the travel (0 to 1 over 0 to 1 of the time; metadata
## travel_direction in model space and travel_m).
##
## How: both skeletons face +Z with their left side at +X. For each mapped bone the world rotation
## change from the source rest pose is copied: target = change x align x target rest. "align" turns
## the target limb from its rest direction (A-pose arms, splayed legs) to the source rest direction
## (T-pose), so the limbs point the same way. The hips height change is scaled by the hip heights;
## the travel is taken out (the animation plays in place, the dodge code moves the mech along the
## travel curve). The source's stance turn at the first frame (the average of the hips and shoulder
## facing; Mixamo dodges stand turned 45 to 60 degrees from their travel axes) is taken out of the
## body, not out of the travel, so the mech faces forward at the start and at the end and moves along
## the clip's own axis (+Z forward, +X left).
##
## Run: godot --headless --path . --script res://tools/godot/retarget_mixamo.gd -- <fbx> <out anim .res> <out curve .tres>

const MODEL := "res://models/new_mech/new_mech_exploded.glb"
const FPS := 30.0
## Target bone -> [source bone, target child (for the limb direction, "" = no align),
## source child, bone whose align it uses ("" = its own)].
const MAP := {
	"pelvis": ["Hips", "", "", ""],
	"torso": ["Spine2", "", "", ""],
	"head": ["Head", "", "", ""],
	"thigh_L": ["LeftUpLeg", "shin_L", "LeftLeg", ""],
	"shin_L": ["LeftLeg", "foot_L", "LeftFoot", ""],
	"foot_L": ["LeftFoot", "", "", "shin_L"],
	"thigh_R": ["RightUpLeg", "shin_R", "RightLeg", ""],
	"shin_R": ["RightLeg", "foot_R", "RightFoot", ""],
	"foot_R": ["RightFoot", "", "", "shin_R"],
	"upper_arm_L": ["LeftArm", "forearm_L", "LeftForeArm", ""],
	"forearm_L": ["LeftForeArm", "hand_L", "LeftHand", ""],
	"hand_L": ["LeftHand", "", "", "forearm_L"],
	"upper_arm_R": ["RightArm", "forearm_R", "RightForeArm", ""],
	"forearm_R": ["RightForeArm", "hand_R", "RightHand", ""],
	"hand_R": ["RightHand", "", "", "forearm_R"],
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source_root := (load(args[0]) as PackedScene).instantiate() as Node3D
	var target_root := (load(MODEL) as PackedScene).instantiate() as Node3D
	get_root().add_child(source_root)
	get_root().add_child(target_root)
	await process_frame
	var player := source_root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source := source_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var target := target_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var source_anim := player.get_animation(player.get_animation_list()[0])
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(player.get_animation_list()[0])

	var source_rest := _rest_globals(source)
	var target_rest := _rest_globals(target)
	var hips := _src(source, "Hips")
	var scale := target_rest[target.find_bone("pelvis")].origin.y / source_rest[hips].origin.y
	# Align rotations (world) from the rest directions.
	var align := {}
	for bone: String in MAP:
		var entry: Array = MAP[bone]
		if entry[1] == "":
			continue
		var t_dir := (target_rest[target.find_bone(entry[1])].origin - target_rest[target.find_bone(bone)].origin).normalized()
		var s_dir := (source_rest[_src(source, entry[2])].origin - source_rest[_src(source, entry[0])].origin).normalized()
		align[bone] = Quaternion(t_dir, s_dir)
	for bone: String in MAP:
		var use: String = MAP[bone][3]
		if use != "":
			align[bone] = align[use]

	var anim := Animation.new()
	anim.length = source_anim.length
	anim.step = 1.0 / FPS
	var tracks := {}
	for bone: String in MAP:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("MechRig/Skeleton3D:" + bone))
		tracks[bone] = track
	var pelvis_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pelvis_track, NodePath("MechRig/Skeleton3D:pelvis"))

	player.seek(0.0, true)
	player.advance(0.0)
	source.force_update_all_bone_transforms()
	# Stance turn: the average of the hips and shoulder facing at the first frame (Mixamo dodges stand
	# in a boxer stance, turned about 60 degrees from the travel axes).
	var hips_face := source.get_bone_global_pose(hips).basis.z
	var shoulders := source.get_bone_global_pose(_src(source, "LeftArm")).origin - source.get_bone_global_pose(_src(source, "RightArm")).origin
	var shoulder_face := shoulders.cross(Vector3.UP)
	var stance_yaw := (atan2(hips_face.x, hips_face.z) + atan2(shoulder_face.x, shoulder_face.z)) * 0.5
	var unturn := Quaternion(Vector3.UP, -stance_yaw)
	var frames := int(ceil(source_anim.length * FPS))
	var offsets: Array[Vector3] = []
	for frame in frames + 1:
		var time := minf(frame / FPS, source_anim.length)
		player.seek(time, true)
		player.advance(0.0)
		source.force_update_all_bone_transforms()
		var globals := {}
		for b in target.get_bone_count():
			var name := target.get_bone_name(b)
			var parent := target.get_bone_parent(b)
			var parent_global: Transform3D = globals[parent] if parent >= 0 else Transform3D.IDENTITY
			var local := target.get_bone_rest(b)
			if MAP.has(name):
				var s := _src(source, MAP[name][0])
				var change := unturn * source.get_bone_global_pose(s).basis.get_rotation_quaternion() \
						* source_rest[s].basis.get_rotation_quaternion().inverse()
				var aligned: Quaternion = align.get(name, Quaternion.IDENTITY)
				var rest_rotation := target_rest[b].basis.get_rotation_quaternion()
				var global_rotation := (change * aligned * rest_rotation).normalized()
				var parent_rotation := parent_global.basis.get_rotation_quaternion()
				var local_rotation := (parent_rotation.inverse() * global_rotation).normalized()
				local = Transform3D(Basis(local_rotation), local.origin)
				anim.rotation_track_insert_key(tracks[name], time, local_rotation)
			globals[b] = parent_global * local
		# Hips: the height change (scaled), in place; the forward travel goes to the curve.
		var hips_pos := source.get_bone_global_pose(hips).origin
		var change_pos := (hips_pos - source_rest[hips].origin) * scale
		# The travel stays on the source axes (+Z forward): only the body is turned.
		offsets.append(Vector3(change_pos.x, 0.0, change_pos.z))
		var pelvis := target.find_bone("pelvis")
		var root_global: Transform3D = globals[target.get_bone_parent(pelvis)]
		var world := target_rest[pelvis].origin + Vector3(0.0, change_pos.y, 0.0)
		anim.position_track_insert_key(pelvis_track, time, root_global.affine_inverse() * world)

	# Travel: along the line to the farthest hips place (a dodge can step back toward the start at
	# the end), 1 = that farthest place.
	var farthest := Vector3.ZERO
	for offset in offsets:
		if (offset - offsets[0]).length() > farthest.length():
			farthest = offset - offsets[0]
	var travel_direction := farthest.normalized()
	var curve := Curve.new()
	curve.min_value = -0.5
	curve.max_value = 1.5
	for i in offsets.size():
		var along := (offsets[i] - offsets[0]).dot(travel_direction) / farthest.length()
		curve.add_point(Vector2(float(i) / float(offsets.size() - 1), along), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.set_meta(&"travel_m", farthest.length())
	# Model space: +Z forward, +X left.
	curve.set_meta(&"travel_direction", travel_direction)
	print("length %.2f s, frames %d, scale %.1f, travel %.1f m toward %s (model space, +Z forward, +X left), end %.2f" % [
			anim.length, frames, scale, farthest.length(), travel_direction.snapped(Vector3.ONE * 0.01), curve.sample(1.0)])
	print("save anim ", ResourceSaver.save(anim, args[1]), " curve ", ResourceSaver.save(curve, args[2]))
	quit()


func _src(skeleton: Skeleton3D, name: String) -> int:
	return skeleton.find_bone("mixamorig_" + name)


func _rest_globals(skeleton: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for b in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_rest(b))
	return out
