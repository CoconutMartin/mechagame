extends SceneTree
## Pulse scan pictures (pulse scan phase): the urban map from the player's game camera, a box target in
## group "lockable" 150 m ahead (behind buildings), one scan, pictures at SCAN_TIMES seconds.
## Run under xvfb (frame_post_draw hangs headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3
##   --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_pulse_scan.gd
## Environment: SCAN_OUT (folder, default user://pulse_scan_renders), SCAN_TIMES (default
## "0,0.3,0.8,1.5,3,4.5,6"), SCAN_DISTANCE (target distance, default 150).

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return value if value != "" else fallback


func _run() -> void:
	change_scene_to_file(MAP)
	for i in 60:
		await process_frame
	var out := _env("SCAN_OUT", ProjectSettings.globalize_path("user://pulse_scan_renders"))
	DirAccess.make_dir_recursive_absolute(out)
	var player := get_first_node_in_group(&"player") as Mech
	var camera := root.get_viewport().get_camera_3d()
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var target := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 10.0, 5.0)
	mesh.mesh = box
	mesh.position.y = 5.0
	target.add_child(mesh)
	current_scene.add_child(target)
	target.global_position = player.global_position + ahead * float(_env("SCAN_DISTANCE", "150"))
	target.add_to_group(&"lockable")
	var scanner := AuxMount.find_device(player, PulseScanner) as PulseScanner
	var times: PackedStringArray = _env("SCAN_TIMES", "0,0.3,0.8,1.5,3,4.5,6").split(",")
	var elapsed := 0.0
	var shot := 0
	scanner.scan()
	for value in times:
		var at := float(value)
		while elapsed < at:
			await process_frame
			elapsed += 1.0 / 60.0
		await RenderingServer.frame_post_draw
		var path := "%s/scan_%02d_%0.1fs.png" % [out, shot, at]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved " + path)
		shot += 1
	quit()
