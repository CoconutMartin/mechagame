extends SceneTree
## In-game screenshots of a charged weapon through the player's own camera (user request 2026-11-01: "Show in game
## screen shot"). Holds WEAPON (data/weapons file name, default beam_rifle_4) in the right hand, holds LMB for CHARGE_S
## seconds (default 2.0) and takes <OUT>/charge.png with a camera above and beside the rifle (the light bars show),
## releases and takes <OUT>/shot.png with the game camera right after the shot leaves, and <OUT>/cool.png 1.5 s
## after the shot with the camera above the rifle again.
##   OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --script res://tools/godot/screenshot_charge.gd


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


## Game seconds (physics frames): a slow virtual display renders fewer frames per real second.
func _seconds(s: float) -> void:
	for i in roundi(s * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(file: String, wait: int = 2) -> void:
	await _frames(wait)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("wrote ", file)
	var shots := current_scene.find_children("ParticleShot*", "", true, false)
	var camera := root.get_viewport().get_camera_3d()
	for shot in shots:
		print("  shot at %.1f m from the camera, on screen %s" % [(shot as Node3D).global_position.distance_to(camera.global_position),
				not camera.is_position_behind((shot as Node3D).global_position)])


func _run() -> void:
	var out := _env("OUT", "/tmp")
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/%s.tres" % _env("WEAPON", "beam_rifle_4")) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var weapons := mech.find_child("WeaponController", true, false) as WeaponController
	var rifle := weapons.right_weapon
	var game_camera := root.get_viewport().get_camera_3d()
	var side_camera := Camera3D.new()
	side_camera.fov = 50.0
	current_scene.add_child(side_camera)
	var fired := [false]
	rifle.fired.connect(func() -> void: fired[0] = true)
	await _frames(30)
	Input.action_press("use_left_arm")
	await _seconds(float(_env("CHARGE_S", "2.0")))
	_aim_side_camera(side_camera, rifle)
	if rifle.get(&"charge") != null:
		print("  charge %.2f" % float(rifle.get(&"charge")))
		for bar in ["Model/LightBar2", "Model/LightBar1", "Model/LightBar0"]:
			var mesh := rifle.get_node_or_null(bar) as MeshInstance3D
			if mesh != null and mesh.material_override is StandardMaterial3D:
				var m := mesh.material_override as StandardMaterial3D
				print("  %s glow %.2f albedo %s override %s surface %s skin %s" % [bar, m.emission_energy_multiplier, m.albedo_color,
						mesh.material_override, mesh.get_surface_override_material(0), mesh.get_active_material(0)])
	await _shot(out + "/charge.png")
	game_camera.make_current()
	Input.action_release("use_left_arm")
	for i in 180:
		if fired[0]:
			break
		await physics_frame
	await _shot(out + "/shot.png", 0)
	await _seconds(1.5)
	_aim_side_camera(side_camera, rifle)
	await _shot(out + "/cool.png")
	quit()


## Above the rifle's left side, a little behind its middle, looking at the barrel section.
func _aim_side_camera(camera: Camera3D, rifle: Node3D) -> void:
	var xf := rifle.global_transform
	var look := xf * Vector3(0.0, 0.3, -4.5)
	camera.look_at_from_position(xf * Vector3(5.5, 6.0, -1.0), look, Vector3.UP)
	camera.make_current()
