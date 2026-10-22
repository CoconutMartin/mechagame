extends SceneTree
## Dodge to walk blend measure (user report 2026-10-22). Holds a move key through a dodge and logs, per
## physics frame, the biggest bone rotation change (degrees, over all bones of the skeleton) and the
## bone that did it, with the dodge state. A pop shows as a spike after the release frame.
## DODGE_KEY=move_forward|move_left|move_right|move_back (default move_forward).
## Run: godot --headless --path . --script res://tools/godot/measure_dodge_blend.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var action := OS.get_environment("DODGE_KEY") if OS.get_environment("DODGE_KEY") != "" else "move_forward"
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	switcher.rebuild(switcher.current_loadout.duplicate() as Loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var animation := player.dodge.animation
	Input.action_press(action)
	await _frames(30)
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _frames(5)
	Input.action_press("jump")
	var previous: Array[Quaternion] = []
	var released := -1
	for frame in 150:
		await _frames(1)
		await process_frame
		if frame == 2:
			Input.action_release("jump")
		var worst := 0.0
		var worst_bone := ""
		for bone in skeleton.get_bone_count():
			var rotation := skeleton.get_bone_pose_rotation(bone)
			if previous.size() == skeleton.get_bone_count():
				var angle := rad_to_deg(previous[bone].angle_to(rotation))
				if angle > worst:
					worst = angle
					worst_bone = skeleton.get_bone_name(bone)
			if previous.size() < skeleton.get_bone_count():
				previous.append(rotation)
			else:
				previous[bone] = rotation
		if released < 0 and player.dodge.is_dodging == false and frame > 5:
			released = frame
		print("%3d  speed %5.2f  playing %d  max bone change %5.2f deg (%s)%s" % [frame, player.get_horizontal_speed(),
				1 if animation.is_playing else 0, worst, worst_bone, "  <- released" if frame == released else ""])
	Input.action_release(action)
	quit()
