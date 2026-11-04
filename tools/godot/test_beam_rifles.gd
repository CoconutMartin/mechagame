extends SceneTree
## Beam Rifle 1 to 4 test (user requests 2026-11-01 and 2026-11-02).
## Beam Rifle 1 (BeamRifleWeapon): a very slight aim kick when a charged beam starts. User request 2026-11-04: while the
## charged beam fires the weapon recoils all the time (pushed back, climbs, shakes) and the aim drifts up and wanders with
## a small tremor, so the crosshair moves; no big kick when the beam ends; a held target (the player does nothing) still
## takes most of the damage of a drift-free beam. The damage numbers are printed.
## Beam Rifle 3 (BeamCannonWeapon): rings and side rails grey at rest; during the 0.3 s charge the rings light one after
## another from the back ring to the front ring, then the prong tips; all lit at the shot, then they fade over 1 s;
## no shot before the fade ends; one PPC bolt from the middle barrel; the prong tips red at a shot; 3 s cool down.
## Beam Rifle 2 (BeamRepeaterWeapon): rapid bolts from the middle barrel; the two rail bores glow red while firing; the
## barrel coil (Fin0..5) goes from dark through a dull red to bright red with the heat, and cools back down.
## Beam Rifle 4 (ParticleRifleWeapon): charges while walking, the light bars light body -> midsection -> barrel, the shot
## leaves on the release frame (no stop and no wait), from the muzzle toward the aim point (smaller and weaker for a
## part charge), all bars lit after the shot and fading together over the 6 s cool down, no charge while cooling.
## Times are game time (physics frames), so --fixed-fps 60 runs fast and still measures right.
## Run: godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_beam_rifles.gd

var _fails: int = 0
var _shot_times: Array[float] = []
var _shot_offsets: Array[float] = []
var _rifle3: BeamCannonWeapon
## Shot data of Beam Rifle 4 at the shot: muzzle offset (m) and the angle to the aim point (deg).
var _p4_offset: float = -1.0
var _p4_angle: float = -1.0
var _rifle4: ParticleRifleWeapon


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


## Game time in seconds (physics frames).
func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


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


func _on_rifle4_fired() -> void:
	var muzzle := _rifle4.get_node("Muzzle") as Node3D
	for node in current_scene.find_children("ParticleShot*", "", true, false):
		var shot := node as Bullet
		_p4_offset = shot.global_position.distance_to(muzzle.global_position)
		var aim := (_rifle4.controller.mech_aim.aim_point - shot.global_position).normalized()
		_p4_angle = rad_to_deg(shot.velocity.normalized().angle_to(aim))


## The material of Fin0 of Beam Rifle 2 (the heat glow: emission color and energy).
func _fin(rifle: Node) -> StandardMaterial3D:
	return (rifle.get_node("Model/Fin0") as MeshInstance3D).material_override as StandardMaterial3D


## One full charged beam of Beam Rifle 1 at the dummy with the player doing nothing. Returns the damage the dummy took, the
## aim drift (degrees from the aim before the beam: up at the end, the most side and up on the way), the biggest aim change
## in one frame, the aim change in the 10 frames after the beam ended, and the weapon model recoil seen.
func _beam_run(rifle: BeamRifleWeapon, dummy: TargetDummy) -> Dictionary:
	var free_aim := rifle.controller.mech_aim.camera_rig.free_aim
	while (rifle.heat > 0.0 or rifle.overheated) and _now() < 400.0:
		await _frames(1)
	free_aim._kick_offset = Vector2.ZERO
	free_aim._kick_shown = Vector2.ZERO
	free_aim._pending_kick = Vector2.ZERO
	await _frames(20)
	dummy.hp = dummy.max_hp
	Input.action_press("use_left_arm")
	var t := _now()
	while rifle.charge < 1.0 and _now() - t < 4.0:
		await _frames(1)
	var start := free_aim.aim_offset
	var recoil := rifle.controller.weapon_recoil
	var result := {"up": 0.0, "up_max": 0.0, "side_max": 0.0, "step_max": 0.0, "end_step": 0.0, "model_back": 0.0,
			"model_pitch_min": 0.0, "model_pitch_max": 0.0, "model_yaw_range": 0.0}
	var last := start
	var yaw_min := 0.0
	var yaw_max := 0.0
	Input.action_release("use_left_arm")
	# The beam starts within a few frames of the release.
	for i in 10:
		await _frames(1)
		if rifle.discharge_left > 0.0:
			break
	while rifle.discharge_left > 0.0 and _now() - t < 12.0:
		await _frames(1)
		var now_offset := free_aim.aim_offset - start
		result["up_max"] = maxf(result["up_max"], now_offset.y)
		result["side_max"] = maxf(result["side_max"], absf(now_offset.x))
		result["step_max"] = maxf(result["step_max"], (free_aim.aim_offset - last).length())
		last = free_aim.aim_offset
		var offset := recoil.get_offset()
		var pitch := rad_to_deg(offset.basis.get_euler().x)
		var yaw := rad_to_deg(offset.basis.get_euler().y)
		result["model_back"] = maxf(result["model_back"], offset.origin.z)
		result["model_pitch_min"] = minf(result["model_pitch_min"], pitch)
		result["model_pitch_max"] = maxf(result["model_pitch_max"], pitch)
		yaw_min = minf(yaw_min, yaw)
		yaw_max = maxf(yaw_max, yaw)
	result["model_yaw_range"] = yaw_max - yaw_min
	result["up"] = (free_aim.aim_offset - start).y
	var before_end := free_aim.aim_offset
	await _frames(10)
	result["end_step"] = (free_aim.aim_offset - before_end).length()
	await _frames(20)
	result["damage"] = dummy.max_hp - dummy.hp
	return result


## The recoil of a charged beam (user request 2026-11-04) against a target dummy straight on the crosshair, the player
## doing nothing. A drift-free beam (all drift and model recoil values 0) is the "before" number.
func _beam_drift_checks(rifle: BeamRifleWeapon, distance: float, size: Vector3) -> void:
	var aim := rifle.controller.mech_aim
	# The ring without any leftover kick of an earlier beam.
	var free_aim := aim.camera_rig.free_aim
	free_aim._kick_offset = Vector2.ZERO
	free_aim._kick_shown = Vector2.ZERO
	free_aim._pending_kick = Vector2.ZERO
	await _frames(30)
	var ring := aim.get_ring_screen_point()
	var from := aim.camera.project_ray_origin(ring)
	var direction := aim.camera.project_ray_normal(ring)
	var dummy := TargetDummy.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	dummy.add_child(shape)
	dummy.collision_layer = 2 | 8
	dummy.max_hp = 100000.0
	current_scene.add_child(dummy)
	# `distance` m along the ring ray, in front of any wall the ray reaches first.
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * distance, 29, rifle.controller.mech.get_hit_exclude())
	var wall := rifle.get_world_3d().direct_space_state.intersect_ray(query)
	var center := from + direction * distance if wall.is_empty() else (wall.position as Vector3) - direction * 3.0
	dummy.global_position = center
	await _frames(5)
	# Before: no drift, no model recoil.
	var saved := [rifle.drift_up_deg_per_s, rifle.drift_side_deg_per_s, rifle.drift_tremor_deg, rifle.model_back_m,
			rifle.model_climb_deg, rifle.model_shake_deg]
	rifle.drift_up_deg_per_s = 0.0
	rifle.drift_side_deg_per_s = 0.0
	rifle.drift_tremor_deg = 0.0
	rifle.model_back_m = 0.0
	rifle.model_climb_deg = 0.0
	rifle.model_shake_deg = 0.0
	var before: Dictionary = await _beam_run(rifle, dummy)
	rifle.drift_up_deg_per_s = saved[0]
	rifle.drift_side_deg_per_s = saved[1]
	rifle.drift_tremor_deg = saved[2]
	rifle.model_back_m = saved[3]
	rifle.model_climb_deg = saved[4]
	rifle.model_shake_deg = saved[5]
	var runs: Array[Dictionary] = []
	for i in 3:
		runs.append(await _beam_run(rifle, dummy))
	var gap := dummy.global_position.distance_to(from)
	print("INFO beam at a dummy %.0f m away (a %.0f x %.0f m box, the crosshair on its middle), the player does nothing: damage %.0f before (no drift); with drift %.0f, %.0f, %.0f" % [
			gap, size.x, size.y, before["damage"], runs[0]["damage"], runs[1]["damage"], runs[2]["damage"]])
	_check(before["damage"] > 380.0, "the drift-free full beam does most of its 450 damage on the dummy at %.0f m (%.0f)" % [gap, before["damage"]])
	var worst := INF
	var least_up := INF
	var most_up := 0.0
	var most_step := 0.0
	var side := 0.0
	var end_step := 0.0
	for run in runs:
		worst = minf(worst, run["damage"])
		least_up = minf(least_up, run["up"])
		most_up = maxf(most_up, run["up"])
		most_step = maxf(most_step, run["step_max"])
		side = maxf(side, run["side_max"])
		end_step = maxf(end_step, run["end_step"])
	_check(worst > before["damage"] * 0.6, "a held target still takes most of the damage with the drift (worst %.0f of %.0f)" % [worst, before["damage"]])
	_check(least_up > 0.6 and most_up < 6.0, "the aim climbs a few degrees over the beam (%.2f to %.2f deg up)" % [least_up, most_up])
	_check(side > 0.1, "the aim also moves sideways (up to %.2f deg)" % side)
	_check(most_step < 0.35, "no jump: the aim never moves more than %.2f deg in one frame (must be below 0.35)" % most_step)
	_check(end_step < 0.8, "no big kick when the beam ends (%.2f deg in the next 10 frames)" % end_step)
	_check(runs[0]["model_back"] > 0.1, "the weapon is pushed back while the beam fires (%.2f m)" % runs[0]["model_back"])
	_check(runs[0]["model_pitch_max"] - runs[0]["model_pitch_min"] > 0.3 and runs[0]["model_yaw_range"] > 0.2,
			"the weapon shakes while the beam fires (pitch range %.2f deg, yaw range %.2f deg)" % [
			runs[0]["model_pitch_max"] - runs[0]["model_pitch_min"], runs[0]["model_yaw_range"]])
	_check(runs[0]["model_back"] > before["model_back"] + 0.05, "more model recoil than with the values at 0 (%.2f m against %.2f m)" % [runs[0]["model_back"], before["model_back"]])
	dummy.queue_free()


func _run() -> void:
	TestMode.settings().free_energy = true
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher

	# Beam Rifle 1: a very slight aim kick when the charged beam starts.
	var rifle1 := await _equip(switcher, "res://data/weapons/beam_rifle.tres") as BeamRifleWeapon
	_check(rifle1 != null, "the player holds Beam Rifle 1")
	if rifle1 != null:
		var free_aim := rifle1.controller.mech_aim.camera_rig.free_aim
		Input.action_press("aim")
		await _frames(60)
		Input.action_press("use_left_arm")
		var t1 := _now()
		while rifle1.charge < 1.0 and _now() - t1 < 4.0:
			await _frames(1)
		free_aim._pending_kick = Vector2.ZERO
		Input.action_release("use_left_arm")
		var start_kick := 0.0
		for i in 4:
			await _frames(1)
			start_kick = maxf(start_kick, free_aim._pending_kick.y)
		_check(rifle1.discharge_left > 0.0, "the charged beam fires")
		_check(start_kick > 0.05 and start_kick < 1.0, "a very slight aim kick when the charged beam starts (%.2f deg up)" % start_kick)
		await _frames(150)
		await _beam_drift_checks(rifle1, 40.0, Vector3(4.0, 10.0, 4.0))
		await _beam_drift_checks(rifle1, 40.0, Vector3(3.0, 5.0, 3.0))
		Input.action_release("aim")

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
	# Seconds after the trigger at which each of Ring0..Ring6 and the prong tip (index 7) first glows.
	var lit_at: Array[float] = []
	for i in 8:
		lit_at.append(-1.0)
	var rail_lit_at := -1.0
	var peak := 0.0
	while _shot_times.is_empty() and _now() - start < 2.0:
		await _frames(1)
		for i in 7:
			if lit_at[i] < 0.0 and _energy(_rifle3, "Model/Ring%d" % i) > 0.05:
				lit_at[i] = _now() - start
		if lit_at[7] < 0.0 and _energy(_rifle3, "Model/ProngTipTop") > 0.05:
			lit_at[7] = _now() - start
		if rail_lit_at < 0.0 and _energy(_rifle3, "Model/UpperRail") > 0.05:
			rail_lit_at = _now() - start
		peak = maxf(peak, _energy(_rifle3, "Model/UpperRail"))
	await _frames(2)
	var prong_peak := _energy(_rifle3, "Model/ProngTipBottom")
	_check(not _shot_times.is_empty(), "Beam Rifle 3 fires")
	var shot_at := 0.0
	if not _shot_times.is_empty():
		shot_at = _shot_times[0]
		var delay := _shot_times[0] - start
		_check(delay > 0.25 and delay < 0.6, "the shot comes after the charge (%.2f s; charge 0.3 s plus the raise)" % delay)
		_check(_shot_offsets[0] < 1.0, "the bolt starts at the middle barrel's muzzle (%.2f m)" % _shot_offsets[0])
	var in_order := true
	for i in 7:
		in_order = in_order and lit_at[i] >= 0.0 and (i == 0 or lit_at[i] >= lit_at[i - 1])
	in_order = in_order and lit_at[7] >= lit_at[6]
	_check(in_order, "the rings light one after another, back to front, then the tip (first lit, s: %s)" % str(lit_at))
	_check(lit_at[6] > lit_at[0] and lit_at[7] > lit_at[0], "the front ring and the tip light after the back ring (%.3f -> %.3f s)" % [lit_at[0], lit_at[6]])
	_check(rail_lit_at >= 0.0, "the side rails glow in the charge")
	_check(peak >= _rifle3.ring_energy * 0.85, "the side rails are fully lit at the shot (%.2f)" % peak)
	_check(prong_peak > 1.0, "the prongs glow red after the shot (%.2f)" % prong_peak)
	# The glow fades over 1 s after the shot.
	while _now() - shot_at < 0.5:
		await _frames(1)
	var half := _energy(_rifle3, "Model/Ring3")
	_check(half > _rifle3.ring_energy * 0.25 and half < _rifle3.ring_energy * 0.75, "the glow is about half after 0.5 s (%.2f of %.1f)" % [half, _rifle3.ring_energy])
	while _now() - shot_at < 1.05:
		await _frames(1)
	for path in glow_paths:
		_check(_energy(_rifle3, path) < 0.05, "%s is dark 1 s after the shot (%.2f)" % [path, _energy(_rifle3, path)])
	_check(_rifle3.get_status_text().begins_with("COOLING"), "the HUD shows the cool down (%s)" % _rifle3.get_status_text())
	while _shot_times.size() < 2 and _now() - start < 8.0:
		await _frames(1)
	if _shot_times.size() >= 2:
		var gap := _shot_times[1] - _shot_times[0]
		_check(gap > 3.1 and gap < 3.6, "the held trigger fires again after the 3 s cool down and the charge (%.2f s)" % gap)
	else:
		_check(false, "a second shot after the cool down")
	# No shot before the glow fade ends: a fade longer than the cool down holds the next shot back.
	_rifle3.ring_fade = 4.5
	var t_fade := _now()
	var count := _shot_times.size()
	while _shot_times.size() == count and _now() - t_fade < 8.0:
		await _frames(1)
	Input.action_release("use_left_arm")
	if _shot_times.size() > count:
		var wait := _shot_times[-1] - _shot_times[count - 1]
		_check(wait >= 4.5, "no shot while the glow still fades (a 4.5 s fade: the next shot after %.2f s)" % wait)
	else:
		_check(false, "a shot after a long fade")

	# Beam Rifle 2.
	Input.action_release("aim")
	var rifle2 := await _equip(switcher, "res://data/weapons/beam_rifle_2.tres") as BeamRepeaterWeapon
	var is_repeater := rifle2 != null
	_check(is_repeater, "the player holds Beam Rifle 2")
	if is_repeater:
		var shots := [0]
		rifle2.fired.connect(func() -> void: shots[0] += 1)
		_check(rifle2._muzzles.size() == 1 and rifle2._muzzles[0] == rifle2.get_node("Muzzle"), "Beam Rifle 2 fires from the middle barrel")
		_check(is_zero_approx(_energy(rifle2, "Model/RailTopBore")), "the rail bores are dark at rest")
		_check(is_zero_approx(_energy(rifle2, "Model/Fin0")), "the barrel coil is dark at no heat")
		var cold_albedo := _fin(rifle2).albedo_color
		await _frames(40)
		Input.action_press("use_left_arm")
		var glow := 0.0
		var fin_peak := 0.0
		for i in 90:
			await _frames(1)
			glow = maxf(glow, _energy(rifle2, "Model/RailBottomBoreRing"))
			fin_peak = maxf(fin_peak, _energy(rifle2, "Model/Fin3"))
		_check(shots[0] >= 4 and shots[0] <= 7, "rapid bolts while LMB is held (%d in 1.5 s)" % shots[0])
		_check(glow > 1.0, "the rail bores glow red while firing (%.2f)" % glow)
		_check(fin_peak > 0.02, "the barrel coil starts to glow with the heat (%.2f)" % fin_peak)
		# Keep firing to the overheat: the coil reaches bright red.
		var t2 := _now()
		while not rifle2.overheated and _now() - t2 < 12.0:
			await _frames(1)
		var overheat_peak := _energy(rifle2, "Model/Fin0")
		var hot := _fin(rifle2).emission
		Input.action_release("use_left_arm")
		_check(rifle2.overheated, "Beam Rifle 2 overheats while the trigger is held")
		_check(overheat_peak > rifle2.heat_energy_max * 0.85, "the coil glows at full strength at max heat (%.2f of %.1f)" % [overheat_peak, rifle2.heat_energy_max])
		_check(hot.r > 0.9 and hot.g < 0.15 and hot.b < 0.1, "the coil is bright red at max heat (%s)" % hot)
		# The glow follows the heat: a dull deep red at a low heat, a brighter red higher.
		rifle2.heat = 25.0
		rifle2.overheated = false
		rifle2._show_heat()
		var low_energy := _energy(rifle2, "Model/Fin0")
		var low_color := _fin(rifle2).emission
		rifle2.heat = 60.0
		rifle2._show_heat()
		var mid_energy := _energy(rifle2, "Model/Fin0")
		var mid_color := _fin(rifle2).emission
		_check(low_energy > 0.0 and low_energy < mid_energy and mid_energy < overheat_peak, "the glow grows with the heat (%.2f, %.2f, %.2f)" % [low_energy, mid_energy, overheat_peak])
		_check(low_color.r < 0.7 and low_color.r > 0.3 and low_color.g < 0.12, "a low heat is a dull deep red (%s)" % low_color)
		_check(low_color.r < mid_color.r and mid_color.r < hot.r, "the red gets brighter with the heat (%.2f, %.2f, %.2f)" % [low_color.r, mid_color.r, hot.r])
		# Cools back to dark.
		var t3 := _now()
		while rifle2.heat > 0.0 and _now() - t3 < 14.0:
			await _frames(1)
		await _frames(2)
		_check(is_zero_approx(_energy(rifle2, "Model/Fin0")) and _fin(rifle2).albedo_color.is_equal_approx(cold_albedo), "the coil is dark again when the rifle has cooled (%.2f)" % _energy(rifle2, "Model/Fin0"))

	# Beam Rifle 4: charge while walking, release, the shot leaves on the release frame; light bars. No RMB (RMB raises
	# the rifle, and a raised two-hand rifle locks walking: the sniping stance).
	Input.action_release("aim")
	var rifle4 := await _equip(switcher, "res://data/weapons/beam_rifle_4.tres") as ParticleRifleWeapon
	_rifle4 = rifle4
	_check(rifle4 != null, "the player holds Beam Rifle 4")
	if rifle4 != null:
		var mech := switcher.mech
		var bars := ["Model/LightBar2", "Model/LightBar1", "Model/LightBar0"]
		var shots: Array[float] = []
		rifle4.fired.connect(func() -> void: shots.append(_now()))
		rifle4.fired.connect(_on_rifle4_fired)
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
		# Two frames after the release: the shot is out (no stop, no brace and no raise first).
		await _frames(2)
		var speed_at_shot := mech.get_horizontal_speed()
		var shot_scale := -1.0
		var shot_damage := -1.0
		for node in current_scene.find_children("ParticleShot*", "", true, false):
			shot_scale = (node.get_node("Visual") as Node3D).scale.x
			shot_damage = (node as Bullet).damage
		var delay4 := shots[0] - t0 if not shots.is_empty() else -1.0
		_check(not shots.is_empty() and delay4 <= 0.05, "the shot leaves on the release (%.3f s after the release)" % delay4)
		_check(speed_at_shot > 1.0, "the mech does not stop for the shot, W still held (%.2f m/s)" % speed_at_shot)
		_check(_p4_offset >= 0.0 and _p4_offset < 0.5, "the shot starts at the muzzle (%.2f m)" % _p4_offset)
		_check(_p4_angle >= 0.0 and _p4_angle < 0.5, "the shot flies toward the aim point also at the low ready (%.2f deg off)" % _p4_angle)
		_check(shot_scale > 0.6 and shot_scale < 0.85, "a half charge fires a smaller shot (scale %.2f)" % shot_scale)
		_check(shot_damage > 250.0 and shot_damage < 350.0, "a half charge does less damage (%.0f of 450)" % shot_damage)
		var all_lit := true
		for path in bars:
			all_lit = all_lit and _energy(rifle4, path) > rifle4.bar_energy * 0.95
		_check(all_lit, "all three bars are lit after the shot, whatever the charge")
		await _frames(88)
		e = [_energy(rifle4, bars[0]), _energy(rifle4, bars[1]), _energy(rifle4, bars[2])]
		_check(absf(e[0] - e[2]) < 0.05 and e[0] > rifle4.bar_energy * 0.6 and e[0] < rifle4.bar_energy * 0.9,
				"the bars fade together over the 6 s cool down (%.2f, %.2f, %.2f after 1.5 s)" % e)
		_check(rifle4.get_status_text().begins_with("COOLING"), "the HUD shows the cool down (%s)" % rifle4.get_status_text())
		Input.action_press("use_left_arm")
		await _frames(30)
		_check(is_zero_approx(rifle4.charge), "no charge during the cool down")
		Input.action_release("use_left_arm")
		Input.action_release("move_forward")
		while rifle4.cooling() > 0.0 and _now() - t0 < 12.0:
			await _frames(1)
		var cool_time := _now() - shots[0] if not shots.is_empty() else -1.0
		_check(absf(cool_time - 6.0) < 0.15, "the cool down is 6 s (3 s + 3 s) for a part charge (%.2f s)" % cool_time)
		for path in bars:
			_check(_energy(rifle4, path) < 0.01, "%s is dark again: ready" % path)
		# A full charge: hold 3 s, release; the shot leaves at once, then 6 s of cool down.
		await _frames(10)
		var t_full := _now()
		Input.action_press("use_left_arm")
		while rifle4.charge < 1.0 and _now() - t_full < 4.0:
			await _frames(1)
		var charge_time := _now() - t_full
		Input.action_release("use_left_arm")
		await _frames(2)
		_check(absf(charge_time - 3.0) < 0.15, "a full charge takes 3 s (%.2f s)" % charge_time)
		var full_delay := shots[1] - t_full - charge_time if shots.size() >= 2 else -1.0
		_check(shots.size() >= 2 and full_delay <= 0.05, "the full shot leaves on the release (%.3f s after it)" % full_delay)
		var full_damage := -1.0
		for node in current_scene.find_children("ParticleShot*", "", true, false):
			full_damage = maxf(full_damage, (node as Bullet).damage)
		_check(absf(full_damage - 450.0) < 1.0, "a full charge does full damage (%.0f)" % full_damage)
		while rifle4.cooling() > 0.0 and _now() - t_full < 14.0:
			await _frames(1)
		var cycle := _now() - t_full
		_check(cycle > 8.8 and cycle < 9.4, "a full charge and the cool down take about 9 s: 3 s charge, then 6 s cool down (%.2f s)" % cycle)
	Input.action_release("aim")
	print("BEAM RIFLES: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
