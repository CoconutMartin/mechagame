extends SceneTree
## Building wear render (phase 5b): the front wall of Office5F, pictures after each step: 0 as built,
## 1 cracks (a wall chunk at 40% HP), 2 scorch marks (a blast and a heavy shell), 3 a concrete chunk breaks
## (rebar, rough rubble flying), 4 the rubble on the ground 3 s later. Pictures in WEAR_OUT
## (default user://wear_renders/).
## Run: xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://tools/godot/render_wear.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const BUILDING := "Office5F"

var _out := ""


func _initialize() -> void:
	_out = OS.get_environment("WEAR_OUT")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://wear_renders")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(40)
	var map := current_scene
	var building := map.find_child(BUILDING, true, false) as BuildingGenerator
	# Front wall chunks of floor 1 and 2 (smallest local z), left to right.
	var front: Array[UrbanChunk] = []
	var min_z := INF
	for chunk: UrbanChunk in building.chunks:
		if chunk.kind == UrbanChunk.Kind.WALL:
			min_z = minf(min_z, _local(building, chunk).z)
	for chunk: UrbanChunk in building.chunks:
		if chunk.kind == UrbanChunk.Kind.WALL and _local(building, chunk).z < min_z + 0.5 and chunk.floor_index in [1, 2]:
			front.append(chunk)
	front.sort_custom(func(a: UrbanChunk, b: UrbanChunk) -> bool:
		return a.floor_index * 1000 + _local(building, a).x < b.floor_index * 1000 + _local(building, b).x)
	print("front wall chunks on floors 1 and 2: ", front.size())
	var normal := -building.global_basis.z
	var middle := Vector3.ZERO
	for chunk in front:
		middle += _center(chunk)
	middle /= front.size()
	var camera := Camera3D.new()
	camera.fov = 55.0
	map.add_child(camera)
	camera.global_position = middle + normal * 16.0 + Vector3.UP * 1.0
	camera.look_at(middle, Vector3.UP)
	camera.current = true
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech:
			(node as Node3D).visible = false
	await _frames(10)
	await _shot("wear_0_built")
	var half := front.size() / 2
	var count := front.size()
	# 1: cracks on two chunks.
	for chunk in [front[1], front[half + 1]]:
		chunk.on_hit(chunk.hp * 0.6, Vector3.INF, &"")
	await _frames(3)
	await _shot("wear_1_cracks")
	# 2: a blast in front of one chunk, a heavy shell on another.
	var blast_target: UrbanChunk = front[mini(3, count - 1)]
	blast_target.on_hit(1.0, _center(blast_target) + normal * 2.0, &"blast")
	var shell_target: UrbanChunk = front[mini(half + 3, count - 1)]
	shell_target.on_hit(160.0, _center(shell_target) + normal * 10.0, &"")
	await _frames(3)
	await _shot("wear_2_scorch")
	# 3: a concrete chunk breaks (rebar on its neighbors, rubble).
	var broken: UrbanChunk = front[mini(half + 2, count - 1)]
	var hole := _center(broken)
	broken.on_hit(1.0e9, hole + normal * 10.0, &"")
	await _frames(12)
	await _shot("wear_3_break")
	await _frames(100)
	await _shot("wear_4_rubble")
	# Close view of the hole.
	camera.global_position = hole + normal * 6.0 + Vector3.UP * 0.5 + building.global_basis.x * 2.0
	camera.look_at(hole, Vector3.UP)
	await _frames(3)
	await _shot("wear_5_hole_close")
	quit()


## The middle of a chunk's collision boxes (world). Chunk nodes stand at the building origin.
func _center(chunk: UrbanChunk) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for child in chunk.get_children():
		if child is CollisionShape3D:
			sum += (child as CollisionShape3D).global_position
			count += 1
	return sum / count if count > 0 else chunk.global_position


func _local(building: Node3D, chunk: UrbanChunk) -> Vector3:
	return building.global_transform.affine_inverse() * _center(chunk)
