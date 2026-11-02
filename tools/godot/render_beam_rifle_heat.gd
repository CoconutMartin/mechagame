extends SceneTree
## Pictures of Beam Rifle 2's barrel coil at heat 0, 35, 70 and 100 (user request 2026-11-02: the coil turns bright
## red at max heat). The rifle alone, a camera close to the coil, in front of a grey background.
## RENDER_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://tools/godot/render_beam_rifle_heat.gd
## Writes <RENDER_OUT>/beam_rifle_2_heat_<n>.png and beam_rifle_2_heat_levels.png (the four side by side, 2 x 2).

const HEATS: Array[float] = [0.0, 35.0, 70.0, 100.0]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("RENDER_OUT") if OS.has_environment("RENDER_OUT") else "/tmp"
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
	var rifle := (load("res://scenes/weapons/beam_rifle_2.tscn") as PackedScene).instantiate() as BeamRepeaterWeapon
	rifle.data = load("res://data/weapons/beam_rifle_2.tres") as WeaponData
	world.add_child(rifle)
	rifle.set_physics_process(false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(OS.get_environment("RENDER_SIZE")) if OS.has_environment("RENDER_SIZE") else 2.2
	var mid := float(OS.get_environment("RENDER_Z")) if OS.has_environment("RENDER_Z") else -3.5
	world.add_child(camera)
	camera.look_at_from_position(Vector3(6.0, 1.2, mid), Vector3(0, 0, mid), Vector3.UP)
	var images: Array[Image] = []
	for heat in HEATS:
		rifle.heat = heat
		rifle._show_heat()
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(out + "/beam_rifle_2_heat_%d.png" % roundi(heat))
		images.append(image)
		print("wrote heat ", heat)
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	for i in images.size():
		var small := images[i].duplicate() as Image
		small.convert(Image.FORMAT_RGB8)
		small.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
	sheet.save_png(out + "/beam_rifle_2_heat_levels.png")
	quit()
