extends SceneTree
## Other-arm twitch probe (user report 2026-11-04: "other arm is twitching while the other arm is executing the
## pilebunker animation"). The player holds a Pile Bunker in SIDE (R or L, default R) and plays clip NUMBER (default
## 3; "all" = 3, 4, 5); the other arm's upper arm and forearm turns (torso frame, after the skeleton modifiers) are read
## each frame. Prints the largest turn step per frame and the frames with a step over SPIKE degrees (default 6) with
## the clip time and the melee weight.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_other_arm_twitch.gd

var _skeleton: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _pose(bone: String) -> Transform3D:
	return _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))


func _run() -> void:
	var side := _env("SIDE", "R")
	var other := "L" if side == "R" else "R"
	var spike := float(_env("SPIKE", "6"))
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var numbers := [3, 4, 5] if _env("NUMBER", "3") == "all" else [int(_env("NUMBER", "3"))]
	for number: int in numbers:
		var loadout := switcher.current_loadout.duplicate() as Loadout
		var pb := load(_env("BUNKER", "res://data/weapons/pile_bunker.tres")) as WeaponData
		loadout.weapon_right = pb if side == "R" else null
		loadout.weapon_left = pb if side == "L" else null
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(60)
		var mech := switcher.mech
		_skeleton = mech.find_child("Skeleton3D", true, false) as Skeleton3D
		var weapons := mech.get_node("WeaponController") as WeaponController
		var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
		bunker.clip_number = number
		var melee := mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
		var rig_node := mech.find_child("ArmRig", true, false)
		for key in ["clip_release_speed_deg", "clip_target_smooth", "clip_out_speed_deg"]:
			if OS.has_environment(key.to_upper()):
				rig_node.set(key, float(OS.get_environment(key.to_upper())))
		if OS.has_environment("NOKEEP"):
			var rig := mech.find_child("ArmRig", true, false)
			rig.set(&"clip_max_out_deg", 0.0)
			rig.set(&"clip_max_forward_deg", 0.0)
		var button := "use_right_arm" if side == "R" else "use_left_arm"
		Input.action_press(button)
		await _frames(30)
		Input.action_release(button)
		var last_upper := Basis.IDENTITY
		var last_fore := Basis.IDENTITY
		var largest_upper := 0.0
		var largest_fore := 0.0
		var spikes: Array[String] = []
		var first := true
		var last_du := Vector3.ZERO
		var last_df := Vector3.ZERO
		var reversals := 0
		var reversal_frames: Array[String] = []
		for frame in 330:
			await _skeleton.skeleton_updated
			var torso := _pose("torso").basis
			var upper := torso.inverse() * _pose("upper_arm_" + other).basis
			var fore := upper.inverse() * (torso.inverse() * _pose("forearm_" + other).basis)
			if not first:
				var du := rad_to_deg(Quaternion(last_upper.orthonormalized()).angle_to(Quaternion(upper.orthonormalized())))
				var df := rad_to_deg(Quaternion(last_fore.orthonormalized()).angle_to(Quaternion(fore.orthonormalized())))
				# A twitch turns one way, then back: the step's axis-angle flips (dot < 0) with both steps over 2 deg.
				var qu := Quaternion(last_upper.orthonormalized()).inverse() * Quaternion(upper.orthonormalized())
				var qf := Quaternion(last_fore.orthonormalized()).inverse() * Quaternion(fore.orthonormalized())
				var vu := qu.get_axis() * qu.get_angle() if qu.get_angle() > 0.0001 else Vector3.ZERO
				var vf := qf.get_axis() * qf.get_angle() if qf.get_angle() > 0.0001 else Vector3.ZERO
				if (vu.dot(last_du) < 0.0 and du > 2.0 and rad_to_deg(last_du.length()) > 2.0) \
						or (vf.dot(last_df) < 0.0 and df > 2.0 and rad_to_deg(last_df.length()) > 2.0):
					reversals += 1
					if reversal_frames.size() < 10:
						reversal_frames.append("f%d t%.2f w%.2f up %.1f fore %.1f" % [frame, melee.external_time(bunker),
								melee._weight(), du, df])
				last_du = vu
				last_df = vf
				largest_upper = maxf(largest_upper, du)
				largest_fore = maxf(largest_fore, df)
				if (du > spike or df > spike) and spikes.size() < 12:
					spikes.append("f%d t%.2f w%.2f state%d up %.1f fore %.1f" % [frame, melee.external_time(bunker),
							melee._weight(), bunker.state, du, df])
			first = false
			last_upper = upper
			last_fore = fore
			await physics_frame
			if frame > 30 and bunker.state == PileBunkerWeapon.State.IDLE:
				break
		print("clip %d, %s Pile Bunker: other arm largest step: upper %.1f deg, forearm %.1f deg per frame" % [number,
				side, largest_upper, largest_fore])
		print("   direction reversals over 2 deg: %d" % reversals)
		if OS.has_environment("SHOW_SPIKES"):
			for line in spikes:
				print("   spike ", line)
		for line in reversal_frames:
			print("   rev ", line)
		await _frames(60)
	quit()
