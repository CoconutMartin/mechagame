extends SceneTree
## In-game screenshots of a gun shot (user requests 2026-11-01). Holds WEAPON (data/weapons file name, default
## shotgun_2) in the right hand and takes <OUT>/rest.png (a camera beside the gun), then presses ACTION (default
## use_right_arm) and takes <OUT>/open.png beside the gun the frame the shot leaves, and <OUT>/flight.png with the game
## camera FLIGHT_FRAMES physics frames later (default 6).
##   OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --script res://tools/godot/screenshot_shot.gd


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("wrote ", file)


func _run() -> void:
	var out := _env("OUT", "/tmp")
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/%s.tres" % _env("WEAPON", "shotgun_2")) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var weapons := switcher.mech.find_child("WeaponController", true, false) as WeaponController
	var gun := weapons.right_weapon
	var game_camera := root.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 45.0
	current_scene.add_child(camera)
	_place(camera, gun)
	await _frames(2)
	await _shot(out + "/rest.png")
	game_camera.make_current()
	var fired := [false]
	gun.fired.connect(func() -> void: fired[0] = true)
	Input.action_press(_env("ACTION", "use_right_arm"))
	for i in 240:
		if fired[0]:
			break
		await physics_frame
	Input.action_release(_env("ACTION", "use_right_arm"))
	await physics_frame
	await physics_frame
	await physics_frame
	_place(camera, gun)
	await _shot(out + "/open.png")
	game_camera.make_current()
	for i in int(_env("FLIGHT_FRAMES", "6")):
		await physics_frame
	await _shot(out + "/flight.png")
	quit()


## Beside the gun's front, a little above, looking at the emitter end.
func _place(camera: Camera3D, gun: Node3D) -> void:
	var xf := gun.global_transform
	camera.look_at_from_position(xf * Vector3(3.2, 1.6, -6.2), xf * Vector3(0.0, 0.0, -4.0), Vector3.UP)
	camera.make_current()
