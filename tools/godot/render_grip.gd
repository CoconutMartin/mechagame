extends SceneTree
## One-hand grip render and check (user report 2026-10-16: the hand is disconnected when it holds a
## gun with one hand). Gives the player GRIP_RIGHT / GRIP_LEFT (weapon file names, "" = none; defaults
## smg / smg), holds the GRIP_ACTIONS input actions, waits GRIP_FRAMES frames (default 90), records
## the largest wrist gap over 60 frames, then logs per hand the gap from the forearm's wrist to the jointed hand's wrist and from the fist to
## the gun's grip socket, and saves front, side and close pictures (grip_*.png in GRIP_OUT).
##   GRIP_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_grip.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	var out := _env("GRIP_OUT", ProjectSettings.globalize_path("user://grip_renders"))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var right := _env("GRIP_RIGHT", "smg")
	var left := _env("GRIP_LEFT", "smg")
	loadout.weapon_right = load("res://data/weapons/%s.tres" % right) as WeaponData if right != "" else null
	loadout.weapon_left = load("res://data/weapons/%s.tres" % left) as WeaponData if left != "" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(2)
	# GRIP_NOREACH=1: the hand's reach correction off (MechHandControl.max_reach_offset 0), to compare.
	if _env("GRIP_NOREACH", "") == "1":
		(switcher.mech.find_child("MechHandControl", true, false) as MechHandControl).max_reach_offset = 0.0
	await _frames(28)
	# GRIP_NOCLAMP=1: WeaponPose.max_reach_share 1.0 (the reach rule of 2026-10-16 off), to compare.
	if _env("GRIP_NOCLAMP", "") == "1":
		for pose in switcher.mech.find_children("*", "WeaponPose", true, false):
			(pose as WeaponPose).max_reach_share = 1.0
	# GRIP_ACTIONS: input actions held during the test (comma list, e.g. "move_forward,aim,use_right_arm").
	var actions := _env("GRIP_ACTIONS", "").split(",", false)
	for action in actions:
		Input.action_press(action)
	await _frames(int(_env("GRIP_FRAMES", "90")))
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var lines: Array = []
	var worst := {"R": 0.0, "L": 0.0}
	var sample := func() -> void:
		for line in _measure(switcher.mech, switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D):
			var side: String = line.substr(0, 1)
			worst[side] = maxf(worst[side], float(line.get_slice("wrist gap ", 1).get_slice(" m", 0)))
	var skeleton_now := switcher.mech.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton_now.skeleton_updated.connect(sample)
	await _frames(60)
	skeleton_now.skeleton_updated.disconnect(sample)
	# Bone poses with the skeleton modifiers applied exist only during skeleton_updated (after it the
	# skeleton shows the plain animation pose again), so the check runs there, after MechHandControl.
	var measure := func() -> void:
		if lines.is_empty():
			lines.append_array(_measure(player, skeleton))
	skeleton.skeleton_updated.connect(measure)
	await _frames(3)
	skeleton.skeleton_updated.disconnect(measure)
	for line in lines:
		print(line)
	print("largest wrist gap over 60 frames: R %.3f m, L %.3f m" % [worst["R"], worst["L"]])
	for action in actions:
		Input.action_release(action)
	var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
	var side_axis := forward.cross(Vector3.UP)
	var camera := Camera3D.new()
	camera.fov = 30.0
	map.add_child(camera)
	camera.current = true
	var chest := player.global_position + Vector3.UP * 5.5
	var views := {"front": chest + forward * 22.0 + Vector3.UP * 1.0, "right": chest + side_axis * 20.0,
			"left": chest - side_axis * 20.0, "top": chest + forward * 10.0 + Vector3.UP * 12.0}
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	var targets := {}
	for name: String in views:
		targets[name] = chest
	for side in ["R", "L"]:
		var hand: Node3D = control.hand_right if side == "R" else control.hand_left
		if hand != null:
			var out_dir := side_axis if side == "R" else -side_axis
			views["close_%s_front" % side] = hand.global_position + forward * 7.0 + out_dir * 1.5 + Vector3.UP * 0.5
			views["close_%s_side" % side] = hand.global_position + out_dir * 7.0 + Vector3.UP * 0.5
			targets["close_%s_front" % side] = hand.global_position
			targets["close_%s_side" % side] = hand.global_position
	for name: String in views:
		camera.look_at_from_position(views[name], targets[name])
		await _frames(2)
		map.get_viewport().get_texture().get_image().save_png("%s/grip_%s.png" % [out, name])
	quit()


## Per hand: the gap from the forearm's wrist (hand bone) to the jointed hand's wrist, and from the
## fist to the gun's grip socket.
func _measure(player: Mech, skeleton: Skeleton3D) -> PackedStringArray:
	var lines: PackedStringArray = []
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	var weapons := player.get_node("WeaponController") as WeaponController
	for side in ["R", "L"]:
		var hand := control.hand_right if side == "R" else control.hand_left
		if hand == null:
			continue
		var wrist := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))).origin
		var text := "%s hand: wrist gap %.3f m" % [side, hand.global_position.distance_to(wrist)]
		var gun: Node3D = weapons.right_weapon if side == "R" else weapons.left_weapon
		var socket := gun.get_node_or_null("GripSocketRight") as Node3D if gun != null and is_instance_valid(gun) else null
		if socket != null:
			var hollow := MechHandControl.RIGHT_HOLLOW if side == "R" else MechHandControl.LEFT_HOLLOW
			text += ", fist to grip %.3f m" % (hand.global_transform * hollow).distance_to(socket.global_position)
		# Torso space (the weapon frame: -Z forward, +X right): shoulder, elbow, wrist, grip, muzzle way.
		var torso := weapons.torso.global_transform.affine_inverse()
		var bone := func(name: String) -> Vector3:
			return torso * (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name + "_" + side))).origin
		text += "\n    torso space: shoulder %s elbow %s wrist %s" % [bone.call("upper_arm"), bone.call("forearm"), bone.call("hand")]
		if gun != null and is_instance_valid(gun):
			text += " grip %s muzzle way %s" % [torso * socket.global_position if socket != null else Vector3.ZERO,
					(weapons.torso.global_basis.inverse() * -gun.global_basis.z).normalized()]
		lines.append(text)
	return lines
