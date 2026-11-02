extends SceneTree
## Pictures of the back pack boosters (user request 2026-11-02: boost wind like a gust, realistic booster fire,
## nozzle heat, petals closing in the jump charge). The mech carries PACK (back pack file name, default
## backpack_quad). Writes into OUT (default /tmp): charge.png (holding jump, the petals closed down, camera behind),
## launch.png (just after the release, the camera follows), boost.png (boosting, 3/4 view from behind), boost_side.png
## (from the side), boost_back.png (from behind). STAGES (default "charge,launch,boost"; add "rest" for rest.png before the charge) picks the pictures, ANGLE,
## DIST, HEIGHT, LOOK move the 3/4 camera, JUMP_FRAMES sets the hold time of the charge picture (default 75 frames).
## The render loop is off between the pictures to save time. Run with a fixed frame rate:
##   PACK=backpack_boost OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 \
##     --rendering-driver opengl3 --resolution 1280x720 --script res://tools/godot/render_booster_fire.gd

var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


## Game frames without drawing.
func _frames(count: int) -> void:
	RenderingServer.render_loop_enabled = false
	for i in count:
		await physics_frame
		await process_frame


func _shot(file: String) -> void:
	RenderingServer.render_loop_enabled = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("wrote ", file)
	RenderingServer.render_loop_enabled = false


## Puts the camera behind the mech (+Z is back) at an angle (degrees round the mech, 0 = straight behind).
func _aim(mech: Mech, angle_deg: float, distance: float, height: float, look_height: float) -> void:
	var back := mech.global_basis.z.normalized()
	var side := Basis(Vector3.UP, deg_to_rad(angle_deg)) * back
	_camera.global_position = mech.global_position + side * distance + Vector3.UP * height
	_camera.look_at(mech.global_position + Vector3.UP * look_height + back * 1.5, Vector3.UP)
	_camera.make_current()


func _run() -> void:
	var out := _env("OUT", "/tmp")
	var stages := _env("STAGES", "charge,launch,boost").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = load("res://data/parts/backpacks/%s.tres" % _env("PACK", "backpack_quad")) as BackPackPart
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	_camera = Camera3D.new()
	_camera.fov = float(_env("FOV", "55"))
	current_scene.add_child(_camera)
	if "charge" in stages or "launch" in stages:
		var charge_angle := float(_env("CHARGE_ANGLE", "25"))
		var charge_distance := float(_env("CHARGE_DIST", "6"))
		if "rest" in stages:
			_aim(mech, charge_angle, charge_distance, 8.2, 8.0)
			await _frames(2)
			await _shot(out + "/rest.png")
		Input.action_press("jump")
		await _frames(int(_env("JUMP_FRAMES", "75")))
		_aim(mech, charge_angle, charge_distance, 8.2, 8.0)
		await _frames(1)
		if "charge" in stages:
			await _shot(out + "/charge.png")
		Input.action_release("jump")
		await _frames(int(_env("LAUNCH_FRAMES", "10")))
		_aim(mech, float(_env("LAUNCH_ANGLE", "30")), 11.0, 6.0, 6.0)
		if "launch" in stages:
			await _shot(out + "/launch.png")
		for i in 400:
			await _frames(1)
			if mech.is_on_floor() and i > 20:
				break
		await _frames(60)
	if "boost" in stages:
		Input.action_press("boost")
		Input.action_press("move_forward")
		await _frames(int(_env("BOOST_FRAMES", "100")))
		_aim(mech, float(_env("ANGLE", "35")), float(_env("DIST", "12")), float(_env("HEIGHT", "6")), float(_env("LOOK", "6")))
		await _shot(out + "/boost.png")
		_aim(mech, 90.0, 13.0, 5.0, 6.0)
		await _shot(out + "/boost_side.png")
		_aim(mech, 0.0, 10.0, 7.0, 6.0)
		await _shot(out + "/boost_back.png")
		Input.action_release("boost")
		Input.action_release("move_forward")
	quit()
