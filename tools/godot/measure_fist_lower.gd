extends SceneTree
## Fist lowering probe (user report 2026-10-24: after an A / D / S punch the fist snapped to the neutral hang).
## Bare hands, one punch with MOVE held (move_left, move_right, move_back or none), then prints the largest
## per-frame move of each hand bone (torso frame) after the swing clip ended, and the frames over STEP_M.
## HOLD=1 keeps MOVE held the whole time.
## Run: MOVE=move_left godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_fist_lower.gd

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = null
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var rig := mech.find_children("*", "SkeletalArmRig", true, false)[0] as SkeletalArmRig
	var melee := mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	var limit := float(OS.get_environment("STEP_M")) if OS.has_environment("STEP_M") else 0.15
	var move := OS.get_environment("MOVE")
	if move != "":
		Input.action_press(move)
	await _frames(3)
	Input.action_press("use_right_arm")
	await _frames(4)
	Input.action_release("use_right_arm")
	var last := {}
	var worst := {"R": 0.0, "L": 0.0}
	var ended := -1
	for frame in 240:
		await _frames(1)
		if move != "" and frame == 20 and not OS.has_environment("HOLD"):
			Input.action_release(move)
		if not melee.is_playing and ended < 0:
			ended = frame
			print("f%d swing ended (%s)" % [frame, melee._attack.resource_path.get_file() if melee._attack else "-"])
		var to_torso := rig.torso.global_transform.affine_inverse()
		# The torso in the mech frame (a body snap does not show in the torso frame).
		var torso_basis := (mech.global_basis.inverse() * rig.torso.global_basis).orthonormalized()
		if last.has("T"):
			var turn := rad_to_deg((last["T"] as Basis).get_rotation_quaternion().angle_to(torso_basis.get_rotation_quaternion()))
			if ended >= 0:
				worst["T"] = maxf(worst.get("T", 0.0), turn)
			if turn > 3.0:
				print("f%d torso turn %.1f deg (melee playing %s, fading %s)" % [frame, turn, melee.is_playing, melee.is_fading()])
		last["T"] = torso_basis
		for side in ["R", "L"]:
			var place := to_torso * (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side)).origin)
			if last.has(side):
				var step: float = place.distance_to(last[side])
				if ended >= 0:
					worst[side] = maxf(worst[side], step)
				if step > limit:
					print("f%d %s hand step %.3f m (melee playing %s, fading %s)" % [frame, side, step, melee.is_playing, melee.is_fading()])
			last[side] = place
			if OS.has_environment("TRACE") and side == "R" and ended >= 0 and frame < ended + 45:
				var hips := mech.find_child("HipTurn", true, false) as SkeletalHipTurn
				print("f%d R %s weight %.2f hip %.0f" % [frame, place, melee._weight(), rad_to_deg(hips.hip_yaw) if hips else 0.0])
	print("after the swing: largest hand step R %.3f m, L %.3f m per frame, torso turn %.1f deg" % [worst.R, worst.L, worst.get("T", 0.0)])
	quit()
