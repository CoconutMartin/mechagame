extends SceneTree
## Shotgun 2 test (user request 2026-11-01): a square electric pulse shot (a 3 x 3 square of pellets and one square
## frame look), one shot per press and two shots a second at most (fast taps), the three heads open fully at each shot (their fronts move out
## from the bore) and go back to neutral, the emitter ring flashes and the arc shows at a shot.
## Run: godot --headless --path . --script res://tools/godot/test_shotgun_2.gd

var _fails: int = 0
var _times: Array[float] = []


func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	TestMode.settings().free_energy = true
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/shotgun_2.tres") as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var weapons := switcher.mech.find_child("WeaponController", true, false) as WeaponController
	var gun := weapons.right_weapon as PulseShotgunWeapon
	_check(gun != null, "the player holds Shotgun 2")
	if gun == null:
		quit(1)
		return
	var head := gun.get_node("Model/Head0") as Node3D
	var tip := head.find_child("HeadBlock*", true, false) as Node3D
	var muzzle := gun.get_node("Muzzle") as Node3D
	var arc := gun.get_node("Model/ArcRing") as Node3D
	var rest_out := _out(gun, tip, muzzle)
	_check(not arc.visible, "the arc is hidden at rest")
	gun.fired.connect(func() -> void: _times.append(Time.get_ticks_msec() / 1000.0))
	Input.action_press("use_right_arm")
	while _times.is_empty():
		await _frames(1)
	var pellets := _pellets().size()
	var looks := current_scene.find_children("*", "PulseShot", true, false).size()
	_check(pellets == 9, "one shot = 9 pellets (%d)" % pellets)
	_check(looks == 1, "one square pulse look per shot (%d)" % looks)
	_check(arc.visible, "the arc shows at the shot")
	var ring := ((gun.get_node("Model/EmitterRing") as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier
	_check(ring > 1.0, "the emitter ring flashes (%.2f)" % ring)
	await _frames(4)
	var open_out := _out(gun, tip, muzzle)
	_check(gun.head_open_amount() > 0.9, "the heads are fully open just after the shot (%.2f)" % gun.head_open_amount())
	_check(open_out > rest_out + 0.15, "the top head's front moves out from the bore (%.2f -> %.2f m)" % [rest_out, open_out])
	# The pellets fly on a square: compare their spread across and up.
	var xs: Array[float] = []
	var ys: Array[float] = []
	for p in _pellets():
		var local := muzzle.global_transform.affine_inverse() * (p as Node3D).global_position
		xs.append(local.x)
		ys.append(local.y)
	var w: float = xs.max() - xs.min()
	var h: float = ys.max() - ys.min()
	_check(w > 0.5 and absf(w - h) < 0.25 * w, "the pellets fly in a square (%.2f x %.2f m)" % [w, h])
	await _frames(20)
	_check(gun.head_open_amount() < 0.05, "the heads are back to neutral before the next shot (%.2f)" % gun.head_open_amount())
	_check(absf(_out(gun, tip, muzzle) - rest_out) < 0.02, "the head is back at its rest place")
	# Manual fire (user rule 2026-11-01): holding the trigger fires no more shots.
	await _frames(60)
	_check(_times.size() == 1, "holding the trigger fires once (%d shots in 1.3 s)" % _times.size())
	Input.action_release("use_right_arm")
	await _frames(2)
	# Fast taps: at most two shots a second.
	var t0 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < 1.6:
		Input.action_press("use_right_arm")
		await _frames(2)
		Input.action_release("use_right_arm")
		await _frames(2)
	var gaps: Array[float] = []
	for i in range(2, _times.size()):
		gaps.append(_times[i] - _times[i - 1])
	_check(_times.size() >= 4 and gaps.min() > 0.45 and gaps.min() < 0.6, "fast taps fire two shots a second (gaps %s)" % str(gaps))
	print("SHOTGUN 2: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)


## The pellets in the world (siblings with one name get new names, so match the scene file).
func _pellets() -> Array[Node]:
	return current_scene.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.scene_file_path == "res://scenes/weapons/pulse_pellet.tscn")


## How far the head mesh's center is from the bore line (m).
func _out(gun: Node3D, mesh: Node3D, muzzle: Node3D) -> float:
	var aabb := (mesh as MeshInstance3D).get_aabb()
	var front := mesh.global_transform * (aabb.position + aabb.size * 0.5 - Vector3(0, 0, aabb.size.z * 0.5))
	var local := muzzle.global_transform.affine_inverse() * front
	return Vector2(local.x, local.y).length()
