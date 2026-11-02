extends SceneTree
## Renders the Ctrl kneel of the player (user report 2026-11-02): the mech stands, kneels (Ctrl), stands up again.
## Pictures from the side (default), front and the game camera. Environment:
##   KNEEL_OUT   directory for the pictures (default user://kneel_renders)
##   KNEEL_VIEW  side (default), front, front_left, game
##   KNEEL_WEAPON  right weapon file in data/weapons (default: the map loadout); "-" = empty
##   KNEEL_DIST camera distance in m (default 26)
##   KNEEL_AIM=1 holds the aim button while kneeling
##   KNEEL_TIMES comma list of seconds after the Ctrl press (default 0,0.4,0.8,1.3,2)
## Render:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --fixed-fps 60 --script res://tools/godot/render_kneel.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("KNEEL_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://kneel_renders")
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
	var weapon := OS.get_environment("KNEEL_WEAPON")
	if weapon != "":
		loadout.weapon_right = null if weapon == "-" else load("res://data/weapons/%s.tres" % weapon) as WeaponData
		loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var view := OS.get_environment("KNEEL_VIEW")
	var camera := Camera3D.new()
	camera.fov = 32.0
	map.add_child(camera)
	camera.current = view != "game"
	for layer in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	if view == "front":
		side = forward
	elif view == "front_left":
		side = (forward - forward.cross(Vector3.UP)).normalized()
	var times: PackedFloat64Array = PackedFloat64Array()
	for item in (OS.get_environment("KNEEL_TIMES") if OS.get_environment("KNEEL_TIMES") != "" else "0,0.4,0.8,1.3,2").split(",", false):
		times.append(float(item))
	if OS.get_environment("KNEEL_AIM") == "1":
		Input.action_press("aim")
	await _frames(20)
	Input.action_press("crouch")
	await _frames(2)
	Input.action_release("crouch")
	var frame := 2
	var index := 0
	while index < times.size():
		var middle := player.global_position + Vector3.UP * 4.8
		camera.global_position = middle + side * (float(OS.get_environment("KNEEL_DIST")) if OS.get_environment("KNEEL_DIST") != "" else 26.0)
		camera.look_at(middle, Vector3.UP)
		if frame / 60.0 >= times[index]:
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			image.save_png("%s/kneel_%s_%03d.png" % [out, view if view != "" else "side", int(times[index] * 100)])
			print("shot t=%.2f amount %.2f" % [times[index], player.kneel.amount])
			index += 1
		await _frames(1)
		frame += 1
	Input.action_release("aim")
	quit()
