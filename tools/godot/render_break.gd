extends SceneTree
## Part break render tool (user report 2026-10-16: a broken arm left its hand floating). Breaks the
## parts in BREAK_PARTS one after another (default "Arm R,Torso L") on the player and saves a picture
## from the front every BREAK_STEP physics frames.
## Render (frames in BREAK_OUT, default user://break_renders/):
##   BREAK_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_break.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("BREAK_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://break_renders")
	DirAccess.make_dir_recursive_absolute(out)
	var parts := (OS.get_environment("BREAK_PARTS") if OS.get_environment("BREAK_PARTS") != "" else "Arm R,Torso L").split(",")
	var step := int(OS.get_environment("BREAK_STEP")) if OS.get_environment("BREAK_STEP") != "" else 10
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
	var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
	var camera := Camera3D.new()
	camera.fov = 40.0
	map.add_child(camera)
	camera.current = true
	var shot := 0
	for part in parts:
		# Small hits, so the mech is not knocked down.
		var key := part.strip_edges()
		while player.health.is_part_alive(key):
			player.health.damage(key, 40.0)
			await _frames(1)
		var hands := player.find_children("MechHand*", "", true, false)
		print("%s broken: hands on the mech %s" % [key, hands.map(func(h: Node) -> String: return h.name)])
		for debris in map.find_children("*", "Debris", false, false):
			for hand in debris.find_children("*", "MechHand", true, false):
				print("  hand in debris %s at %s" % [hand.name, (hand as Node3D).global_position])
		for i in 6:
			await _frames(step)
			var center := player.global_position + Vector3.UP * 6.0
			camera.look_at_from_position(center + forward * 26.0 + Vector3.UP * 2.0, center)
			await process_frame
			map.get_viewport().get_texture().get_image().save_png("%s/break_%02d.png" % [out, shot])
			print("shot %d after %s" % [shot, part])
			shot += 1
	quit()
