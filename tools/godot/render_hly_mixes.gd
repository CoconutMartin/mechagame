extends SceneTree
## Pictures of mixed mechs after the Haliya legs-only refit (user choice 2026-11-08): parts of SGG-101 and HLY-101 put together as the
## garage does it (SkeletalPartModels: the legs bring the rig, the core and arms set their bone offsets from their own part rig).
## Needs a renderer, so xvfb on a server:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tools/godot/render_hly_mixes.gd
## Env: OUT_DIR (default docs), NAME (file prefix, default hly_legs_aligned_mixes), POSE ("rest" or "Clip:time", from the legs' rig).
## Writes <NAME>_front.png, _side.png and _back34.png.

## Each mix: label and the mech ("sgg" or "haliya") of the head, core, left arm, right arm and legs.
const MIXES: Array = [
	["HLY legs, SGG top", ["sgg", "sgg", "sgg", "sgg", "haliya"]],
	["SGG legs, HLY top", ["haliya", "haliya", "haliya", "haliya", "sgg"]],
	["HLY, SGG arms", ["haliya", "haliya", "sgg", "sgg", "haliya"]],
	["SGG, HLY arms", ["sgg", "sgg", "haliya", "haliya", "sgg"]],
]
const PART_NAMES: Array[String] = ["head", "core", "arm_l", "arm_r", "legs"]
const RIGS := {"sgg": "res://models/mechs/sgg/sgg_rig.glb", "haliya": "res://models/mechs/haliya/haliya_rig.glb"}
## Camera view height (m) of the pictures (orthographic).
const VIEW_HEIGHT := 14.0
## Distance (m) between the mechs in the row.
const ROW_SPACING := 5.8
## View yaw (degrees) of the mechs for each picture.
const VIEWS: Dictionary = {"front": 0.0, "side": 90.0, "back34": 145.0}

var _camera: Camera3D
var _label: Label
var _mechs: Array[Node3D] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("needs a renderer: run with xvfb-run and --rendering-driver opengl3")
		quit(1)
		return
	var out_dir := OS.get_environment("OUT_DIR") if OS.has_environment("OUT_DIR") else ProjectSettings.globalize_path("res://docs")
	var prefix := OS.get_environment("NAME") if OS.has_environment("NAME") else "hly_legs_aligned_mixes"
	var pose := OS.get_environment("POSE") if OS.has_environment("POSE") else "rest"
	_build_stage()
	for i in MIXES.size():
		_add_mix(MIXES[i], i, pose)
	await process_frame
	await process_frame
	for view: String in VIEWS:
		for holder in _mechs:
			holder.rotation_degrees = Vector3(0, VIEWS[view], 0)
		_camera.position = Vector3(0, VIEW_HEIGHT * 0.5 - 1.0, 40)
		_set_labels()
		_label.text = "Mixed mechs   view: %s   pose: %s   (lines every 2 m)" % [view, pose]
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%s.png" % [out_dir, prefix, view]
		root.get_texture().get_image().save_png(path)
		print("wrote ", path)
	quit()


## The legs' rig with the parts' meshes; the core and arm bones take the offsets of their part rigs, as SkeletalPartModels does.
func _add_mix(mix: Array, index: int, pose: String) -> void:
	var mechs: Array = mix[1]
	var rig := (load(RIGS[mechs[4]]) as PackedScene).instantiate()
	var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	for child in skeleton.get_children():
		skeleton.remove_child(child)
		child.free()
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for p in PART_NAMES.size():
		var mech: String = mechs[p]
		var scene := (load("res://models/mechs/%s/%s_%s.glb" % [mech, mech, PART_NAMES[p]]) as PackedScene).instantiate()
		var source := scene.find_child("Skeleton3D", true, false) as Skeleton3D
		var bones: Array[StringName] = []
		if PART_NAMES[p] == "core":
			bones = SkeletalPartModels.CORE_BONES.duplicate()
		elif PART_NAMES[p].begins_with("arm"):
			for bone in SkeletalPartModels.ARM_BONES:
				bones.append(StringName(bone + ("L" if PART_NAMES[p] == "arm_l" else "R")))
		var changed := false
		for bone_name in bones:
			var bone := skeleton.find_bone(bone_name)
			var from := source.find_bone(bone_name)
			if bone < 0 or from < 0:
				continue
			var rest := skeleton.get_bone_rest(bone)
			var offset := source.get_bone_rest(from).origin
			if rest.origin.distance_to(offset) > SkeletalPartModels.SAME_OFFSET:
				rest.origin = offset
				skeleton.set_bone_rest(bone, rest)
				skeleton.set_bone_pose_position(bone, offset)
				changed = true
		if changed and player != null:
			_drop_position_tracks(player, bones)
		for mi in source.get_children():
			if mi is MeshInstance3D:
				source.remove_child(mi)
				mi.owner = null
				skeleton.add_child(mi)
				(mi as MeshInstance3D).skeleton = NodePath("..")
		scene.free()
	if pose != "rest" and player != null:
		var clip := pose.get_slice(":", 0)
		player.play(clip)
		player.seek(float(pose.get_slice(":", 1)) if pose.contains(":") else 0.0, true)
		player.pause()
	var holder := Node3D.new()
	holder.name = "Mix%d" % index
	holder.add_child(rig)
	holder.position = Vector3((index - (MIXES.size() - 1) * 0.5) * ROW_SPACING, 0, 0)
	root.add_child(holder)
	_mechs.append(holder)


func _drop_position_tracks(player: AnimationPlayer, bones: Array[StringName]) -> void:
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for track in range(animation.get_track_count() - 1, -1, -1):
			if animation.track_get_type(track) == Animation.TYPE_POSITION_3D \
					and StringName(animation.track_get_path(track).get_subname(0)) in bones:
				animation.remove_track(track)


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
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.35, 0.37, 0.42)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for h in range(0, 13, 2):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(40, 0.03, 0.02)
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
	_label.position = Vector2(20, 14)
	layer.add_child(_label)
	var labels := Control.new()
	labels.name = "RowLabels"
	layer.add_child(labels)


func _set_labels() -> void:
	var labels: Control = _label.get_parent().get_node("RowLabels")
	for c in labels.get_children():
		c.free()
	for i in MIXES.size():
		var l := Label.new()
		l.text = MIXES[i][0]
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		var screen := _camera.unproject_position(_mechs[i].position)
		l.position = Vector2(screen.x - 180, 850)
		l.size = Vector2(360, 40)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(l)
