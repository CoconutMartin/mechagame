extends SceneTree
## Beam Rifle 2 and 3 test (user requests 2026-11-01).
## Beam Rifle 3 (BeamCannonWeapon): rings and side rails grey at rest, glowing orange during the 0.3 s charge and
## fully lit at the shot, then fading; one PPC bolt from the middle barrel after the charge; the prong tips red at a
## shot; 3 s cool down (a held trigger fires again about 3.3 s later).
## Beam Rifle 2 (BeamRepeaterWeapon): rapid bolts from the middle barrel; the two rail bores glow red while firing.
## Beam Rifle 4 (BeamRepeaterWeapon as a sniper beam): one beam from the muzzle, then 2.5 s until the next; the
## muzzle ring flashes orange; HUD READY / COOLING; the rifle is 10 m long.
## Run: godot --headless --path . --script res://tools/godot/test_beam_rifles.gd

var _fails: int = 0
var _shot_times: Array[float] = []
var _shot_offsets: Array[float] = []
var _rifle3: BeamCannonWeapon


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


func _energy(rifle: Node, path: String) -> float:
	var mesh := rifle.get_node(path) as MeshInstance3D
	var material := mesh.material_override as StandardMaterial3D
	return material.emission_energy_multiplier if material != null and material.emission_enabled else -1.0


func _equip(switcher: LoadoutSwitcher, file: String) -> MechWeapon:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(file) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var weapons := switcher.mech.find_child("WeaponController", true, false) as WeaponController
	return weapons.right_weapon


func _on_rifle3_fired() -> void:
	_shot_times.append(_now())
	var muzzle := _rifle3.get_node("Muzzle") as Node3D
	var best := INF
	for bolt in current_scene.find_children("PpcBolt*", "", true, false):
		best = minf(best, (bolt as Node3D).global_position.distance_to(muzzle.global_position))
	_shot_offsets.append(best)


func _run() -> void:
	TestMode.settings().free_energy = true
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher

	# Beam Rifle 3.
	_rifle3 = await _equip(switcher, "res://data/weapons/beam_rifle_3.tres") as BeamCannonWeapon
	_check(_rifle3 != null, "the player holds Beam Rifle 3")
	if _rifle3 == null:
		quit(1)
		return
	var glow_paths := ["Model/Ring0", "Model/Ring6", "Model/UpperRail", "Model/LowerRail"]
	for path in glow_paths:
		_check(is_zero_approx(_energy(_rifle3, path)), "%s is dark at rest (%.2f)" % [path, _energy(_rifle3, path)])
	var ring_color := ((_rifle3.get_node("Model/Ring0") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	_check(absf(ring_color.r - ring_color.b) < 0.1, "the rings are grey at rest (albedo %s)" % ring_color)
	_check(is_zero_approx(_energy(_rifle3, "Model/ProngTipTop")), "the prongs are dark at rest")
	_rifle3.fired.connect(_on_rifle3_fired)
	Input.action_press("aim")
	await _frames(60)
	Input.action_press("use_left_arm")
	var start := _now()
	var mid_energy := -1.0
	var peak := 0.0
	var prong_peak := 0.0
	while _shot_times.is_empty() and _now() - start < 2.0:
		await _frames(1)
		if _rifle3.charge_left >= 0.0 and _rifle3.charge_left < _rifle3.charge_time * 0.6 and mid_energy < 0.0:
			mid_energy = _energy(_rifle3, "Model/Ring3")
		peak = maxf(peak, _energy(_rifle3, "Model/UpperRail"))
	await _frames(2)
	prong_peak = _energy(_rifle3, "Model/ProngTipBottom")
	_check(not _shot_times.is_empty(), "Beam Rifle 3 fires")
	if not _shot_times.is_empty():
		var delay := _shot_times[0] - start
		_check(delay > 0.25 and delay < 0.6, "the shot comes after the charge (%.2f s; charge 0.3 s plus the raise)" % delay)
		_check(_shot_offsets[0] < 1.0, "the bolt starts at the middle barrel's muzzle (%.2f m)" % _shot_offsets[0])
	_check(mid_energy > 0.0 and mid_energy < _rifle3.ring_energy, "the rings light up during the charge (%.2f)" % mid_energy)
	_check(peak >= _rifle3.ring_energy * 0.85, "the side rails are fully lit at the shot (%.2f)" % peak)
	_check(prong_peak > 1.0, "the prongs glow red after the shot (%.2f)" % prong_peak)
	await _frames(60)
	for path in glow_paths:
		_check(_energy(_rifle3, path) < 0.05, "%s fades after the shot (%.2f)" % [path, _energy(_rifle3, path)])
	_check(_rifle3.get_status_text().begins_with("COOLING"), "the HUD shows the cool down (%s)" % _rifle3.get_status_text())
	while _shot_times.size() < 2 and _now() - start < 6.0:
		await _frames(1)
	Input.action_release("use_left_arm")
	if _shot_times.size() >= 2:
		var gap := _shot_times[1] - _shot_times[0]
		_check(gap > 3.1 and gap < 3.6, "the held trigger fires again after the 3 s cool down and the charge (%.2f s)" % gap)
	else:
		_check(false, "a second shot after the cool down")

	# Beam Rifle 2.
	var rifle2 := await _equip(switcher, "res://data/weapons/beam_rifle_2.tres") as BeamRepeaterWeapon
	var is_repeater := rifle2 != null
	_check(is_repeater, "the player holds Beam Rifle 2")
	if is_repeater:
		var shots := [0]
		rifle2.fired.connect(func() -> void: shots[0] += 1)
		_check(rifle2._muzzles.size() == 1 and rifle2._muzzles[0] == rifle2.get_node("Muzzle"), "Beam Rifle 2 fires from the middle barrel")
		_check(is_zero_approx(_energy(rifle2, "Model/RailTopBore")), "the rail bores are dark at rest")
		await _frames(40)
		Input.action_press("use_left_arm")
		var glow := 0.0
		for i in 90:
			await _frames(1)
			glow = maxf(glow, _energy(rifle2, "Model/RailBottomBoreRing"))
		Input.action_release("use_left_arm")
		_check(shots[0] >= 4 and shots[0] <= 7, "rapid bolts while LMB is held (%d in 1.5 s)" % shots[0])
		_check(glow > 1.0, "the rail bores glow red while firing (%.2f)" % glow)

	# Beam Rifle 4.
	var rifle4 := await _equip(switcher, "res://data/weapons/beam_rifle_4.tres") as BeamRepeaterWeapon
	_check(rifle4 != null, "the player holds Beam Rifle 4")
	if rifle4 != null:
		var times: Array[float] = []
		rifle4.fired.connect(func() -> void: times.append(_now()))
		_check(rifle4._muzzles[0] == rifle4.get_node("Muzzle"), "Beam Rifle 4 fires from its muzzle")
		_check(absf((rifle4.get_node("Muzzle") as Node3D).position.z + 10.0) < 0.05, "the muzzle is 10 m from the butt (%.2f)" % (rifle4.get_node("Muzzle") as Node3D).position.z)
		_check(rifle4.get_status_text() == "READY", "the HUD shows READY (%s)" % rifle4.get_status_text())
		await _frames(40)
		Input.action_press("use_left_arm")
		var ring := 0.0
		var t0 := _now()
		while times.size() < 2 and _now() - t0 < 4.0:
			await _frames(1)
			ring = maxf(ring, _energy(rifle4, "Model/MuzzleRing"))
			if times.size() == 1 and _now() - times[0] > 1.0 and _now() - times[0] < 1.1:
				_check(rifle4.get_status_text().begins_with("COOLING"), "the HUD shows the cool down (%s)" % rifle4.get_status_text())
		Input.action_release("use_left_arm")
		_check(times.size() == 2 and absf(times[1] - times[0] - 2.5) < 0.15, "one beam each 2.5 s (%s)" % str(times))
		_check(ring > 1.0, "the muzzle ring flashes at a shot (%.2f)" % ring)
		var color := ((rifle4.get_node("Model/MuzzleRing") as MeshInstance3D).material_override as StandardMaterial3D).emission
		_check(color.r > 0.9 and color.g > 0.2 and color.g < 0.5, "the flash is orange (%s)" % color)
	Input.action_release("aim")
	print("BEAM RIFLES: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
