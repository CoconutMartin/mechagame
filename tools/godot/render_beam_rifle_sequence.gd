extends SceneTree
## Pictures of Beam Rifle 3 during its charge (user request 2026-11-02: the rings glow one after another, back to
## front, then the tip) and after the shot (the glow fades over 1 s). The rifle alone, an orthogonal side camera.
## The weapon is driven by hand: charge_left is set to a part of the charge, then _show() draws the glow.
## RENDER_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://tools/godot/render_beam_rifle_sequence.gd
## Writes <RENDER_OUT>/beam_rifle_3_charge_seq.png: 6 panels (charge 10, 25, 45, 65, 85 and 100 %), and
## beam_rifle_3_fade_seq.png: 6 panels (0, 0.2, 0.4, 0.6, 0.8 and 1.0 s after the shot).

const CHARGES: Array[float] = [0.10, 0.25, 0.45, 0.65, 0.85, 0.999]
const FADES: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]


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
	var rifle := (load("res://scenes/weapons/beam_rifle_3.tscn") as PackedScene).instantiate() as BeamCannonWeapon
	rifle.data = load("res://data/weapons/beam_rifle_3.tres") as WeaponData
	world.add_child(rifle)
	rifle.set_physics_process(false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(OS.get_environment("RENDER_SIZE")) if OS.has_environment("RENDER_SIZE") else 3.0
	var mid := float(OS.get_environment("RENDER_Z")) if OS.has_environment("RENDER_Z") else -4.5
	world.add_child(camera)
	camera.look_at_from_position(Vector3(6.0, 1.0, mid), Vector3(0, 0, mid), Vector3.UP)
	var charge_images: Array[Image] = []
	for part in CHARGES:
		rifle.charge_left = rifle.charge_time * (1.0 - part)
		rifle._show()
		charge_images.append(await _grab())
	_sheet(charge_images).save_png(out + "/beam_rifle_3_charge_seq.png")
	print("wrote charge sequence")
	var fade_images: Array[Image] = []
	rifle.charge_left = -1.0
	for seconds in FADES:
		rifle._since_shot = seconds
		rifle._show()
		fade_images.append(await _grab())
	_sheet(fade_images).save_png(out + "/beam_rifle_3_fade_seq.png")
	print("wrote fade sequence")
	quit()


func _grab() -> Image:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## Panels in a 2 x 3 sheet (each 640 x 240 from the 1280 x 720 picture, cropped to the middle band).
func _sheet(images: Array[Image]) -> Image:
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	for i in images.size():
		var panel := images[i].duplicate() as Image
		panel.convert(Image.FORMAT_RGB8)
		panel.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		# The rifle fills the middle of the picture: keep the middle 240 rows.
		sheet.blit_rect(panel, Rect2i(0, 60, 640, 240), Vector2i((i % 2) * 640, (i / 2) * 240))
	return sheet
