extends SceneTree
## Picture of an attack drone in flight (user 2026-11-02, saucer): the drone is launched from the Drone Pack model at
## a dummy 14 m away and the camera follows it. Writes the picture while the drone glides to its second firing place
## (leaning, the port toward the dummy) to models/backpacks/drone_saucer.png; a second one at the start of a burst.
## The mech and its skin are not in this scene: the model shows its own colors.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --script res://tools/godot/render_drone_saucer.gd
## DRONE_OUT=<file> changes the output file of the flight picture; DRONE_CLOSE=<m> changes the camera distance.

const PACK_MODEL := "res://models/backpacks/backpack_drone.glb"
const DATA := "res://data/equipment/attack_drone.tres"

var _drone: AttackDrone
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("DRONE_OUT") if OS.has_environment("DRONE_OUT") \
			else "res://models/backpacks/drone_saucer.png"
	var close := float(OS.get_environment("DRONE_CLOSE")) if OS.has_environment("DRONE_CLOSE") else 2.3
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.46, 0.5, 0.56)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.32, 0.3)
	floor_mesh.material_override = floor_mat
	floor_mesh.position.y = -6.0
	world.add_child(floor_mesh)
	# A floor to collide with: firing places need ground under them.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -6.5
	world.add_child(floor_body)
	var dummy := TargetDummy.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 10.0, 4.0)
	shape.shape = box
	shape.position.y = 5.0
	dummy.add_child(shape)
	dummy.collision_layer = 2 | 8
	dummy.max_hp = 100000.0
	world.add_child(dummy)
	dummy.global_position = Vector3(0.0, -6.0, -16.0)
	var pack := (load(PACK_MODEL) as PackedScene).instantiate() as Node3D
	world.add_child(pack)
	pack.global_position = Vector3(0.0, 0.0, 0.0)
	var model := pack.find_child("Drone4", true, false) as Node3D
	var data := load(DATA) as DroneData
	await physics_frame
	if OS.has_environment("DRONE_PORT"):
		# Close-up of the port: the disc flat, the port toward -Z, the camera in front of it.
		model.reparent(world, false)
		model.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.0, 0.0, 0.0))
		pack.visible = false
		var cam := Camera3D.new()
		cam.fov = 40.0
		world.add_child(cam)
		cam.make_current()
		cam.look_at_from_position(Vector3(0.45, 0.3, -1.25), Vector3(0.0, 0.0, -0.4), Vector3.UP)
		for i in 6:
			await process_frame
		_save(out.get_basename() + "_port.png")
		quit()
		return
	_drone = AttackDrone.launch(world, model, 1.0, null, dummy, 1.0, data)
	pack.visible = false
	_camera = Camera3D.new()
	_camera.fov = 45.0
	world.add_child(_camera)
	_camera.make_current()
	var shots := 0
	var written_burst := false
	var written_shift := false
	for i in 900:
		await physics_frame
		if not is_instance_valid(_drone) or _drone.is_queued_for_deletion():
			break
		_follow(dummy, close)
		await process_frame
		if not is_instance_valid(_drone):
			break
		if OS.has_environment("DRONE_TRACE") and i % 5 == 0:
			print("age %.2f phase %d step %d bursts %d shifts %d speed %.1f" % [_drone.age, _drone.phase, _drone.step,
					_drone.bursts_fired, _drone.shifts_done, _drone.velocity.length()])
		if _drone.phase == AttackDrone.Phase.FIRE and _drone.step == AttackDrone.Step.BURST and not written_burst \
				and _drone._step_time > 0.25 and _drone.bursts_fired == 1:
			written_burst = true
			_save(out.get_basename() + "_burst.png")
		if _drone.phase == AttackDrone.Phase.FIRE and _drone.step == AttackDrone.Step.SHIFT and not written_shift \
				and _drone.bursts_fired == 2 and _drone._step_time > 0.2 and _drone.velocity.length() > 3.0:
			written_shift = true
			_save(out)
			shots += 1
	print("pictures: burst %s, flight %s, shifts done %d" % [written_burst, written_shift, _drone.shifts_done \
			if is_instance_valid(_drone) else -1])
	quit()


## The camera hangs beside the drone, a bit above and toward the dummy, so the port shows.
func _follow(dummy: Node3D, distance: float) -> void:
	var at := _drone.global_position
	var to_target := (dummy.global_position + Vector3.UP * 5.0 - at)
	to_target.y = 0.0
	to_target = to_target.normalized()
	var side := to_target.cross(Vector3.UP).normalized()
	_camera.look_at_from_position(at + side * distance * 0.55 + Vector3.UP * distance * 0.45 + to_target * distance * 0.95,
			at, Vector3.UP)


func _save(file: String) -> void:
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(file) if file.begins_with("res://") else file
	image.save_png(path)
	print("wrote ", path)
