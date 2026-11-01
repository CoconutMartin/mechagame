extends SceneTree
## Pictures of a beam rifle scene at rest and with its glow meshes lit (Beam Rifle 3 rings and side rails, the
## prong tips; Beam Rifle 2 rail bores). No mech: the rifle alone in front of a grey background.
## RENDER_OUT=/tmp/x RIFLE=res://scenes/weapons/beam_rifle_3.tscn xvfb-run -a -s "-screen 0 1280x720x24" \
##   godot --path . --rendering-driver opengl3 --script res://tools/godot/render_beam_rifle_glow.gd
## Writes <RENDER_OUT>/<name>_rest.png and <name>_lit.png.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("RENDER_OUT") if OS.has_environment("RENDER_OUT") else "/tmp"
	var path := OS.get_environment("RIFLE") if OS.has_environment("RIFLE") else "res://scenes/weapons/beam_rifle_3.tscn"
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.36, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment.glow_enabled = true
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -60, 0)
	world.add_child(sun)
	# The weapon scripts load cleanly only after WeaponController (GunWeapon subclasses loaded first meet the
	# GunWeapon -> MechWeapon -> WeaponController -> ForearmGunWeapon cycle; in the game the mech loads it first).
	load("res://scripts/weapons/weapon_controller.gd")
	var rifle := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(rifle)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	world.add_child(camera)
	camera.look_at_from_position(Vector3(6.0, 1.2, -3.2), Vector3(0, 0, -3.2), Vector3.UP)
	var name := path.get_file().get_basename()
	await _shot(out + "/%s_rest.png" % name)
	# Light every glow mesh as the weapon script does at full charge or at a shot.
	var energy: float = rifle.get(&"ring_energy") if rifle.get(&"ring_energy") != null else 4.0
	for mesh in rifle.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh as MeshInstance3D).material_override as StandardMaterial3D
		if material != null and material.emission_enabled:
			material.emission_energy_multiplier = energy
	await _shot(out + "/%s_lit.png" % name)
	quit()


func _shot(file: String) -> void:
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(file)
	print("wrote ", file)
