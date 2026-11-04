extends SceneTree
## Head parallel to the barrel in ADS (user request 2026-11-04: "head: should be parallel with the direction of all firearm
## during ADS"). For each weapon and camera pitch the player holds the aim key (RMB; the trigger too for a one-hand gun, which
## raises with it, but the gun cannot fire: a long reload) and after the hold has settled the probe measures, inside the skeleton
## update (after every modifier), the angle between the head's forward and the barrel (the muzzle's -Z) in degrees: total,
## elevation part and heading part, and the roll of the head. A steep aim that the head limits (parallel_max_down_deg) is
## expected to differ by the part past the limit; the limit is printed. Exit code 1 when the head's elevation is more than MAX_DEG from the barrel's (clamped to the limits against the torso),
## its heading is more than MAX_DEG off, or it rolls more than MAX_ROLL_DEG.
## Environment: DISABLE=1 (parallel look off: the old steady head, the before numbers), WEAPONS (comma list of
## data/weapons names), PITCHES (comma list, camera pitch in degrees), MAX_DEG (default 3), MAX_ROLL_DEG (default 3).
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_head_parallel.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _failures := 0
var _skeleton: Skeleton3D
var _head := -1
var _sampling := false
var _angles: Array[float] = []
var _pitch_diffs: Array[float] = []
var _yaw_diffs: Array[float] = []
var _rolls: Array[float] = []
var _barrel_pitches: Array[float] = []
var _head_pitches: Array[float] = []
var _muzzle: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _sample() -> void:
	if not _sampling or _muzzle == null or not is_instance_valid(_muzzle):
		return
	var head := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head)).basis.orthonormalized()
	var forward := head * Vector3.BACK
	var up := head * Vector3.UP
	var barrel := -_muzzle.global_basis.z.normalized()
	_angles.append(rad_to_deg(forward.angle_to(barrel)))
	_pitch_diffs.append(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)) - asin(clampf(barrel.y, -1.0, 1.0))))
	_yaw_diffs.append(rad_to_deg(wrapf(atan2(forward.x, forward.z) - atan2(barrel.x, barrel.z), -PI, PI)))
	var flat_right := Vector3.UP.cross(forward).normalized()
	_rolls.append(rad_to_deg(atan2(up.dot(flat_right), up.dot(Vector3.UP))))
	_barrel_pitches.append(rad_to_deg(asin(clampf(barrel.y, -1.0, 1.0))))
	_head_pitches.append(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))))


func _mean(values: Array[float]) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / maxf(values.size(), 1.0)


func _largest(values: Array[float]) -> float:
	var out := 0.0
	for v in values:
		out = maxf(out, absf(v))
	return out


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var names := (OS.get_environment("WEAPONS") if OS.get_environment("WEAPONS") != "" else "heavy_rifle,smg,shotgun,auto_cannon,beam_rifle,beam_sniper,beam_rifle_4").split(",", false)
	var pitches := (OS.get_environment("PITCHES") if OS.get_environment("PITCHES") != "" else "0,-12,-25,10").split(",", false)
	var max_deg := float(OS.get_environment("MAX_DEG")) if OS.get_environment("MAX_DEG") != "" else 3.0
	var max_roll := float(OS.get_environment("MAX_ROLL_DEG")) if OS.get_environment("MAX_ROLL_DEG") != "" else 3.0
	var kneel := OS.get_environment("KNEEL") == "1"
	for weapon_name in names:
		for pitch_text in pitches:
			var pitch := float(pitch_text)
			var loadout := switcher.current_loadout.duplicate() as Loadout
			loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon_name) as WeaponData
			loadout.weapon_left = null
			switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
			await _frames(100)
			var player := switcher.mech
			var rig := player.get_node("CameraRig") as MechCameraRig
			var controller := player.get_node("WeaponController") as WeaponController
			_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
			_head = _skeleton.find_bone(&"head")
			if not _skeleton.skeleton_updated.is_connected(_sample):
				_skeleton.skeleton_updated.connect(_sample)
			var steady := player.find_child("HeadSteady", true, false) as SkeletalHeadSteady
			if OS.has_environment("DISABLE"):
				steady.parallel_to_barrel = false
			if kneel:
				Input.action_press("crouch")
				await _frames(2)
				Input.action_release("crouch")
				await _frames(100)
			var weapon := controller.right_weapon
			_muzzle = SkeletalHeadSteady._muzzle_of(weapon)
			Input.action_press("aim")
			Input.action_press("use_right_arm")
			rig._target_pitch = deg_to_rad(pitch)
			rig._pitch_spring.value = deg_to_rad(pitch)
			for i in 100:
				weapon.reload_left = 1000.0
				rig._target_pitch = maxf(deg_to_rad(pitch), rig.get_min_pitch())
				await _frames(1)
			_angles.clear()
			_pitch_diffs.clear()
			_yaw_diffs.clear()
			_rolls.clear()
			_barrel_pitches.clear()
			_head_pitches.clear()
			_sampling = true
			for i in 40:
				weapon.reload_left = 1000.0
				rig._target_pitch = maxf(deg_to_rad(pitch), rig.get_min_pitch())
				await _frames(1)
			_sampling = false
			Input.action_release("aim")
			Input.action_release("use_right_arm")
			var barrel_pitch := _mean(_barrel_pitches)
			# The part of the elevation difference the limits explain.
			# The head looks along the barrel, except where its elevation limit (against the torso) holds it.
			var torso_pitch := rad_to_deg(steady.torso_elevation)
			var head_pitch := _mean(_head_pitches)
			var expected := clampf(barrel_pitch, torso_pitch - steady.parallel_max_down_deg, torso_pitch + steady.parallel_max_up_deg)
			var limited := absf(barrel_pitch - expected)
			var excess := _largest(_yaw_diffs)
			var ok := absf(head_pitch - expected) <= max_deg and excess <= max_deg and _largest(_rolls) <= max_roll
			if OS.has_environment("DISABLE"):
				ok = true
			print(("ok   " if ok else "FAIL ") + "%s %s pitch %+.0f: head vs barrel mean %.2f max %.2f deg (elevation %+.2f, heading %+.2f) | barrel elevation %.1f head elevation %.1f | head roll max %.2f | parallel %.2f | torso elev %.1f, limits hold it %.1f deg off" % [
					weapon_name, "kneel" if kneel else "stand", pitch, _mean(_angles), _largest(_angles), _mean(_pitch_diffs), _mean(_yaw_diffs),
					barrel_pitch, _mean(_head_pitches), _largest(_rolls), steady.parallel_amount, torso_pitch, limited])
			if not ok:
				_failures += 1
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
