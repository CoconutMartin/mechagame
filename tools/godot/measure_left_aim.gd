extends SceneTree
## Left hand reach on a two-hand rifle while aiming (user request 2026-11-01: "Move the left hand a bit more forward
## when holding the rifle while aiming"). Holds WEAPON (data/weapons file name, default beam_rifle_4), moves the
## GripLeftAim and GripSocketLeftAim markers by AIM_DZ meters along the rifle (negative = forward; default 0) at run
## time, aims (RMB) for 2 s, then prints: the aim amount, the gap from the left hand bone to its target, and the angle
## between the rifle's bore and the aim (a large angle = the arm rig drags the rifle).
##   WEAPON=beam_rifle_4 AIM_DZ=-0.5 godot --headless --path . --script res://tools/godot/measure_left_aim.gd

var _gap: float = -1.0


func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var weapon_name := OS.get_environment("WEAPON") if OS.has_environment("WEAPON") else "beam_rifle_4"
	loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon_name) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var mech := switcher.mech
	var weapons := mech.find_child("WeaponController", true, false) as WeaponController
	var rifle := weapons.right_weapon
	var dz := float(OS.get_environment("AIM_DZ")) if OS.has_environment("AIM_DZ") else 0.0
	for marker in ["GripLeftAim", "GripSocketLeftAim"]:
		(rifle.get_node(marker) as Node3D).position.z += dz
	Input.action_press("aim")
	await _frames(120)
	var skeleton := mech.find_child("Skeleton3D", true, false) as Skeleton3D
	var target := weapons.weapon_pose.left_grip_target
	var sample := func() -> void:
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_L")).origin
		_gap = hand.distance_to(target.global_position) if target != null else -1.0
	skeleton.skeleton_updated.connect(sample)
	await _frames(3)
	skeleton.skeleton_updated.disconnect(sample)
	var muzzle := rifle.get_node("Muzzle") as Node3D
	var bore := -rifle.global_basis.z
	var to_aim := (weapons.mech_aim.aim_point - muzzle.global_position).normalized()
	print("AIM_DZ %.2f: aim %.2f, left grip z %.3f, left hand gap %.3f m, bore vs aim %.1f deg" % [dz,
			weapons.weapon_pose.aim_amount, (rifle.get_node("GripLeftAim") as Node3D).position.z, _gap,
			rad_to_deg(bore.angle_to(to_aim))])
	Input.action_release("aim")
	quit()
