extends SceneTree
## Pictures of the held gun in ADS: standing and kneeling, from the game camera and from the side (user request
## 2026-11-04, kneeling aim). Environment: WEAPON (data/weapons name, default auto_cannon), PITCH (camera pitch in
## degrees, default -6), OUT (directory, default user://barrel_renders).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --fixed-fps 60 --script res://tools/godot/render_barrel_aim.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else ProjectSettings.globalize_path("user://barrel_renders")
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var weapon_name := OS.get_environment("WEAPON") if OS.get_environment("WEAPON") != "" else "auto_cannon"
	var pitch := float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else -6.0
	for kneel in [false, true]:
		var loadout := switcher.current_loadout.duplicate() as Loadout
		loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon_name) as WeaponData
		loadout.weapon_left = null
		switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
		await _frames(100)
		var player := switcher.mech
		var rig := player.get_node("CameraRig") as MechCameraRig
		var controller := player.get_node("WeaponController") as WeaponController
		if kneel:
			Input.action_press("crouch")
			await _frames(2)
			Input.action_release("crouch")
			await _frames(100)
		Input.action_press("aim")
		Input.action_press("use_right_arm")
		rig._target_pitch = deg_to_rad(pitch)
		rig._pitch_spring.value = deg_to_rad(pitch)
		for i in 90:
			controller.right_weapon.reload_left = 1000.0
			rig._target_pitch = deg_to_rad(pitch)
			await _frames(1)
		print("kneel %s amount %.2f" % [kneel, player.kneel.amount])
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_game.png" % [out, weapon_name, "kneel" if kneel else "stand"])
		# Side view.
		var camera := Camera3D.new()
		camera.fov = 32.0
		map.add_child(camera)
		camera.current = true
		for layer in root.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
		var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
		var middle := player.global_position + Vector3.UP * 4.8
		camera.global_position = middle + forward.cross(Vector3.UP) * 26.0
		camera.look_at(middle, Vector3.UP)
		await _frames(2)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_side.png" % [out, weapon_name, "kneel" if kneel else "stand"])
		camera.queue_free()
		Input.action_release("aim")
		Input.action_release("use_right_arm")
		await _frames(10)
	quit()
