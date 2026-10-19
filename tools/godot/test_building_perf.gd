extends SceneTree
## Building destruction frame time test (phase 5a, user request 2026-10-19: frame drops in big
## collapses). Loads the urban map, waits, then runs one case and logs each frame: wall time (ms),
## physics and process time, rubble and falling chunk counts, nodes, draw calls. The summary gives the
## worst frame, the 95th percentile, the mean and the frames over 33 ms in the event window.
## Cases (PERF_CASE): office (all ground floor chunks of Office5F break in one frame), tower (the ground
## floor of TowerConcrete breaks, 6 chunks per frame, until it collapses), shoot (5 random chunks of
## the near buildings break per frame for 3 s), walk (the player boosts north through Office5F).
## Run (dummy renderer: CPU only):
##   godot --headless --path . --script res://tools/godot/test_building_perf.gd
## Forward+ on the CPU (also the GPU work, slow): VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
##   xvfb-run -a godot --path . --rendering-driver vulkan --script res://tools/godot/test_building_perf.gd
## Environment: PERF_CASE (default office), PERF_FRAMES (frames after the event starts, default 360).

const MAP := "res://maps/urban_small/urban_small.tscn"

var _times: PackedFloat32Array = []


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(60)
	var map := current_scene
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var case := OS.get_environment("PERF_CASE")
	if case == "":
		case = "office"
	var frames := int(OS.get_environment("PERF_FRAMES")) if OS.get_environment("PERF_FRAMES") != "" else 360
	var player := map.get_tree().get_first_node_in_group(&"player") as Mech
	var queue: Array[UrbanChunk] = []
	match case:
		"office":
			queue = _ground_chunks(map, "Office5F")
		"tower":
			queue = _ground_chunks(map, "TowerConcrete")
		"shoot":
			for name in ["Office5F", "Office5F2", "Office5F3"]:
				queue.append_array(_chunks(map, name))
			queue.shuffle()
		"walk":
			var office := map.find_child("Office5F", true, false) as Node3D
			player.global_position = office.global_position + Vector3(0.0, 0.5, 30.0)
			player.rotation.y = 0.0
	print("case %s: %d chunks queued" % [case, queue.size()])
	var per_frame := {"office": 1000, "tower": 6, "shoot": 5}.get(case, 0) as int
	var log: PackedStringArray = []
	var last := Time.get_ticks_usec()
	for frame in frames:
		if case == "walk":
			Input.action_press("move_forward")
			Input.action_press("boost")
		var count := per_frame if case != "shoot" or frame < 180 else 0
		for i in count:
			if queue.is_empty():
				break
			var chunk: UrbanChunk = queue.pop_back()
			if is_instance_valid(chunk) and chunk.is_inside_tree():
				chunk.on_hit(1.0e9)
		await _frames(1)
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		_times.append(ms)
		log.append("f%d ms=%.1f phys=%.1f proc=%.1f rubble=%d falling=%d nodes=%d draws=%d" % [frame, ms,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Rubble._all.size(),
				_count(map, "FallingChunk"), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	Input.action_release("move_forward")
	Input.action_release("boost")
	var out := OS.get_environment("PERF_OUT")
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		for line in log:
			file.store_line(line)
		file.close()
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0.0
	var over := 0
	for t in _times:
		total += t
		if t > 33.3:
			over += 1
	var worst_frame := Array(_times).find(sorted[sorted.size() - 1])
	print("PERF %s: worst %.1f ms (frame %d), p95 %.1f ms, mean %.1f ms, frames over 33 ms: %d of %d" % [
			case, sorted[sorted.size() - 1], worst_frame, sorted[int(sorted.size() * 0.95)], total / _times.size(),
			over, _times.size()])
	print("  worst frame: " + log[worst_frame])
	quit()


## All chunks of a building (by node name) that are standing.
func _chunks(map: Node, building: String) -> Array[UrbanChunk]:
	var out: Array[UrbanChunk] = []
	var root := map.find_child(building, true, false)
	if root == null:
		push_error("no building " + building)
		return out
	for node in root.find_children("*", "UrbanChunk", true, false):
		out.append(node as UrbanChunk)
	return out


## The ground floor walls and columns of a building, last in the queue first (pop_back).
func _ground_chunks(map: Node, building: String) -> Array[UrbanChunk]:
	var out: Array[UrbanChunk] = []
	for chunk in _chunks(map, building):
		if chunk.floor_index == 0 and chunk.kind in [UrbanChunk.Kind.WALL, UrbanChunk.Kind.COLUMN, UrbanChunk.Kind.GLASS,
				UrbanChunk.Kind.DOOR, UrbanChunk.Kind.CORE]:
			out.append(chunk)
	return out


func _count(map: Node, type_name: String) -> int:
	var count := 0
	for node in map.get_children():
		if node.get_script() != null and (node.get_script() as Script).get_global_name() == type_name:
			count += 1
	return count
