extends SceneTree
## Writes Haliya HLY-101's rig file models/mechs/haliya/haliya_rig.glb on the SGG-101 skeleton (user decision 2026-11-08, DESIGN
## "HLY refit decision"): the SGG rig (same bones, offsets and rest rotations) with the SGG clips and only the steps Haliya still
## needs on top of them, baked into the clips as the Blender rig did (tools/blender/haliya_rig_light.py):
##   arm carry   the arms come down from the A-pose of the clips to Haliya's stance (the turns of the old Haliya_Arm_Carry action),
##               plus ARM_CARRY_OUT_DEG out from the body, because the hips and skirts are now at the wider SGG hip width;
##   walk lean   the pelvis and the torso lean forward while the mech moves (driver of Haliya_Walk_Lean: keyed crouch and the
##               distance between the foot controls); the thighs turn back by the pelvis lean, so the feet stay where the clip has them.
## Dropped: the pelvis lift (the legs now have the SGG length the clips were made for) and the baked skirt swing (AccessoryBoneFollow
## turns the plates in the game). The clip Haliya_Stand holds the stance for looking and is the zero of the plate follow.
##   godot --headless --path . --script res://tools/godot/make_haliya_rig.gd
## Then import (godot --headless --path . --import): the tool also copies the clip import settings (loop modes) of sgg_rig.glb.

const Parts := preload("res://tools/godot/refit_haliya_parts.gd")
const SGG_RIG := "res://models/mechs/sgg/sgg_rig.glb"
const OLD_RIG := "res://models/mechs/haliya/source_light_rig/haliya_rig.glb"
const OUT := "res://models/mechs/haliya/haliya_rig.glb"
const STAND := &"Haliya_Stand"
## A clip with the arms in the same pose on both rigs except for the carry (a hand pose): the old rig minus the SGG rig is the carry.
## The old Haliya_Arm_Carry clip cannot be used: its own constraint doubled the carry when it was baked.
const CARRY_REFERENCE := &"Hand_Grip"
const SKELETON_PATH := "MechRig/Skeleton3D:"
## Arm carry: the bones it turns.
const CARRY_BONES: Array[String] = ["upper_arm_L", "forearm_L", "upper_arm_R", "forearm_R"]
## Extra turn (degrees) of the upper arm out from the body, on top of the old carry: the SGG hips are 0.5 m wider each side, the
## shoulders only 0.13 m, so the hands would touch the skirts.
const ARM_CARRY_OUT_DEG := 4.0
## Walk lean (degrees) at the pelvis and the torso, as WALK_LEAN_PELVIS_DEG and WALK_LEAN_TORSO_DEG in haliya_rig_light.py.
const WALK_LEAN_PELVIS_DEG := 3.0
const WALK_LEAN_TORSO_DEG := 3.0


func _initialize() -> void:
	var rig := (load(SGG_RIG) as PackedScene).instantiate()
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var old := Parts.load_glb(OLD_RIG)
	var old_player := old.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var carry := _carry_turns(skeleton, old_player.get_animation(CARRY_REFERENCE), player.get_animation(CARRY_REFERENCE))
	var library := AnimationLibrary.new()
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip).duplicate(true) as Animation
		_add_carry(animation, skeleton, carry)
		_add_lean(animation, skeleton)
		library.add_animation(clip, animation)
		print("%-24s lean %s" % [clip, _lean_summary(animation, skeleton)])
	library.add_animation(STAND, _stand(old_player.get_animation(STAND), skeleton, carry))
	for name in player.get_animation_library_list():
		player.remove_animation_library(name)
	player.add_animation_library(&"", library)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(rig, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT))
	print("wrote %s: %d clips, %s" % [OUT, library.get_animation_list().size(), error_string(err)])
	_copy_import_settings()
	old.free()
	rig.free()
	quit()


## Bone -> carry rotation in the bone's parent frame (applied before the clip's own rotation, as the Blender Action constraint
## "before original" did): the old rig's value of a reference clip times the inverse of the SGG rig's value.
func _carry_turns(skeleton: Skeleton3D, old_clip: Animation, sgg_clip: Animation) -> Dictionary:
	var turns := {}
	for bone in CARRY_BONES:
		var path := NodePath(SKELETON_PATH + bone)
		var old_value := old_clip.rotation_track_interpolate(old_clip.find_track(path, Animation.TYPE_ROTATION_3D), 0.0)
		var sgg_value := sgg_clip.rotation_track_interpolate(sgg_clip.find_track(path, Animation.TYPE_ROTATION_3D), 0.0)
		turns[bone] = old_value * sgg_value.inverse()
	# The extra outward turn of the upper arm, about the mech's forward axis, in the upper arm's parent frame.
	for side: String in ["L", "R"]:
		var bone := "upper_arm_" + side
		var parent := skeleton.get_bone_global_rest(skeleton.get_bone_parent(skeleton.find_bone(bone))).basis.get_rotation_quaternion()
		var sign := 1.0 if side == "L" else -1.0
		var out := Quaternion(Vector3.BACK, deg_to_rad(ARM_CARRY_OUT_DEG) * sign)  # about +Z (the mech front): +X (left) turns up
		turns[bone] = parent.inverse() * out * parent * (turns[bone] as Quaternion)
	return turns


## The carry before every key of the arm rotation tracks.
func _add_carry(animation: Animation, skeleton: Skeleton3D, turns: Dictionary) -> void:
	for bone: String in turns:
		var track := animation.find_track(NodePath(SKELETON_PATH + bone), Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, NodePath(SKELETON_PATH + bone))
			animation.rotation_track_insert_key(track, 0.0, skeleton.get_bone_rest(skeleton.find_bone(bone)).basis.get_rotation_quaternion())
		for k in animation.track_get_key_count(track):
			var q: Quaternion = animation.track_get_key_value(track, k)
			animation.track_set_key_value(track, k, ((turns[bone] as Quaternion) * q).normalized())


## How much the mech moves at a time (0..1), the driver of Haliya_Walk_Lean: the keyed crouch of the pelvis and the distance
## between the foot controls, in their bones' own rest frames.
func _moving(animation: Animation, skeleton: Skeleton3D, time: float) -> float:
	var py := _local_offset(animation, skeleton, "pelvis", time).y
	var l := _local_offset(animation, skeleton, "foot_ctrl_L", time)
	var r := _local_offset(animation, skeleton, "foot_ctrl_R", time)
	return clampf(maxf(-py - 0.2, maxf(absf(l.y - r.y) - 0.3, absf(l.z - r.z) - 0.1)) / 0.2, 0.0, 1.0)


## A bone's keyed move from its rest, in the bone's rest frame (Blender's pose bone location).
func _local_offset(animation: Animation, skeleton: Skeleton3D, bone: String, time: float) -> Vector3:
	var track := animation.find_track(NodePath(SKELETON_PATH + bone), Animation.TYPE_POSITION_3D)
	if track < 0:
		return Vector3.ZERO
	var rest := skeleton.get_bone_rest(skeleton.find_bone(bone))
	return rest.basis.inverse() * (animation.position_track_interpolate(track, time) - rest.origin)


## The lean before the pelvis and torso rotation keys, scaled by the driver at each key; the thighs turn back by the pelvis lean.
func _add_lean(animation: Animation, skeleton: Skeleton3D) -> void:
	var pelvis_track := animation.find_track(NodePath(SKELETON_PATH + "pelvis"), Animation.TYPE_ROTATION_3D)
	if pelvis_track < 0:
		return
	var old_pelvis := animation.duplicate(true) as Animation
	for bone: String in {"pelvis": WALK_LEAN_PELVIS_DEG, "torso": WALK_LEAN_TORSO_DEG}:
		var degrees: float = WALK_LEAN_PELVIS_DEG if bone == "pelvis" else WALK_LEAN_TORSO_DEG
		var track := animation.find_track(NodePath(SKELETON_PATH + bone), Animation.TYPE_ROTATION_3D)
		var parent := skeleton.get_bone_global_rest(skeleton.get_bone_parent(skeleton.find_bone(bone))).basis.get_rotation_quaternion()
		for k in animation.track_get_key_count(track):
			var time := animation.track_get_key_time(track, k)
			var lean := Quaternion(Vector3.RIGHT, deg_to_rad(degrees * _moving(animation, skeleton, time)))  # +X tips the top to the front (+Z)
			var q: Quaternion = animation.track_get_key_value(track, k)
			animation.track_set_key_value(track, k, (parent.inverse() * lean * parent * q).normalized())
	for side: String in ["L", "R"]:
		var track := animation.find_track(NodePath(SKELETON_PATH + "thigh_" + side), Animation.TYPE_ROTATION_3D)
		if track < 0:
			continue
		for k in animation.track_get_key_count(track):
			var time := animation.track_get_key_time(track, k)
			var before := old_pelvis.rotation_track_interpolate(pelvis_track, time)
			var after := animation.rotation_track_interpolate(pelvis_track, time)
			var q: Quaternion = animation.track_get_key_value(track, k)
			animation.track_set_key_value(track, k, (after.inverse() * before * q).normalized())


func _lean_summary(animation: Animation, skeleton: Skeleton3D) -> String:
	var values := []
	for i in 5:
		values.append("%.2f" % _moving(animation, skeleton, animation.length * i / 4.0))
	return ", ".join(values)


## The stance for looking (and the zero of the plate follow): the rotations of the old Haliya_Stand, which already hold the old carry,
## plus the extra outward turn. No position keys: the bones keep the SGG offsets and the pelvis its rest height.
func _stand(old_stand: Animation, skeleton: Skeleton3D, turns: Dictionary) -> Animation:
	var stand := Animation.new()
	stand.length = old_stand.length
	for t in old_stand.get_track_count():
		if old_stand.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := old_stand.track_get_path(t)
		var bone := String(path).get_slice(":", 1)
		if skeleton.find_bone(bone) < 0:
			continue
		var value := old_stand.rotation_track_interpolate(t, 0.0)
		if bone.begins_with("upper_arm_"):
			var parent := skeleton.get_bone_global_rest(skeleton.get_bone_parent(skeleton.find_bone(bone))).basis.get_rotation_quaternion()
			var sign := 1.0 if bone.ends_with("L") else -1.0
			value = parent.inverse() * Quaternion(Vector3.BACK, deg_to_rad(ARM_CARRY_OUT_DEG) * sign) * parent * value
		var track := stand.add_track(Animation.TYPE_ROTATION_3D)
		stand.track_set_path(track, path)
		stand.rotation_track_insert_key(track, 0.0, value.normalized())
	return stand


## The rig's .import keeps its own uid and gets the [params] of sgg_rig.glb.import (the loop mode of each clip).
func _copy_import_settings() -> void:
	var sgg := FileAccess.get_file_as_string(SGG_RIG + ".import")
	var own_path := OUT + ".import"
	var own := FileAccess.get_file_as_string(own_path) if FileAccess.file_exists(own_path) else ""
	var head := own.substr(0, own.find("[params]")) if own.contains("[params]") else "[remap]\n\nimporter=\"scene\"\nimporter_version=1\ntype=\"PackedScene\"\n\n"
	var file := FileAccess.open(own_path, FileAccess.WRITE)
	file.store_string(head + sgg.substr(sgg.find("[params]")))
	file.close()
	print("import settings of ", SGG_RIG, " copied to ", own_path)
