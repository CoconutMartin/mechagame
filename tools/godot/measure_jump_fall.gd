extends SceneTree
## Jump fall measure (user reports 2026-10-22: two fall animations from the top of a jump, and arm and
## shoulder flicker with the Beam Sniper while falling). Holds jump for FALL_CHARGE seconds (default 3,
## a full jump), releases, and logs inside Skeleton3D.skeleton_updated (every modifier applied) the
## per-frame turn of the local bone rotations (degrees) of the bones in FALL_BONES, from the apex to the
## landing. Prints the worst turn per bone, the worst frames, and the limb motion (the total path of the
## hands and feet in model space and the peak speed) over the fall.
## Run: godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_jump_fall.gd
## Environment: FALL_CHARGE (s), FALL_WEAPONS (slot=weapon pairs as in render_jump.gd, e.g.
## "right=beam_sniper"), FALL_BONES (comma list; default the arms, shoulders, torso and legs),
## FALL_VERBOSE=1 (every frame), FALL_ARMS=1 (add the upper arm directions to the frame lines),
## FALL_POSE=1 (add the jump pose's guard and weapon lift), FALL_LIST=1 (print all bone names).

const MAP := "res://maps/urban_small/urban_small.tscn"
const DEFAULT_BONES := "upper_arm_L,upper_arm_R,forearm_L,forearm_R,hand_L,hand_R,torso,shoulder_L,shoulder_R,pelvis,thigh_L,thigh_R,shin_L,shin_R,foot_L,foot_R,head"

var _skeleton: Skeleton3D
var _names: PackedStringArray = []
var _ids: Array[int] = []
var _local: Array[Quaternion] = []
var _turns: Array[float] = []
var _places: Array[Vector3] = []
var _have_previous := false
## FALL_ARMS=1: the upper arm direction in the torso bone's space (x, y, z) per side, set in each update.
var _arm_text := ""


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _on_updated() -> void:
	var places: Array[Vector3] = []
	for i in _ids.size():
		var rotation := _skeleton.get_bone_pose_rotation(_ids[i])
		_turns[i] = rad_to_deg(_local[i].angle_to(rotation)) if _have_previous else 0.0
		_local[i] = rotation
		places.append(_skeleton.get_bone_global_pose(_ids[i]).origin)
	_places = places
	_have_previous = true
	if OS.get_environment("FALL_ARMS") == "1":
		_arm_text = ""
		var torso := _skeleton.get_bone_global_pose(_skeleton.find_bone("torso")).basis.orthonormalized()
		for pair in [["upper_arm_L", "forearm_L"], ["upper_arm_R", "forearm_R"]]:
			var a := _skeleton.get_bone_global_pose(_skeleton.find_bone(pair[0])).origin
			var b := _skeleton.get_bone_global_pose(_skeleton.find_bone(pair[1])).origin
			var d := torso.inverse() * (b - a).normalized()
			_arm_text += "  %s dir (%.2f %.2f %.2f)" % [pair[0], d.x, d.y, d.z]


func _run() -> void:
	var charge := float(OS.get_environment("FALL_CHARGE")) if OS.get_environment("FALL_CHARGE") != "" else 3.0
	var verbose := OS.get_environment("FALL_VERBOSE") == "1"
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	for pair in OS.get_environment("FALL_WEAPONS").split(",", false):
		var slot := pair.get_slice("=", 0).strip_edges()
		var weapon := pair.get_slice("=", 1).strip_edges()
		loadout.set("weapon_" + slot if slot in ["right", "left"] else slot,
				null if weapon == "-" else load("res://data/weapons/%s.tres" % weapon) as WeaponData)
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
	if OS.get_environment("FALL_LIST") == "1":
		for i in _skeleton.get_bone_count():
			print("bone %d %s" % [i, _skeleton.get_bone_name(i)])
	var list := OS.get_environment("FALL_BONES") if OS.get_environment("FALL_BONES") != "" else DEFAULT_BONES
	for bone_name in list.split(",", false):
		var id := _skeleton.find_bone(bone_name)
		if id >= 0:
			_names.append(bone_name)
			_ids.append(id)
			_local.append(Quaternion.IDENTITY)
			_turns.append(0.0)
	_skeleton.skeleton_updated.connect(_on_updated)
	var pose := _skeleton.find_children("*", "SkeletalJumpPose", false, false)[0] as SkeletalJumpPose
	Input.action_press("jump")
	await _frames(int(charge * 60.0))
	Input.action_release("jump")
	var apex := -1
	var landed := -1
	var was_up := false
	# Per bone: worst turn and frame since the apex; path length of the bone place; peak speed.
	var worst: Array[float] = []
	var worst_frame: Array[int] = []
	var path: Array[float] = []
	var peak_speed: Array[float] = []
	var last_place: Array[Vector3] = []
	var turn_sum: Array[float] = []
	var jerk_count: Array[int] = []
	# Rotation at the apex and at the landing: the net turn (a sum of turns far above it = a back and forth).
	var first_local: Array[Quaternion] = []
	var last_local: Array[Quaternion] = []
	for i in _ids.size():
		worst.append(0.0)
		worst_frame.append(-1)
		path.append(0.0)
		peak_speed.append(0.0)
		last_place.append(Vector3.ZERO)
		turn_sum.append(0.0)
		jerk_count.append(0)
		first_local.append(Quaternion.IDENTITY)
		last_local.append(Quaternion.IDENTITY)
	var previous_turn: Array[float] = []
	previous_turn.resize(_ids.size())
	previous_turn.fill(0.0)
	var delta := 1.0 / 60.0
	for frame in 360:
		await _frames(1)
		var vy := player.velocity.y
		if vy > 0.5:
			was_up = true
		if was_up and apex < 0 and vy <= 0.0:
			apex = frame
		if apex >= 0 and landed < 0 and player.is_on_floor():
			landed = frame
		if apex >= 0 and landed < 0 and frame >= apex:
			var w: Array[float] = pose.director.weights
			var line := "%3d vy %6.2f w %.2f %.2f %.2f t %.2f %.2f %.2f tti %.2f" % [frame, vy, w[0], w[1], w[2],
					pose.director.times[0], pose.director.times[1], pose.director.times[2], pose.director.time_to_impact]
			for i in _ids.size():
				var place := _places[i]
				if frame > apex:
					var step := place.distance_to(last_place[i])
					path[i] += step
					peak_speed[i] = maxf(peak_speed[i], step / delta)
				last_place[i] = place
				if frame == apex:
					first_local[i] = _local[i]
				last_local[i] = _local[i]
				if _turns[i] > worst[i]:
					worst[i] = _turns[i]
					worst_frame[i] = frame
				turn_sum[i] += _turns[i]
				# A jerk: this frame's turn is 3 deg or more above the mean of the frames next to it.
				if _turns[i] > 3.0 and _turns[i] > previous_turn[i] * 2.0 + 2.0:
					jerk_count[i] += 1
				previous_turn[i] = _turns[i]
				line += " %s %.1f" % [_names[i], _turns[i]]
			if OS.get_environment("FALL_POSE") == "1":
				line += "  guard %.3f lift %s depth %.2f" % [pose.guard, pose.weapon_offset(), pose.clip_depth]
			if verbose:
				print(line + _arm_text)
		if landed >= 0 and frame > landed + 3:
			break
	print("FALL charge %.1f: apex frame %d, landed frame %d (fall %d frames)" % [charge, apex, landed, landed - apex])
	for i in _ids.size():
		print("FALL %-12s worst turn %5.2f deg (frame %d)  sum of turns %6.1f deg  net %5.1f deg  jerks %d  place path %6.2f m  peak speed %6.1f m/s" % [
				_names[i], worst[i], worst_frame[i], turn_sum[i], rad_to_deg(first_local[i].angle_to(last_local[i])),
				jerk_count[i], path[i], peak_speed[i]])
	Input.action_release("jump")
	quit()
