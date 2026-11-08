extends SceneTree
## Writes ArmPart.neutral_turn of Haliya's arm parts: the mean local turn of upper_arm_L / upper_arm_R over the Walk clip of
## models/mechs/haliya/haliya_rig.glb (user 2026-11-08: "Make HLY walking arms position as neutral arms position"). Also prints the
## mean palm place (grip bone) from the shoulder in torso space, the source of ArmPart.relaxed_hand. Run after make_haliya_rig.gd:
##   godot --headless --path . --script res://tools/godot/write_arm_neutral_data.gd

const RIG := "res://models/mechs/haliya/haliya_rig.glb"
const CLIP := &"Walk"
const PARTS := {"L": "res://data/parts/haliya/haliya_arm_l.tres", "R": "res://data/parts/haliya/haliya_arm_r.tres"}
## Samples over the clip.
const SAMPLES := 32


func _initialize() -> void:
	var rig := (load(RIG) as PackedScene).instantiate()
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var animation := player.get_animation(CLIP)
	for side: String in PARTS:
		var turn := _mean_turn(animation, "upper_arm_" + side)
		var part := load(PARTS[side]) as ArmPart
		part.neutral_turn = turn
		var err := ResourceSaver.save(part, PARTS[side])
		print("%s neutral_turn %s (%s)  palm from shoulder, torso space: %s" % [side, turn, error_string(err),
				_mean_palm(animation, skeleton, side)])
	rig.free()
	quit()


## Mean of a bone's rotation track over the clip (the samples on one side of the quaternion sphere, normalized sum).
func _mean_turn(animation: Animation, bone: String) -> Quaternion:
	var track := animation.find_track(NodePath("MechRig/Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D)
	var first: Quaternion = animation.rotation_track_interpolate(track, 0.0)
	var sum := Vector4.ZERO
	for i in SAMPLES:
		var q: Quaternion = animation.rotation_track_interpolate(track, animation.length * i / SAMPLES)
		if q.dot(first) < 0.0:
			q = -q
		sum += Vector4(q.x, q.y, q.z, q.w)
	sum = sum.normalized()
	return Quaternion(sum.x, sum.y, sum.z, sum.w)


## Mean palm (grip bone) place from the shoulder over the clip, in the torso marker frame (x out to the mech's right, -z forward:
## the skeleton frame turned half round, as the model faces the mech's back).
func _mean_palm(animation: Animation, skeleton: Skeleton3D, side: String) -> Vector3:
	var sum := Vector3.ZERO
	for i in SAMPLES:
		var time := animation.length * i / SAMPLES
		for track in animation.get_track_count():
			var bone := skeleton.find_bone(String(animation.track_get_path(track).get_subname(0)))
			if bone < 0:
				continue
			if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			elif animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
		var torso := _global(skeleton, skeleton.find_bone("torso"))
		var shoulder := _global(skeleton, skeleton.find_bone("upper_arm_" + side)).origin
		var palm := _global(skeleton, skeleton.find_bone("grip_" + side)).origin
		sum += torso.basis.orthonormalized().inverse() * (palm - shoulder)
	var mean := sum / SAMPLES
	return Vector3(-mean.x, mean.y, -mean.z)


## A bone's pose in skeleton space from the local poses (the skeleton's own global pose updates later).
func _global(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var pose := skeleton.get_bone_pose(bone)
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		pose = skeleton.get_bone_pose(parent) * pose
		parent = skeleton.get_bone_parent(parent)
	return pose
