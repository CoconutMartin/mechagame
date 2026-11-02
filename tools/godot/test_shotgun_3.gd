extends SceneTree
## Shotgun 3 and manual shotgun fire test (user requests 2026-11-01). Shotgun 3: the heads spin while the trigger is
## held, the X pulse (9 pellets on the diagonals and one X look) leaves after the 0.2 s hold, holding on fires no more,
## the heads slow down after the shot, letting go before 0.2 s fires nothing, a new press fires again. The first
## Shotgun: one shot per press (held 1.5 s = 1 shot).
## Run: godot --headless --path . --script res://tools/godot/test_shotgun_3.gd

var _fails: int = 0


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


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _equip(switcher: LoadoutSwitcher, file: String) -> MechWeapon:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(file) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	return (switcher.mech.find_child("WeaponController", true, false) as WeaponController).right_weapon


func _pellets() -> Array[Node]:
	return current_scene.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.scene_file_path == "res://scenes/weapons/pulse_pellet.tscn")


func _run() -> void:
	TestMode.settings().free_energy = true
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var gun := await _equip(switcher, "res://data/weapons/shotgun_3.tres") as SpinPulseShotgunWeapon
	_check(gun != null, "the player holds Shotgun 3")
	if gun == null:
		quit(1)
		return
	var spinner := gun.get_node("Model/Heads") as Node3D
	var times: Array[float] = []
	gun.fired.connect(func() -> void: times.append(_now()))
	# Raise the gun first (RMB raises a one-hand gun), so the hold time shows alone.
	Input.action_press("use_right_arm")
	await _frames(6)
	Input.action_release("use_right_arm")
	await _frames(2)
	_check(times.is_empty(), "a 0.1 s press fires nothing")
	var spun := spinner.rotation.z
	await _frames(40)
	times.clear()
	Input.action_press("use_right_arm")
	var t0 := _now()
	await _frames(6)
	_check(gun.spin_speed > 0.0 and absf(spinner.rotation.z - spun) > 0.01, "the heads spin while held (%.0f deg/s)" % gun.spin_speed)
	_check(times.is_empty(), "no shot before 0.2 s")
	while times.is_empty() and _now() - t0 < 2.0:
		await _frames(1)
	var delay := times[0] - t0 if not times.is_empty() else -1.0
	_check(delay > 0.18 and delay < 0.6, "the pulse leaves after the hold (%.2f s, 0.2 s plus the raise)" % delay)
	var pellets := _pellets()
	# The pellets' flight directions against the middle one, across and up: an X has |across| = |up|.
	var center := Vector3.ZERO
	for p in pellets:
		center += (p as Bullet).velocity.normalized()
	center = center.normalized()
	var across := center.cross(Vector3.UP).normalized()
	var upward := across.cross(center).normalized()
	var tx := tan(deg_to_rad(gun.pattern_half_deg.x))
	var ty := tan(deg_to_rad(gun.pattern_half_deg.y))
	var on_x := true
	for p in pellets:
		var d := (p as Bullet).velocity.normalized() - center
		on_x = on_x and absf(absf(d.dot(across)) / tx - absf(d.dot(upward)) / ty) < 0.05
	_check(pellets.size() == 9 and on_x, "9 pellets on an X, corner to corner of the rectangle (%d)" % pellets.size())
	var looks := current_scene.find_children("*", "PulseShot", true, false)
	_check(looks.size() == 1 and (looks[0] as PulseShot).cross, "one X pulse look")
	_check(gun.uses_heat() and gun.heat > 0.0, "the pulse shot adds heat, no ammo (%.0f)" % gun.heat)
	var webs := current_scene.find_children("*", "PulseArcWeb", true, false)
	_check(webs.size() == 1 and (webs[0] as PulseArcWeb).links.size() == 8,
			"one arc web on the X links (%d)" % ((webs[0] as PulseArcWeb).links.size() if webs.size() > 0 else -1))
	var with_look := _pellets().filter(func(n: Node) -> bool: return n.get_node_or_null("Look") is PulsePelletLook)
	_check(with_look.size() == _pellets().size(), "every pellet has the electric look (%d)" % with_look.size())
	var top := gun.spin_speed
	await _frames(30)
	_check(gun.spin_speed < top - 100.0 and gun.spin_speed > 0.0, "the heads slow down after the shot (%.0f -> %.0f deg/s)" % [top, gun.spin_speed])
	await _frames(60)
	_check(times.size() == 1, "holding on fires no more (%d shots)" % times.size())
	Input.action_release("use_right_arm")
	await _frames(2)
	Input.action_press("use_right_arm")
	var t1 := _now()
	while times.size() < 2 and _now() - t1 < 2.0:
		await _frames(1)
	Input.action_release("use_right_arm")
	_check(times.size() == 2, "a new press fires again (%.2f s after the press)" % (times[1] - t1 if times.size() == 2 else -1.0))

	# The first Shotgun: one shot per press.
	var shotgun := await _equip(switcher, "res://data/weapons/shotgun.tres")
	var shots := [0]
	shotgun.fired.connect(func() -> void: shots[0] += 1)
	Input.action_press("use_right_arm")
	await _frames(90)
	Input.action_release("use_right_arm")
	_check(shots[0] == 1, "the Shotgun fires once while held 1.5 s (%d)" % shots[0])
	await _frames(60)
	Input.action_press("use_right_arm")
	await _frames(40)
	Input.action_release("use_right_arm")
	_check(shots[0] == 2, "the Shotgun fires again on a new press (%d)" % shots[0])
	print("SHOTGUN 3: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
