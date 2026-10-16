extends SceneTree
## Walk test (user report 2026-10-16: the feet "double bounce" each step). The player walks forward
## for WALK_TIME seconds (default 4); the tool logs each physics frame the height of both foot bones
## and of the Visual node above the ground, and the footstep signals. With a window it saves a side
## picture every WALK_STEP frames (default 0 = none). WALK_OFF turns skeleton modifiers off,
## WALK_SPEED sets the walk speed, WALK_CAM_H and WALK_CAM_D the picture's aim height and distance.
## Run: WALK_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_walk.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("WALK_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://walk_renders")
	DirAccess.make_dir_recursive_absolute(out)
	var seconds := float(OS.get_environment("WALK_TIME")) if OS.get_environment("WALK_TIME") != "" else 4.0
	var step := int(OS.get_environment("WALK_STEP")) if OS.get_environment("WALK_STEP") != "" else 0
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	switcher.rebuild(switcher.current_loadout.duplicate() as Loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var visual := player.get_node("Visual") as Node3D
	# WALK_OFF: skeleton modifier names to turn off (comma list, "all" = every one), to find which one
	# changes the feet.
	var off := OS.get_environment("WALK_OFF")
	for modifier in skeleton.find_children("*", "SkeletonModifier3D", false, false):
		if off == "all" or modifier.name in off.split(","):
			(modifier as SkeletonModifier3D).active = false
			print("off: %s" % modifier.name)
	# WALK_SPEED: walk speed in m/s (default: the mech's own).
	if OS.get_environment("WALK_SPEED") != "":
		player.walk_speed = float(OS.get_environment("WALK_SPEED"))
	var foot_l := skeleton.find_bone("foot_L")
	var foot_r := skeleton.find_bone("foot_R")
	var locomotion := player.find_child("Locomotion", true, false) as SkeletalLocomotion
	var frame := [0]
	if locomotion != null:
		locomotion.footstep.connect(func(strength: float) -> void: print("  footstep frame %d strength %.2f" % [frame[0], strength]))
	var camera := Camera3D.new()
	camera.fov = 35.0
	map.add_child(camera)
	if step > 0:
		camera.current = true
	Input.action_press("move_forward")
	var shot := 0
	print("frame  speed  visual_y  foot_L_y  foot_R_y  phase")
	while frame[0] < int(seconds * 60.0):
		await _frames(1)
		frame[0] += 1
		var ground := player.global_position.y
		var left := (skeleton.global_transform * skeleton.get_bone_global_pose(foot_l)).origin.y - ground
		var right := (skeleton.global_transform * skeleton.get_bone_global_pose(foot_r)).origin.y - ground
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		var phase: float = locomotion.get("_phase") if locomotion != null else 0.0
		print("%4d  %5.2f  %7.3f  %7.3f  %7.3f  %.3f" % [frame[0], speed, visual.global_position.y - ground, left, right, phase])
		if step > 0 and frame[0] % step == 0:
			var side := player.global_basis.x
			var height := float(OS.get_environment("WALK_CAM_H")) if OS.get_environment("WALK_CAM_H") != "" else 3.0
			var distance := float(OS.get_environment("WALK_CAM_D")) if OS.get_environment("WALK_CAM_D") != "" else 30.0
			var at := player.global_position + Vector3.UP * height
			camera.look_at_from_position(at + side * distance, at)
			await process_frame
			map.get_viewport().get_texture().get_image().save_png("%s/walk_%03d.png" % [out, shot])
			shot += 1
	Input.action_release("move_forward")
	quit()
