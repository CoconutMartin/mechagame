extends SceneTree
## Makes the placeholder straight punch (user request 2026-10-15: fist + mouse button with no
## direction; the Mixamo library has no straight punch). Right fist; mirror it with mirror_clip.gd for
## the left fist.
##
## The body holds the guard pose of the first frame of the retargeted hook clip. The right arm goes
## from the guard to a chamber (pulled back), shoots straight forward at chest height with the torso
## turned into the punch, holds, and comes back to the guard.
##
## Run: godot --headless --path . --script res://tools/godot/make_straight_punch.gd -- <out anim .res>

const MODEL := "res://models/new_mech/new_mech_exploded.glb"
const GUARD_CLIP := "res://data/animations/melee_hook.res"
const FPS := 30.0
const LENGTH := 1.2
## Key times (seconds): guard, chamber, full reach, hold end, guard again.
const KEYS := [0.0, 0.3, 0.48, 0.7, 1.2]
## Torso turn toward the punch at full reach (degrees, about up; the right fist goes forward, so the
## torso turns left).
const TORSO_TURN_DEG := 22.0
## Punch direction in model space (+Z forward, +X left): forward, a little down and in.
const REACH_DIRECTION := Vector3(0.12, -0.12, 1.0)


func _initialize() -> void:
	var out_path := OS.get_cmdline_user_args()[0]
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	get_root().add_child(model)
	await process_frame
	for player in model.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).active = false
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var guard := load(GUARD_CLIP) as Animation

	# Guard pose: every track of the hook clip at time 0.
	var guard_rotation := {}
	var pelvis_position := Vector3.ZERO
	for track in guard.get_track_count():
		var bone := String(guard.track_get_path(track).get_concatenated_subnames())
		if guard.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			guard_rotation[bone] = guard.rotation_track_interpolate(track, 0.0)
		elif guard.track_get_type(track) == Animation.TYPE_POSITION_3D:
			pelvis_position = guard.position_track_interpolate(track, 0.0)

	var reached := _reach_pose(skeleton, guard_rotation, pelvis_position)
	var chamber := _chamber_pose(guard_rotation, reached)

	var anim := Animation.new()
	anim.length = LENGTH
	anim.step = 1.0 / FPS
	var tracks := {}
	for bone: String in guard_rotation:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("MechRig/Skeleton3D:" + bone))
		tracks[bone] = track
	var pelvis_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pelvis_track, NodePath("MechRig/Skeleton3D:pelvis"))
	var poses := [guard_rotation, chamber, reached, reached, guard_rotation]
	for i in KEYS.size():
		for bone: String in guard_rotation:
			anim.rotation_track_insert_key(tracks[bone], KEYS[i], poses[i].get(bone, guard_rotation[bone]))
		anim.position_track_insert_key(pelvis_track, KEYS[i], pelvis_position)
	print("save anim ", ResourceSaver.save(anim, out_path))
	quit()


## The guard pose with the right arm straight along REACH_DIRECTION and the torso turned into it.
func _reach_pose(skeleton: Skeleton3D, guard_rotation: Dictionary, pelvis_position: Vector3) -> Dictionary:
	var pose := guard_rotation.duplicate()
	pose["torso"] = Quaternion(Vector3.UP, deg_to_rad(TORSO_TURN_DEG)) * (guard_rotation["torso"] as Quaternion)
	var direction := REACH_DIRECTION.normalized()
	for pair in [["upper_arm_R", "forearm_R"], ["forearm_R", "hand_R"]]:
		_apply(skeleton, pose, pelvis_position)
		var bone := skeleton.find_bone(pair[0])
		var child := skeleton.find_bone(pair[1])
		var from := skeleton.get_bone_global_pose(child).origin - skeleton.get_bone_global_pose(bone).origin
		var turn := Quaternion(from.normalized(), direction)
		var global := turn * skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
		var parent_global := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis.get_rotation_quaternion()
		pose[pair[0]] = (parent_global.inverse() * global).normalized()
	# The hand keeps the forearm's line (a straight wrist).
	pose["hand_R"] = guard_rotation["hand_R"]
	return pose


## Half way back from the guard, away from the reach: the arm pulled back before the punch.
func _chamber_pose(guard_rotation: Dictionary, reached: Dictionary) -> Dictionary:
	var pose := guard_rotation.duplicate()
	pose["torso"] = Quaternion(Vector3.UP, deg_to_rad(-TORSO_TURN_DEG * 0.4)) * (guard_rotation["torso"] as Quaternion)
	for bone in ["upper_arm_R", "forearm_R"]:
		var guard: Quaternion = guard_rotation[bone]
		var reach: Quaternion = reached[bone]
		# The turn from the guard toward the reach, taken the other way at a quarter of its size.
		var turn := reach * guard.inverse()
		pose[bone] = (Quaternion.IDENTITY.slerp(turn.inverse(), 0.25) * guard).normalized()
	return pose


func _apply(skeleton: Skeleton3D, pose: Dictionary, pelvis_position: Vector3) -> void:
	skeleton.reset_bone_poses()
	for bone: String in pose:
		skeleton.set_bone_pose_rotation(skeleton.find_bone(bone), pose[bone])
	skeleton.set_bone_pose_position(skeleton.find_bone("pelvis"), pelvis_position)
	skeleton.force_update_all_bone_transforms()
