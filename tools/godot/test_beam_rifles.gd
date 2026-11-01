extends SceneTree
## Beam Rifle 2 and 3 test (user requests 2026-11-01).
## Beam Rifle 3 (BeamCannonWeapon): rings and side rails grey at rest, glowing orange during the 0.3 s charge and
## fully lit at the shot, then fading; one PPC bolt from the middle barrel after the charge; the prong tips red at a
## shot; 3 s cool down (a held trigger fires again about 3.3 s later).
## Beam Rifle 2 (BeamRepeaterWeapon): rapid bolts from the middle barrel; the two rail bores glow red while firing.
## Beam Rifle 4 (ParticleRifleWeapon): charges while walking, the light bars light body -> midsection -> barrel, the
## release stops the mech and fires one particle shot (smaller and weaker for a part charge), all bars lit after the
## shot and fading together over the 3 s cool down, no charge while cooling, a full cycle of about 6 s.
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

	# Beam Rifle 4: charge while walking, release, the mech stops, one particle shot; light bars. No RMB (RMB raises the
	# rifle, and a raised two-hand rifle locks walking: the sniping stance).
	Input.action_release("aim")
	var rifle4 := await _equip(switcher, "res://data/weapons/beam_rifle_4.tres") as ParticleRifleWeapon
	_check(rifle4 != null, "the player holds Beam Rifle 4")
	if rifle4 != null:
		var mech := switcher.mech
		var bars := ["Model/LightBar2", "Model/LightBar1", "Model/LightBar0"]
		var shots: Array[float] = []
		rifle4.fired.connect(func() -> void: shots.append(_now()))
		_check(absf((rifle4.get_node("Muzzle") as Node3D).position.z + 10.0) < 0.05, "the muzzle is 10 m from the butt (%.2f)" % (rifle4.get_node("Muzzle") as Node3D).position.z)
		_check(rifle4.get_status_text() == "READY", "the HUD shows READY (%s)" % rifle4.get_status_text())
		for path in bars:
			_check(is_zero_approx(_energy(rifle4, path)), "%s is dark when ready" % path)
		await _frames(40)
		Input.action_press("move_forward")
		await _frames(30)
		Input.action_press("use_left_arm")
		await _frames(90)
		var moving := mech.get_horizontal_speed()
		_check(rifle4.charge > 0.4 and rifle4.charge < 0.6, "it charges while walking (charge %.2f, %.1f m/s)" % [rifle4.charge, moving])
		_check(moving > 1.0, "the mech walks while it charges (%.1f m/s)" % moving)
		var e := [_energy(rifle4, bars[0]), _energy(rifle4, bars[1]), _energy(rifle4, bars[2])]
		_check(e[0] > rifle4.bar_energy * 0.95 and e[1] > 0.0 and e[1] < rifle4.bar_energy and is_zero_approx(e[2]),
				"the bars light body -> midsection -> barrel at half charge (%.2f, %.2f, %.2f)" % e)
		Input.action_release("use_left_arm")
		var t0 := _now()
		var speed_at_shot := -1.0
		var shot_scale := -1.0
		var shot_damage := -1.0
		while shots.is_empty() and _now() - t0 < 3.0:
			await _frames(1)
		if not shots.is_empty():
			speed_at_shot = mech.get_horizontal_speed()
			for node in current_scene.find_children("ParticleShot*", "", true, false):
				shot_scale = (node.get_node("Visual") as Node3D).scale.x
				shot_damage = (node as Bullet).damage
		_check(not shots.is_empty(), "the release fires a shot (%.2f s after the release)" % (shots[0] - t0 if not shots.is_empty() else -1.0))
		_check(speed_at_shot >= 0.0 and speed_at_shot < 0.5, "the mech stops to fire, W still held (%.2f m/s)" % speed_at_shot)
		_check(shot_scale > 0.6 and shot_scale < 0.85, "a half charge fires a smaller shot (scale %.2f)" % shot_scale)
		_check(shot_damage > 250.0 and shot_damage < 350.0, "a half charge does less damage (%.0f of 450)" % shot_damage)
		await _frames(2)
		var all_lit := true
		for path in bars:
			all_lit = all_lit and _energy(rifle4, path) > rifle4.bar_energy * 0.95
		_check(all_lit, "all three bars are lit after the shot, whatever the charge")
		await _frames(90)
		e = [_energy(rifle4, bars[0]), _energy(rifle4, bars[1]), _energy(rifle4, bars[2])]
		_check(absf(e[0] - e[2]) < 0.05 and e[0] > rifle4.bar_energy * 0.3 and e[0] < rifle4.bar_energy * 0.7,
				"the bars fade together (%.2f, %.2f, %.2f after 1.5 s)" % e)
		_check(rifle4.get_status_text().begins_with("COOLING"), "the HUD shows the cool down (%s)" % rifle4.get_status_text())
		Input.action_press("use_left_arm")
		await _frames(30)
		_check(is_zero_approx(rifle4.charge), "no charge during the cool down")
		Input.action_release("use_left_arm")
		Input.action_release("move_forward")
		while rifle4.cooling() > 0.0 and _now() - t0 < 8.0:
			await _frames(1)
		var cool_time := _now() - shots[0] if not shots.is_empty() else -1.0
		_check(absf(cool_time - 3.0) < 0.15, "the cool down is 3 s for a part charge (%.2f s)" % cool_time)
		for path in bars:
			_check(_energy(rifle4, path) < 0.01, "%s is dark again: ready" % path)
		# A full charge: hold 3 s, release; the full cycle is about 6 s.
		await _frames(10)
		var t_full := _now()
		Input.action_press("use_left_arm")
		while rifle4.charge < 1.0 and _now() - t_full < 4.0:
			await _frames(1)
		var charge_time := _now() - t_full
		Input.action_release("use_left_arm")
		while shots.size() < 2 and _now() - t_full < 6.0:
			await _frames(1)
		_check(absf(charge_time - 3.0) < 0.15, "a full charge takes 3 s (%.2f s)" % charge_time)
		var full_damage := -1.0
		for node in current_scene.find_children("ParticleShot*", "", true, false):
			full_damage = maxf(full_damage, (node as Bullet).damage)
		_check(absf(full_damage - 450.0) < 1.0, "a full charge does full damage (%.0f)" % full_damage)
		while rifle4.cooling() > 0.0 and _now() - t_full < 9.0:
			await _frames(1)
		var cycle := _now() - t_full
		_check(cycle > 5.8 and cycle < 6.6, "a full charge and the cool down take about 6 s (%.2f s)" % cycle)
	Input.action_release("aim")
	print("BEAM RIFLES: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
