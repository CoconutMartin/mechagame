extends SceneTree
## Building collapse render (phase 5c): the ground floor of a building (COLLAPSE_BUILDING, default
## Office5F) breaks on one side first, then the rest, and pictures are saved every COLLAPSE_STEP physics
## frames (default 15) for COLLAPSE_SECONDS (default 8) from COLLAPSE_DISTANCE m (default 75) in front.
## Pictures in COLLAPSE_OUT (default user://collapse_renders/).
## Run: xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_collapse.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(name: String, fallback: String) -> String:
	var value := OS.get_environment(name)
	return value if value != "" else fallback


func _run() -> void:
	var out := _env("COLLAPSE_OUT", ProjectSettings.globalize_path("user://collapse_renders"))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(40)
	var map := current_scene
	var building := map.find_child(_env("COLLAPSE_BUILDING", "Office5F"), true, false) as BuildingGenerator
	var ground: Array[UrbanChunk] = []
	for chunk: UrbanChunk in building.chunks:
		if chunk.floor_index == 0 and chunk.kind != UrbanChunk.Kind.SLAB:
			ground.append(chunk)
	# The right side (building +x) goes first: the mass tips that way.
	ground.sort_custom(func(a: UrbanChunk, b: UrbanChunk) -> bool:
		return _local(building, a).x > _local(building, b).x)
	var front := -building.global_basis.z
	var height := building.def.get_height()
	var camera := Camera3D.new()
	camera.fov = 60.0
	map.add_child(camera)
	var target := building.global_position + Vector3.UP * height * 0.45
	camera.global_position = target + front * float(_env("COLLAPSE_DISTANCE", "75")) + Vector3.UP * 4.0
	camera.look_at(target, Vector3.UP)
	camera.current = true
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			(node as Node3D).visible = false
	await _frames(5)
	var step := int(_env("COLLAPSE_STEP", "15"))
	var frames := int(float(_env("COLLAPSE_SECONDS", "8")) * 60.0)
	var shot := 0
	for frame in frames:
		# Two chunks per frame from the right side until the ground floor is gone.
		for i in 2:
			if not ground.is_empty():
				var chunk: Variant = ground.pop_front()
				if is_instance_valid(chunk) and (chunk as UrbanChunk).is_inside_tree():
					(chunk as UrbanChunk).on_hit(1.0e9)
		await _frames(1)
		if frame % step == 0:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/collapse_%03d.png" % [out, shot])
			shot += 1
	print("saved %d pictures" % shot)
	quit()


func _local(building: Node3D, chunk: UrbanChunk) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for child in chunk.get_children():
		if child is CollisionShape3D:
			sum += (child as CollisionShape3D).global_position
			count += 1
	return building.global_transform.affine_inverse() * (sum / maxf(count, 1))
