extends SceneTree
## Jump animation strength measure (user requests 2026-10-24: feet at the standing width on the landing,
## and a calm small motion for a short charge). Holds jump for SCALE_CHARGE seconds (default 3), releases,
## and follows the jump to the end of the landing recovery. SCALE_DROP (m) drops the mech from that height
## instead (a walk off an edge: no charge). Inside Skeleton3D.skeleton_updated (every modifier applied) it
## records, per phase (charge, rise, fall, landing): the worst bone turn in one frame (degrees, local
## rotations of all bones), the sum of the turns, and the peak speed of the hands and feet (m/s, skeleton
## space, so the mech's own travel is not counted). The foot spacing (left to right ankle distance sideways
## in the model frame) is logged from the touchdown through the recovery and compared with the standing
## width measured before the jump.
## Run: godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_jump_scale.gd
## Environment: SCALE_CHARGE (s), SCALE_DROP (m), SCALE_WEAPONS (slot=weapon pairs as in render_jump.gd),
## SCALE_VERBOSE=1 (one line per frame), SCALE_SET (properties of the jump pose, "name=value,...").

const MAP := "res://maps/urban_small/urban_small.tscn"
const LIMBS := ["hand_L", "hand_R", "foot_L", "foot_R"]
const PHASES := ["charge", "rise", "fall", "landing"]

var _skeleton: Skeleton3D
var _ids: Array[int] = []
var _names: PackedStringArray = []
var _local: Array[Quaternion] = []
var _turns: Array[float] = []
var _places := {}
var _have_previous := false
var _ankle_l: Vector3 = Vector3.ZERO
var _ankle_r: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _on_updated() -> void:
	for i in _ids.size():
		var rotation := _skeleton.get_bone_pose_rotation(_ids[i])
		_turns[i] = rad_to_deg(_local[i].angle_to(rotation)) if _have_previous else 0.0
		_local[i] = rotation
	for limb: String in LIMBS:
		_places[limb] = _skeleton.get_bone_global_pose(_skeleton.find_bone(limb)).origin
	_ankle_l = _places["foot_L"]
	_ankle_r = _places["foot_R"]
	_have_previous = true


func _run() -> void:
	var charge := float(OS.get_environment("SCALE_CHARGE")) if OS.get_environment("SCALE_CHARGE") != "" else 3.0
	var drop := float(OS.get_environment("SCALE_DROP")) if OS.get_environment("SCALE_DROP") != "" else 0.0
	var verbose := OS.get_environment("SCALE_VERBOSE") == "1"
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	for pair in OS.get_environment("SCALE_WEAPONS").split(",", false):
		var slot := pair.get_slice("=", 0).strip_edges()
		var weapon := pair.get_slice("=", 1).strip_edges()
		loadout.set("weapon_" + slot if slot in ["right", "left"] else slot,
				null if weapon == "-" else load("res://data/weapons/%s.tres" % weapon) as WeaponData)
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
	for i in _skeleton.get_bone_count():
		_ids.append(i)
		_names.append(_skeleton.get_bone_name(i))
		_local.append(Quaternion.IDENTITY)
		_turns.append(0.0)
	_skeleton.skeleton_updated.connect(_on_updated)
	var pose := _skeleton.find_children("*", "SkeletalJumpPose", false, false)[0] as SkeletalJumpPose
	for pair in OS.get_environment("SCALE_SET").split(",", false):
		var key := pair.get_slice("=", 0).strip_edges()
		var text := pair.get_slice("=", 1).strip_edges()
		var value: Variant = (text == "true") if text in ["true", "false"] else float(text)
		if key in pose:
			pose.set(key, value)
		elif key in pose.director:
			pose.director.set(key, value)
		elif key in player.jump_charge:
			player.jump_charge.set(key, value)
		elif key in player.landing_recovery:
			player.landing_recovery.set(key, value)
	await _frames(20)
	var standing := absf(_ankle_l.x - _ankle_r.x)
	var origin := player.global_position
	var recovery := player.landing_recovery
	if drop > 0.0:
		player.global_position = origin + Vector3.UP * drop
		player.velocity = Vector3.ZERO
	else:
		Input.action_press("jump")
	var released := drop > 0.0
	var was_up := drop > 0.0
	var in_air := false
	var landed := -1
	var stats := {}
	for phase: String in PHASES:
		var row := {"worst": 0.0, "bone": "", "frame": -1, "sum": 0.0, "frames": 0, "peak": {}, "peak_all": 0.0}
		for limb: String in LIMBS:
			row.peak[limb] = 0.0
		stats[phase] = row
	var last_places := {}
	var spacing_min := INF
	var spacing_max := -INF
	var spacing_touch := 0.0
	var spacing_samples: Array[float] = []
	var delta := 1.0 / 60.0
	for frame in 60 * 16:
		await _frames(1)
		var t := frame / 60.0
		if not released and t >= charge:
			Input.action_release("jump")
			released = true
		var up := not player.is_on_floor()
		if up:
			in_air = true
		var phase := "charge"
		if up:
			phase = "rise" if player.velocity.y > 0.0 else "fall"
		elif in_air:
			phase = "landing"
		if in_air and not up and landed < 0:
			landed = frame
			spacing_touch = absf(_ankle_l.x - _ankle_r.x)
		var row: Dictionary = stats[phase]
		var worst_now := 0.0
		var worst_bone := ""
		for i in _ids.size():
			if _turns[i] > worst_now:
				worst_now = _turns[i]
				worst_bone = _names[i]
			row.sum += _turns[i]
		if worst_now > row.worst:
			row.worst = worst_now
			row.bone = worst_bone
			row.frame = frame
		row.frames += 1
		var frame_speed := 0.0
		for limb: String in LIMBS:
			var place: Vector3 = _places[limb]
			if last_places.has(limb):
				var speed := place.distance_to(last_places[limb]) / delta
				frame_speed = maxf(frame_speed, speed)
				row.peak[limb] = maxf(row.peak[limb], speed)
				row.peak_all = maxf(row.peak_all, speed)
			last_places[limb] = place
		var spacing := absf(_ankle_l.x - _ankle_r.x)
		if landed >= 0:
			spacing_min = minf(spacing_min, spacing)
			spacing_max = maxf(spacing_max, spacing)
			spacing_samples.append(spacing)
		if verbose:
			print("%3d %-7s vy %6.2f speed %5.1f turn %5.2f (%s) spacing %.3f rec %.2f crouch %.2f land %.2f w %.2f %.2f %.2f" % [
					frame, phase, player.velocity.y, frame_speed, worst_now, worst_bone, spacing, recovery.time_left, pose.crouch, pose.landing,
					pose.director.weights[0], pose.director.weights[1], pose.director.weights[2]])
		if landed >= 0 and not recovery.is_recovering() and frame > landed + 30:
			break
	print("SCALE charge %.2f drop %.1f: standing width %.3f m; touchdown %.3f; during recovery min %.3f max %.3f (worst off standing %.3f m); fall %.2f m, recovery %.2f s" % [
			charge, drop, standing, spacing_touch, spacing_min, spacing_max,
			maxf(absf(spacing_min - standing), absf(spacing_max - standing)), recovery.fall_height, recovery.duration])
	for phase: String in PHASES:
		var row: Dictionary = stats[phase]
		print("SCALE %-7s frames %3d worst turn %5.2f deg (%s, frame %d) sum of turns %7.1f deg  peak speed %5.1f m/s  hands %.1f %.1f feet %.1f %.1f" % [
				phase, row.frames, row.worst, row.bone, row.frame, row.sum, row.peak_all,
				row.peak.hand_L, row.peak.hand_R, row.peak.foot_L, row.peak.foot_R])
	Input.action_release("jump")
	quit()
