extends SceneTree
## Ctrl kneel test (user report 2026-11-02: "only the camera lowers"). The player kneels (crouch action), holds, stands
## (crouch again), kneels again and stands with W. Every sample is taken inside the skeleton update (after the modifiers):
##   - the pelvis drops by about KNEEL_DROP (2.0 to 3.0 m) and the head comes down with it,
##   - the lowest point of every body mesh stays at or above the ground (down to MIN_Y), all through the transitions,
##   - at the full kneel the lowest point sits on the ground (within GROUND_TOL): the right knee and toes, the left foot,
##   - the left foot stays flat on the ground in front, the right knee is near the ground,
##   - the torso is upright (leans at most MAX_LEAN degrees),
##   - it stands up again: the pelvis is back at its standing height and the lowest point on the ground,
##   - the same with the Beam Rifle raised (the sniping stance under the kneel).
## Exit code 1 on a failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_kneel_pose.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## MECH=haliya runs the test on Haliya (tools/godot/test_mech_choice.gd).
const MechChoice := preload("res://tools/godot/test_mech_choice.gd")
const MIN_Y := -0.12
const GROUND_TOL := 0.2
const MIN_DROP := 2.0
const MAX_DROP := 3.0
const MAX_LEAN := 15.0

var _failures := 0
var _skeleton: Skeleton3D
var _player: Mech


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	await _case(switcher, "Beam Rifle in the hand (map loadout), no aim", false)
	await _case(switcher, "Beam Rifle raised (aim held)", true)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _case(switcher: LoadoutSwitcher, label: String, aim: bool) -> void:
	print("== ", label)
	switcher.rebuild(MechChoice.apply(switcher.current_loadout.duplicate() as Loadout), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	_player = switcher.mech
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var pose := _player.find_child("KneelPose", true, false) as SkeletalKneelPose
	_check(pose != null, "the rigged mech has a KneelPose modifier")
	if pose == null:
		return
	if aim:
		Input.action_press("aim")
		await _frames(60)
	var stand := await _measure()
	print("     standing: pelvis y %.2f head y %.2f lowest %.2f" % [stand.pelvis, stand.head, stand.lowest])
	_check(absf(stand.lowest) < GROUND_TOL, "standing: the lowest point is on the ground (%.2f)" % stand.lowest)
	# Down.
	Input.action_press("crouch")
	await _frames(2)
	Input.action_release("crouch")
	var worst := INF
	var mid_seen := false
	for i in 120:
		await _frames(1)
		if i % 6 == 0:
			var now := await _measure()
			worst = minf(worst, now.lowest)
			if _player.kneel.amount > 0.4 and _player.kneel.amount < 0.6 and not mid_seen:
				mid_seen = true
				print("     half way: pelvis y %.2f lowest %.2f left foot y %.2f right foot y %.2f" % [now.pelvis, now.lowest, now.foot_l, now.foot_r])
	var down := await _measure()
	print("     kneeling: amount %.2f pelvis y %.2f (drop %.2f) head y %.2f lowest %.2f left foot y %.2f z %.2f right knee y %.2f lean %.1f" % [
			_player.kneel.amount, down.pelvis, stand.pelvis - down.pelvis, down.head, down.lowest, down.foot_l, down.foot_l_z, down.knee_r, down.lean])
	_check(_player.kneel.amount > 0.99, "the kneel reaches 1")
	# The sniping stance already lowers the standing hips by 0.6 m, so the aimed case checks the kneel height itself.
	var drop: float = stand.pelvis - down.pelvis
	var min_drop := MIN_DROP - (0.7 if aim else 0.0)
	_check(drop >= min_drop and drop <= MAX_DROP, "the pelvis drops %.2f m (%.1f to %.1f)" % [drop, min_drop, MAX_DROP])
	_check(down.pelvis >= 3.2 and down.pelvis <= 3.9, "the kneeling pelvis height is %.2f m (3.2 to 3.9)" % down.pelvis)
	_check(stand.head - down.head >= min_drop - 0.3, "the head comes down %.2f m" % (stand.head - down.head))
	_check(worst >= MIN_Y, "no mesh goes under the ground while kneeling down (lowest %.2f)" % worst)
	_check(absf(down.lowest) <= GROUND_TOL, "kneeling: the lowest point sits on the ground (%.2f)" % down.lowest)
	_check(absf(down.foot_l - stand.foot_l) < 0.15, "the left foot stands flat at its height (ankle %.2f, standing %.2f)" % [down.foot_l, stand.foot_l])
	_check(down.foot_l_z > 0.5 and (aim or down.foot_l_z - stand.foot_l_z > 0.8), "the left foot is in front (%.2f m ahead of the mech, %.2f m forward)" % [down.foot_l_z, down.foot_l_z - stand.foot_l_z])
	_check(down.knee_r < 1.2, "the right knee is near the ground (%.2f)" % down.knee_r)
	_check(absf(down.lean) <= MAX_LEAN, "the torso is upright (lean %.1f deg)" % down.lean)
	# Up.
	Input.action_press("crouch")
	await _frames(2)
	Input.action_release("crouch")
	worst = INF
	for i in 120:
		await _frames(1)
		if i % 6 == 0:
			worst = minf(worst, (await _measure()).lowest)
	var up := await _measure()
	_check(_player.kneel.amount < 0.01, "the kneel goes back to 0")
	_check(absf(up.pelvis - stand.pelvis) < 0.35, "it stands again: pelvis y %.2f (standing %.2f)" % [up.pelvis, stand.pelvis])
	_check(worst >= MIN_Y, "no mesh goes under the ground while standing up (lowest %.2f)" % worst)
	_check(absf(up.lowest) <= GROUND_TOL, "standing: the lowest point is on the ground (%.2f)" % up.lowest)
	# Down again, W stands up.
	Input.action_press("crouch")
	await _frames(2)
	Input.action_release("crouch")
	await _frames(110)
	_check(_player.kneel.amount > 0.99, "second kneel reaches 1")
	Input.action_press("move_forward")
	await _frames(110)
	Input.action_release("move_forward")
	_check(_player.kneel.amount < 0.01, "W stands the mech up")
	# A flinch (hit reaction clip) while kneeling: the legs stay down.
	var hit := _player.find_child("HitAnimation", true, false) as SkeletalHitAnimation
	if hit != null and hit.clips.size() > 1:
		Input.action_press("crouch")
		await _frames(2)
		Input.action_release("crouch")
		await _frames(110)
		var before := await _measure()
		hit.call("_try_start", hit.clips[1], false)
		var pelvis_high := 0.0
		var lowest := INF
		var started := false
		for i in 90:
			await _frames(1)
			started = started or hit.is_playing
			if i % 3 == 0:
				var now := await _measure()
				pelvis_high = maxf(pelvis_high, now.pelvis - before.pelvis)
				lowest = minf(lowest, now.lowest)
		_check(started, "the flinch clip played while kneeling")
		_check(pelvis_high < 0.4 and lowest >= MIN_Y, "a flinch while kneeling keeps the hips down (rise %.2f m, lowest %.2f)" % [pelvis_high, lowest])
		Input.action_press("crouch")
		await _frames(2)
		Input.action_release("crouch")
		await _frames(110)
	if aim:
		Input.action_release("aim")
	await _frames(30)


## Pelvis, head, ankle heights (world y), the right knee height, the left ankle z, the torso lean (degrees) and the lowest
## mesh point (world y) in the skeleton update now.
func _measure() -> Dictionary:
	await _skeleton.skeleton_updated
	var to_world := _skeleton.global_transform
	var out := {}
	var bone := func(name: StringName) -> Transform3D:
		return to_world * _skeleton.get_bone_global_pose(_skeleton.find_bone(name))
	out.pelvis = (bone.call(&"pelvis") as Transform3D).origin.y
	out.head = (bone.call(&"head") as Transform3D).origin.y
	out.foot_l = (bone.call(&"foot_L") as Transform3D).origin.y
	out.foot_r = (bone.call(&"foot_R") as Transform3D).origin.y
	out.foot_l_z = (_player.global_transform.affine_inverse() * (bone.call(&"foot_L") as Transform3D).origin).z * -1.0
	out.knee_r = (bone.call(&"shin_R") as Transform3D).origin.y
	var up := (bone.call(&"torso") as Transform3D).basis.orthonormalized() * (_skeleton.get_bone_global_rest(_skeleton.find_bone(&"torso")).basis.orthonormalized().inverse() * Vector3.UP)
	out.lean = rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var poses: Array[Transform3D] = []
	for i in _skeleton.get_bone_count():
		poses.append(to_world * _skeleton.get_bone_global_pose(i))
	var lowest := INF
	for node in _skeleton.get_children():
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.skin == null or not mesh.visible or mesh.mesh == null:
			continue
		var name := String(mesh.name)
		# SGG body meshes (Leg_, Pelvis, Torso) and Haliya's (Legs_, Core_: legs, pelvis and torso pieces).
		if not (name.begins_with("Leg_") or name.begins_with("Pelvis") or name.begins_with("Torso") or name.begins_with("Legs_") or name.begins_with("Core_")):
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty():
			continue
		var per := bones.size() / vertices.size()
		for v in vertices.size():
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var index := bones[v * per + best]
			var b := _skeleton.find_bone(mesh.skin.get_bind_name(index))
			if b < 0:
				continue
			lowest = minf(lowest, (poses[b] * (mesh.skin.get_bind_pose(index) * vertices[v])).y)
	out.lowest = lowest - _player.global_position.y
	out.pelvis -= _player.global_position.y
	out.head -= _player.global_position.y
	out.foot_l -= _player.global_position.y
	out.foot_r -= _player.global_position.y
	out.knee_r -= _player.global_position.y
	return out
