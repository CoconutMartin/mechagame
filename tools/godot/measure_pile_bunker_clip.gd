extends SceneTree
## Pile Bunker punch clip probe (2026-10-29): plays the clip with no target (SIDE=R or L) and prints, per clip time,
## how far the nose is in front of the mech (m, along the aim, from the mech center) and its height, so the
## strike window (data/melee/pile_bunker_punch_r/l.tres) can sit where the stakes reach forward. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_pile_bunker_clip.gd

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
	var side := OS.get_environment("SIDE") if OS.has_environment("SIDE") else "R"
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/pile_bunker.tres") if side == "R" else null
	loadout.weapon_left = load("res://data/weapons/pile_bunker.tres") if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var weapons := mech.get_node("WeaponController") as WeaponController
	var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
	var melee := mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	var clip := bunker.punch_clip_left if side == "L" else bunker.punch_clip_right
	if OS.has_environment("CLIP"):
		clip = load(OS.get_environment("CLIP")) as MeleeAttack
	if OS.has_environment("CLIP"):
		melee.play_external(clip, bunker)
	else:
		# The real attack: power up, release, charge (no target: along the aim), then the clip.
		var button := "use_right_arm" if side == "R" else "use_left_arm"
		Input.action_press(button)
		await _frames(40)
		Input.action_release(button)
		while bunker.state != PileBunkerWeapon.State.CLIP:
			await _frames(1)
	var forward := Basis(Vector3.UP, mech.get_aim_yaw()) * Vector3.FORWARD
	var best := -INF
	var best_t := 0.0
	while melee.is_playing:
		await _frames(1)
		var t := melee.external_time(bunker)
		var nose := bunker._nose.global_position - mech.global_position
		var ahead := nose.dot(forward)
		var dir := (-bunker._nose.global_basis.z).normalized()
		if ahead > best:
			best = ahead
			best_t = t
		var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
		await skeleton.skeleton_updated
		var hand_r := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_R")).origin - mech.global_position
		var hand_l := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_L")).origin - mech.global_position
		if absf(t - 1.0) < 0.009:
			var b := Basis(Vector3.UP, mech.get_aim_yaw()).inverse()
			var g := func(n: String) -> Vector3: return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(n)).origin
			print("   at 1.0 s (mech frame, -Z forward): upper arm %s, forearm %s, torso up %s, pelvis h %.2f, shoulder h %.2f" % [
					(b * (g.call("forearm_R") - g.call("upper_arm_R"))).normalized().snappedf(0.01),
					(b * (g.call("hand_R") - g.call("forearm_R"))).normalized().snappedf(0.01),
					(b * (g.call("neck") - g.call("torso"))).normalized().snappedf(0.01) if skeleton.find_bone("neck") >= 0 else Vector3.ZERO,
					(g.call("pelvis") - mech.global_position).y, (g.call("upper_arm_R") - mech.global_position).y])
		if int(t * 60.0) % 6 == 0:
			print("   hands ahead R %.2f (h %.2f)  L %.2f (h %.2f)" % [hand_r.dot(forward), hand_r.y, hand_l.dot(forward), hand_l.y])
		if int(t * 60.0) % 3 == 0:
			print("t %.2f nose ahead %.2f m, height %.2f m, stakes point %.2f forward, %.2f up" % [t, ahead, nose.y, dir.dot(forward), dir.y])
	print("%s farthest nose %.2f m at t %.2f" % [side, best, best_t])
	quit()
