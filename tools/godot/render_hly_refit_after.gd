extends SceneTree
## Before and after pictures of the Haliya HLY-101 refit onto the SGG-101 skeleton (user decision 2026-11-08): HLY before (the
## light-rig export in models/mechs/haliya/source_light_rig), HLY after (models/mechs/haliya) and SGG, side by side, plus
## close-ups of the new waist, neck and ankle pieces. Needs a renderer, so xvfb on a server:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tools/godot/render_hly_refit_after.gd
## Env: POSE = "rest" (default), or a clip and time ("Haliya_Stand", "Walk:0.5"; each mech plays it from its own rig file, HLY
## before from its old rig); OUT_DIR (default docs); NAME (file prefix, default hly_refit_after); ONLY = "row" or "closeup".
## Writes <NAME>_front.png, _side.png, _back34.png and <NAME>_closeup_waist.png, _neck.png, _ankle.png.

const Refit := preload("res://tools/godot/preview_refit_parts.gd")
const Parts := preload("res://tools/godot/refit_haliya_parts.gd")
const PART_NAMES: Array[String] = ["head", "core", "arm_l", "arm_r", "legs"]
const SOURCE_DIR := "res://models/mechs/haliya/source_light_rig/"
const HLY_RIG := "res://models/mechs/haliya/haliya_rig.glb"
const SGG_RIG := "res://models/mechs/sgg/sgg_rig.glb"
## Camera view height (m) of the three-mech pictures (orthographic).
const VIEW_HEIGHT := 13.2
## Distance (m) between the mechs in the row.
const ROW_SPACING := 8.0
## View yaw (degrees) of the mechs for front, side and the 3/4 back picture.
const VIEWS: Dictionary = {"front": 0.0, "side": 90.0, "back34": 145.0}
const ROW_NAMES: Array[String] = ["HLY before", "HLY after", "SGG"]

var _camera: Camera3D
var _label: Label
var _mechs: Array[Node3D] = []
## Mech -> its Skeleton3D, for the close-up places.
var _skeletons: Array[Skeleton3D] = []


func _initialize() -> void:
	var out_dir := OS.get_environment("OUT_DIR") if OS.has_environment("OUT_DIR") else ProjectSettings.globalize_path("res://docs")
	var prefix := OS.get_environment("NAME") if OS.has_environment("NAME") else "hly_refit_after"
	var pose := OS.get_environment("POSE") if OS.has_environment("POSE") else "rest"
	var only := OS.get_environment("ONLY")
	if DisplayServer.get_name() == "headless":
		print("needs a renderer: run with xvfb-run and --rendering-driver opengl3")
		quit(1)
		return
	_build_stage()
	_add_mech(Parts.load_glb(SOURCE_DIR + "haliya_rig.glb"), _source_parts(), 0)
	_add_mech((load(HLY_RIG) as PackedScene).instantiate(), _game_parts("haliya"), 1)
	_add_mech((load(SGG_RIG) as PackedScene).instantiate(), _game_parts("sgg"), 2)
	for holder in _mechs:
		_pose(holder, pose)
	await process_frame
	await process_frame
	if only != "closeup":
		for view: String in VIEWS:
			_set_view(VIEWS[view])
			_camera.size = VIEW_HEIGHT
			_camera.position = Vector3(0, VIEW_HEIGHT * 0.5 - 1.0, 40)
			_camera.rotation_degrees = Vector3.ZERO
			_set_row_labels(true)
			_label.text = "View: %s   pose: %s   (lines every 2 m, thick line at 10 m)" % [view, pose]
			await _snap("%s/%s_%s.png" % [out_dir, prefix, view])
	if only != "row":
		await _render_closeups(out_dir, prefix)
	quit()


func _source_parts() -> Array:
	var scenes := []
	for part in PART_NAMES:
		scenes.append(Parts.load_glb(SOURCE_DIR + "haliya_%s.glb" % part))
	return scenes


func _game_parts(mech: String) -> Array:
	var scenes := []
	for part in PART_NAMES:
		scenes.append((load("res://models/mechs/%s/%s_%s.glb" % [mech, mech, part]) as PackedScene).instantiate())
	return scenes


## Puts the part meshes on the rig's skeleton (the rig file keeps its AnimationPlayer) and places the mech in the row.
func _add_mech(rig: Node, parts: Array, index: int) -> void:
	var skeleton: Skeleton3D
	for node in rig.find_children("*", "Skeleton3D", true, false):
		skeleton = node
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			skeleton.remove_child(child)
			child.free()
	for scene: Node in parts:
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi as MeshInstance3D
			mesh.get_parent().remove_child(mesh)
			mesh.owner = null
			skeleton.add_child(mesh)
			mesh.skeleton = NodePath("..")
		scene.free()
	var holder := Node3D.new()
	holder.name = ROW_NAMES[index].replace(" ", "_")
	holder.add_child(rig)
	holder.position = Vector3((index - 1) * ROW_SPACING, 0, 0)
	root.add_child(holder)
	_mechs.append(holder)
	_skeletons.append(skeleton)


## Rest, or a clip at a time from the mech's own AnimationPlayer (a clip it does not have leaves it at rest).
func _pose(holder: Node3D, pose: String) -> void:
	if pose == "rest":
		return
	var clip := pose.get_slice(":", 0)
	var time := float(pose.get_slice(":", 1)) if pose.contains(":") else 0.0
	var player := holder.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or not player.has_animation(clip):
		print("%s: no clip %s, rest" % [holder.name, clip])
		return
	player.play(clip)
	player.seek(time, true)
	player.pause()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.82, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 28, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, -150, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.63, 0.65)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.35, 0.37, 0.42)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for h in range(0, 13, 2):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(40, 0.03 if h != 10 else 0.14, 0.02)
		line.mesh = box
		line.material_override = lm
		line.position = Vector3(0, h + 0.02, -9)
		root.add_child(line)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = VIEW_HEIGHT
	_camera.far = 200.0
	root.add_child(_camera)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	_label.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	_label.add_theme_constant_override("outline_size", 8)
	_label.position = Vector2(20, 14)
	layer.add_child(_label)
	var labels := Control.new()
	labels.name = "RowLabels"
	layer.add_child(labels)


func _set_view(yaw_deg: float) -> void:
	for holder in _mechs:
		holder.rotation_degrees = Vector3(0, yaw_deg, 0)


func _set_row_labels(visible_on: bool) -> void:
	var labels: Control = _label.get_parent().get_node("RowLabels")
	for c in labels.get_children():
		c.queue_free()
	if not visible_on:
		return
	for i in ROW_NAMES.size():
		var l := Label.new()
		l.text = ROW_NAMES[i]
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		l.add_theme_color_override("font_outline_color", Color(1, 1, 1))
		l.add_theme_constant_override("outline_size", 6)
		var screen := _camera.unproject_position(Vector3((i - 1) * ROW_SPACING, 0, 0))
		l.position = Vector2(screen.x - 200, 848)
		l.size = Vector2(400, 40)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(l)


func _snap(path: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if path != "":
		image.save_png(path)
		print("wrote ", path, " ", image.get_size())
	return image


## One sheet per joint: rows HLY before and HLY after, columns front, side and 3/4 back, each cell 800 x 450 (sheet 2400 x 900).
func _render_closeups(out_dir: String, prefix: String) -> void:
	_label.add_theme_font_size_override("font_size", 40)
	_set_row_labels(false)
	# [name, title, bone, offset in the mech's frame (m), view height (m)].
	var regions := [
		["waist", "Waist (pelvis to chest)", "pelvis", Vector3(0, 0.55, 0), 3.4],
		["neck", "Neck (chest to head)", "head", Vector3(0, -0.45, 0), 3.0],
		["ankle", "Ankle (left foot)", "foot_L", Vector3(0, -0.35, 0), 2.6],
	]
	var cells := [["front", 0.0], ["side", 90.0], ["3/4 back", 145.0]]
	for region: Array in regions:
		var sheet := Image.create(2400, 900, false, Image.FORMAT_RGB8)
		sheet.fill(Color.WHITE)
		for row in 2:
			for i in _mechs.size():
				_mechs[i].visible = i == row
			for c in cells.size():
				var yaw: float = cells[c][1]
				_mechs[row].rotation_degrees = Vector3(0, yaw, 0)
				var skeleton := _skeletons[row]
				var bone := skeleton.find_bone(region[2])
				var local: Vector3 = skeleton.get_bone_global_pose(bone).origin + (region[3] as Vector3)
				var centre := skeleton.global_transform * local
				_camera.size = region[4]
				_camera.rotation_degrees = Vector3.ZERO
				_camera.position = Vector3(centre.x, centre.y, 40)
				_label.text = "%s   %s   %s" % [region[1], ROW_NAMES[row], cells[c][0]]
				var image := await _snap("")
				image.resize(800, 450, Image.INTERPOLATE_BILINEAR)
				image.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(image, Rect2i(0, 0, 800, 450), Vector2i(c * 800, row * 450))
		for i in _mechs.size():
			_mechs[i].visible = true
			_mechs[i].rotation_degrees = Vector3.ZERO
		var path := "%s/%s_closeup_%s.png" % [out_dir, prefix, region[0]]
		sheet.save_png(path)
		print("wrote ", path)
