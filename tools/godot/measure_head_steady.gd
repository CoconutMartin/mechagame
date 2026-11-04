extends SceneTree
## Head steadiness probe (user request 2026-11-02: "always keep the head steady when aiming down or when shooting").
## For each weapon the player aims at PITCH degrees (negative = down), holds the aim and fires for FRAMES physics frames.
## Inside every skeleton update (after all modifiers) it reads the head bone's world rotation and prints:
##   rot  : the turn of the head between two frames (degrees): mean and largest
##   yaw, pitch, roll : the head's world heading, elevation and roll (degrees): the spread (largest - smallest) and the lowest pitch
##   pos  : the head's step between two frames (m): largest
##   neck : the head's turn against the torso bone (degrees): the largest
## and the aim jitter of the same run. Exit code 1 when a weapon's largest per-frame turn is above MAX_STEP_DEG.
## Environment: DISABLE=1 (HeadSteady off: the old head), KICK=1 (a camera kick every 12 frames: 2 degrees to alternate sides, 1 degree up), WEAPONS (comma list of data/weapons names, default heavy_rifle,smg,shotgun,beam_rifle),
##   PITCH (degrees, default -30), FRAMES (default 240), MAX_STEP_DEG (default 0.6), KNEEL=1 (kneel first),
##   SKIP (frames after the trigger press that are not sampled; default 0: the head turns into the barrel while the gun comes
##   up, user request 2026-11-04 "head parallel to the barrel in ADS", so use SKIP=40 to measure the steadiness after that).
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_head_steady.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _failures := 0
var _skeleton: Skeleton3D
var _head := -1
var _torso := -1
var _last_basis := Basis.IDENTITY
var _last_pos := Vector3.ZERO
var _have_last := false
var _sum := 0.0
var _count := 0
var _max_step := 0.0
var _max_pos := 0.0
var _max_neck := 0.0
var _yaws: Array[float] = []
var _pitches: Array[float] = []
var _rolls: Array[float] = []
var _sampling := false
var _shots := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _sample() -> void:
	if not _sampling:
		return
	var pose := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head)
	var basis := pose.basis.orthonormalized()
	var torso := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_torso)).basis.orthonormalized()
	_max_neck = maxf(_max_neck, rad_to_deg((torso.inverse() * basis).get_rotation_quaternion().get_angle()))
	# The head's own forward is the model's +Z (the model is turned 180 degrees, so the world forward is -Z at rest).
	var forward := basis * Vector3.BACK
	var up := basis * Vector3.UP
	_yaws.append(rad_to_deg(atan2(forward.x, forward.z)))
	_pitches.append(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))))
	var flat_right := Vector3.UP.cross(forward).normalized()
	_rolls.append(rad_to_deg(atan2(up.dot(flat_right), up.dot(Vector3.UP))))
	if _have_last:
		var step := rad_to_deg((_last_basis.inverse() * basis).get_rotation_quaternion().get_angle())
		_sum += step
		_count += 1
		_max_step = maxf(_max_step, step)
		if OS.has_environment("TRACE") and step > float(OS.get_environment("TRACE")):
			print("  f%d step %.2f yaw %.1f pitch %.1f" % [_count, step, _yaws[-1], _pitches[-1]])
		_max_pos = maxf(_max_pos, pose.origin.distance_to(_last_pos))
	_last_basis = basis
	_last_pos = pose.origin
	_have_last = true


func _spread(values: Array[float], wrap: bool) -> float:
	if values.is_empty():
		return 0.0
	var low := INF
	var high := -INF
	var base := values[0]
	for v in values:
		var d := wrapf(v - base, -180.0, 180.0) if wrap else v - base
		low = minf(low, d)
		high = maxf(high, d)
	return high - low


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var names := (OS.get_environment("WEAPONS") if OS.get_environment("WEAPONS") != "" else "heavy_rifle,smg,shotgun,beam_rifle").split(",", false)
	var pitch := float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else -30.0
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 240
	var limit := float(OS.get_environment("MAX_STEP_DEG")) if OS.get_environment("MAX_STEP_DEG") != "" else 0.6
	for weapon_name in names:
		var loadout := switcher.current_loadout.duplicate() as Loadout
		loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon_name) as WeaponData
		loadout.weapon_left = null
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(60)
		var player := switcher.mech
		var rig := player.get_node("CameraRig") as MechCameraRig
		_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
		_head = _skeleton.find_bone(&"head")
		_torso = _skeleton.find_bone(&"torso")
		if not _skeleton.skeleton_updated.is_connected(_sample):
			_skeleton.skeleton_updated.connect(_sample)
		_have_last = false
		_sum = 0.0
		_count = 0
		_max_step = 0.0
		_max_pos = 0.0
		_max_neck = 0.0
		_yaws.clear()
		_pitches.clear()
		_rolls.clear()
		if OS.get_environment("KNEEL") == "1":
			Input.action_press("crouch")
			await _frames(2)
			Input.action_release("crouch")
			await _frames(100)
		Input.action_press("aim")
		rig._target_pitch = deg_to_rad(pitch)
		rig._pitch_spring.value = deg_to_rad(pitch)
		await _frames(60)
		rig._target_pitch = deg_to_rad(pitch)
		var skip := int(OS.get_environment("SKIP")) if OS.get_environment("SKIP") != "" else 0
		_sampling = skip <= 0
		var jitter := 0.0
		var weapon := (player.get_node("WeaponController") as WeaponController).right_weapon
		_shots = 0
		weapon.fired.connect(func() -> void: _shots += 1)
		Input.action_press("use_right_arm")
		var steady := player.find_child("HeadSteady", true, false) as SkeletonModifier3D
		if steady != null and OS.has_environment("DISABLE"):
			steady.active = false
		for i in frames:
			await _frames(1)
			if i == skip:
				_sampling = true
				_have_last = false
			# KICK=1: a muzzle kick of 2 degrees to alternate sides and 1 degree up every 12 frames (a fast gun).
			if OS.has_environment("KICK") and i % 12 == 0:
				rig._target_yaw += deg_to_rad(2.0) * (1.0 if (i / 12) % 2 == 0 else -1.0)
				rig._target_pitch = deg_to_rad(pitch) + deg_to_rad(1.0) * (1.0 if (i / 12) % 2 == 0 else 0.0)
			rig._target_pitch = maxf(rig._target_pitch, rig.get_min_pitch())
		Input.action_release("use_right_arm")
		_sampling = false
		Input.action_release("aim")
		var low_pitch := INF
		for p in _pitches:
			low_pitch = minf(low_pitch, p)
		var ok := _max_step <= limit
		print(("ok   " if ok else "FAIL ") + "%s pitch %.0f: rot mean %.3f max %.2f deg/frame | yaw spread %.1f pitch spread %.1f (lowest %.1f) roll spread %.1f | pos max %.3f m | neck max %.1f deg | cam pitch %.1f | shots %d (%s)" % [
				weapon_name, pitch, _sum / maxf(_count, 1), _max_step, _spread(_yaws, true), _spread(_pitches, false), low_pitch,
				_spread(_rolls, true), _max_pos, _max_neck, rad_to_deg(rig.pitch), _shots, weapon.get_class()])
		if not ok:
			_failures += 1
		await _frames(60)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
