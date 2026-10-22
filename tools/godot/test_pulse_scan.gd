extends SceneTree
## Pulse scan test (pulse scan phase): loads the urban map, checks the player's back pack device, runs a
## scan, and checks uses, cool down, the found targets (highlight and ScanAlert) and the clean up.
## Run: godot --headless --path . --script res://tools/godot/test_pulse_scan.gd
## Prints PASS or FAIL lines and a summary; exit code 1 on a failure.

const MAP := "res://maps/urban_small/urban_small.tscn"

var _fails: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _box_target(place: Vector3) -> Node3D:
	var target := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 10.0, 4.0)
	mesh.mesh = box
	mesh.position.y = 5.0
	target.add_child(mesh)
	current_scene.add_child(target)
	target.global_position = place
	target.add_to_group(&"lockable")
	return target


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var player := get_first_node_in_group(&"player") as Mech
	_check(player != null, "player mech found")
	if player == null:
		quit(1)
		return
	var scanner := AuxMount.find_device(player, PulseScanner) as PulseScanner
	_check(scanner != null, "player has a PulseScanner in AuxMount")
	if scanner == null:
		quit(1)
		return
	var data := scanner.data
	_check(data.grade == 2 and data.uses == 4 and is_equal_approx(data.range_m, 500.0), "grade 2 data (500 m, 4 uses)")
	_check(InputMap.action_get_events(&"aux_1").size() == 1, "aux_1 has one key")
	# Test targets: boxes in group "lockable" at 200 m (found) and 600 m (out of range).
	var near := _box_target(player.global_position + Vector3(200.0, 0.0, 0.0))
	var far := _box_target(player.global_position + Vector3(0.0, 0.0, 600.0))
	var targets: Array = []
	for node in get_nodes_in_group(&"lockable"):
		var target := node as Node3D
		if target != null and target != player and player.global_position.distance_to(target.global_position) <= data.range_m:
			targets.append(target)
	print("targets in range: %d" % targets.size())
	_check(scanner.scan(), "first scan starts")
	_check(scanner.uses_left == data.uses - 1 and scanner.cooldown_left > 0.0, "a use is spent and the cool down runs")
	_check(not scanner.scan(), "no second scan during the cool down")
	_check(current_scene.get_node_or_null(^"PulseScanEffect") != null, "wire frame effect made")
	var found := [0]
	scanner.scanned.connect(func(count: int) -> void: found[0] = count)
	await _frames(int(data.range_m / data.ring_speed * 60.0) + 10)
	_check(found[0] == targets.size(), "scanned signal counts every target in range (%d of %d)" % [found[0], targets.size()])
	var lit := 0
	for target: Node3D in targets:
		if is_instance_valid(target) and target.get_node_or_null(^"PulseScanHighlight") != null and target.get_node_or_null(^"ScanAlert") != null:
			lit += 1
	_check(lit == targets.size(), "every target has a highlight and a ScanAlert (%d)" % lit)
	_check(targets.has(near) and near.get_node_or_null(^"PulseScanHighlight") != null, "the 200 m box is highlighted")
	_check(far.get_node_or_null(^"PulseScanHighlight") == null, "the 600 m box is not highlighted")
	_check(player.get_node_or_null(^"PulseScanHighlight") == null, "the player is not highlighted")
	var box := near.get_child(0) as MeshInstance3D
	_check(box.material_overlay != null, "the box has the glow overlay")
	await _frames(int((data.highlight_time + 1.0) * 60.0))
	var left := 0
	for target: Node3D in targets:
		if is_instance_valid(target) and target.get_node_or_null(^"PulseScanHighlight") != null:
			left += 1
	_check(left == 0, "highlights end after the highlight time")
	_check(box.material_overlay == null, "the glow overlay is removed")
	await _frames(int(data.wireframe_time * 60.0))
	_check(current_scene.get_node_or_null(^"PulseScanEffect") == null, "wire frame effect freed")
	scanner.cooldown_left = 0.0
	for i in data.uses:
		scanner.cooldown_left = 0.0
		scanner.scan()
	_check(scanner.uses_left == 0 and not scanner.is_ready(), "uses run out")
	print("PULSE SCAN: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
