extends SceneTree
## Pictures of the player mech built from its part files (DESIGN "Swappable mech parts"): front, three-quarter,
## side and back at rest, then the same four views in a walk. Other mechs are hidden. Each part slot can get a
## tint (TINT=1) to show where one part ends and the next starts. The map's objects are hidden; a plain ground is added. xvfb:
##   RENDER_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_part_models.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## Camera yaw (degrees, 0 = in front of the mech) per view.
const VIEWS := {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "back": 180.0}
## Tint per slot for TINT=1.
const TINTS := {&"head": Color(1.0, 0.45, 0.45), &"core": Color(0.5, 0.8, 1.0), &"arm_left": Color(0.5, 1.0, 0.5),
		&"arm_right": Color(1.0, 0.9, 0.4), &"legs": Color(0.85, 0.55, 1.0)}


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("RENDER_OUT") if OS.has_environment("RENDER_OUT") else "/tmp/part_models"
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in get_nodes_in_group(&"lockable"):
		if node is Mech and node != switcher.mech:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var mech := switcher.mech
	# Only the mech, the lights and a plain ground: the map's buildings and trees would hide it.
	for node in current_scene.find_children("*", "GeometryInstance3D", true, false):
		if not mech.is_ancestor_of(node):
			(node as GeometryInstance3D).visible = false
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	var ground_look := StandardMaterial3D.new()
	ground_look.albedo_color = Color(0.42, 0.43, 0.45)
	ground.material_override = ground_look
	current_scene.add_child(ground)
	ground.global_position = Vector3(mech.global_position.x, 0.0, mech.global_position.z)
	for ui in current_scene.find_children("*", "CanvasLayer", true, false):
		(ui as CanvasLayer).visible = false
	for ui in mech.find_children("*", "CanvasLayer", true, false):
		(ui as CanvasLayer).visible = false
	if OS.get_environment("TINT") == "1":
		var models := mech.get_node("PartModels") as SkeletalPartModels
		for slot: StringName in models.meshes_by_slot:
			for mesh: MeshInstance3D in models.meshes_by_slot[slot]:
				var tint := StandardMaterial3D.new()
				tint.albedo_color = TINTS[slot]
				mesh.material_override = tint
	var camera := Camera3D.new()
	camera.fov = 40.0
	current_scene.add_child(camera)
	camera.current = true
	await _frames(60)
	await _shoot_views(mech, camera, out, "rest")
	var input := mech.get_node("MechInput") as MechInput
	Input.action_press(&"move_forward")
	await _frames(90)
	input.process_mode = Node.PROCESS_MODE_DISABLED
	await _shoot_views(mech, camera, out, "walk")
	Input.action_release(&"move_forward")
	print("RENDER done ", out)
	quit()


func _shoot_views(mech: Mech, camera: Camera3D, out: String, tag: String) -> void:
	for view: String in VIEWS:
		var center := mech.global_position + Vector3.UP * 5.2
		var forward := -mech.global_basis.z
		var dir := forward.rotated(Vector3.UP, deg_to_rad(VIEWS[view]))
		camera.global_position = center + dir * 24.0 + Vector3.UP * 1.5
		camera.look_at(center, Vector3.UP)
		await _frames(2)
		var path := "%s/sgg_%s_%s.png" % [out, tag, view]
		get_root().get_texture().get_image().save_png(path)
		print("RENDER ", path)
