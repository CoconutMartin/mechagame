extends SceneTree
## Foot dust test (play test fixes 2026-10-24, round 2): loads the urban map, walks the player mech forward and
## checks that each step makes one thin DustBurst at the landing foot, on the ground. Then a jump landing
## makes two (both feet).
## Run: godot --headless --path . --script res://tools/godot/test_foot_dust.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _fails: int = 0
var _steps: int = 0
var _puffs: Array[DustBurst] = []
## [place, opacity] of each puff, read right after create() placed it.
var _seen: Array = []


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


func _on_node_added(node: Node) -> void:
	if node is DustBurst:
		_puffs.append(node)
		_record.call_deferred(node)


func _record(puff: DustBurst) -> void:
	if is_instance_valid(puff):
		_seen.append([puff.global_position, puff.opacity])


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var player := get_first_node_in_group(&"player") as Mech
	var dust := player.get_node_or_null(^"FootDust") as FootDust if player != null else null
	_check(dust != null, "player has FootDust")
	if dust == null:
		quit(1)
		return
	_check(dust._bones.size() == 2 and dust._bones[0] >= 0 and dust._bones[1] >= 0, "both foot bones found")
	dust.locomotion.footstep.connect(func(_s: float) -> void: _steps += 1)
	node_added.connect(_on_node_added)
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	await _frames(2)
	var on_ground := 0
	var near_foot := 0
	var thin := 0
	for seen: Array in _seen:
		if absf(seen[0].y - player.global_position.y) < 0.5:
			on_ground += 1
		if seen[1] <= 0.3:
			thin += 1
	print("steps %d, puffs %d, on ground %d, thin %d" % [_steps, _puffs.size(), on_ground, thin])
	_check(_steps >= 4, "the walk made steps")
	_check(_puffs.size() == _steps, "one puff per step")
	_check(_seen.size() == _puffs.size() and on_ground == _seen.size() and thin == _seen.size(), "puffs are on the ground and thin")
	# Left and right puffs alternate sides of the mech.
	var sides := []
	for seen: Array in _seen:
		sides.append(signf(player.global_basis.x.dot(seen[0] - player.global_position)))
	var alternate := sides.size() >= 2
	for i in range(1, sides.size()):
		if sides[i] == sides[i - 1]:
			alternate = false
	print("sides ", sides)
	_check(alternate, "puffs alternate left and right feet")
	await _frames(60)
	_puffs.clear()
	_seen.clear()
	Input.action_press("jump")
	await _frames(40)
	Input.action_release("jump")
	var landed := [false]
	player.landed.connect(func(_f: float) -> void: landed[0] = true)
	for i in 600:
		await _frames(1)
		if landed[0]:
			break
	await _frames(1)
	print("landing puffs %d" % _puffs.size())
	_check(landed[0] and _puffs.size() >= 2, "a jump landing puffs under both feet")
	print("FOOT DUST: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
