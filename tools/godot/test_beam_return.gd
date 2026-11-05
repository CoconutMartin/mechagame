extends SceneTree
## Automatic crosshair return after a Beam Rifle 4 shot (user request 2026-11-04: "add a small auto crosshair correction
## after shooting"). Unit part (FreeAim alone): a kick with a 70% return comes back by 70% smoothly in about 0.5 s, never
## past zero where the mouse already pulled the crosshair back, and a stack of kicks returns only the last one's share.
## Game part: the player fires a part charge of Beam Rifle 4 in the urban map and the crosshair kick (FreeAim.aim_offset.y) is
## traced: the peak, the value 0.3 and 0.6 s after the peak, the end, the largest step per frame on the way back, with the
## return off (aim_return_share 0, the old behavior) and on. Exit code 1 on a failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_beam_return.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _run() -> void:
	_unit()
	await _game()
	print("BEAM RETURN: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _unit() -> void:
	var dt := 1.0 / 60.0
	var aim := FreeAim.new()
	root.add_child(aim)
	aim.kick(5.0, 0.0)
	aim.return_last_kick(0.7, 0.45, 0.2)
	var peak := 0.0
	var worst_step := 0.0
	var last := 0.0
	var low := 0.0
	for i in 240:
		aim._physics_process(dt)
		var y := aim.aim_offset.y
		peak = maxf(peak, y)
		low = minf(low, y)
		if peak > 4.0 and y < last:
			worst_step = maxf(worst_step, last - y)
		last = y
	print("     unit: peak %.2f deg, after 4 s %.2f deg, largest step back %.3f deg per frame" % [peak, aim.aim_offset.y, worst_step])
	_check(peak > 4.4, "the kick still rises to nearly its size first (peak %.2f of 5)" % peak)
	_check(absf(aim.aim_offset.y - 1.5) < 0.15, "70%% of the kick comes back: %.2f deg left of 5 (want 1.5)" % aim.aim_offset.y)
	_check(low > -0.01, "the return never goes below the pre-shot aim (lowest %.3f)" % low)
	_check(worst_step < 0.2, "the return is smooth (%.3f deg per frame at most)" % worst_step)
	aim.free()
	# The mouse brings the kick back first: the return must not push past zero.
	aim = FreeAim.new()
	root.add_child(aim)
	aim.kick(5.0, 0.0)
	aim.return_last_kick(0.7, 0.45, 0.5)
	for i in 28:
		aim._physics_process(dt)
	aim.take_motion(Vector2(0.0, -aim._kick_offset.y))
	low = 0.0
	for i in 120:
		aim._physics_process(dt)
		low = minf(low, aim.aim_offset.y)
	print("     unit: mouse pulled the kick back, lowest %.3f deg, end %.3f deg" % [low, aim.aim_offset.y])
	_check(low > -0.05 and absf(aim.aim_offset.y) < 0.1, "a kick the mouse already corrected is not pulled past zero (lowest %.3f, end %.3f)" % [low, aim.aim_offset.y])
	aim.free()
	# Two kicks: each return takes its own kick's share only.
	aim = FreeAim.new()
	root.add_child(aim)
	aim.kick(5.0, 0.0)
	aim.return_last_kick(0.7, 0.45, 0.2)
	for i in 240:
		aim._physics_process(dt)
	aim.kick(5.0, 0.0)
	aim.return_last_kick(0.7, 0.45, 0.2)
	for i in 240:
		aim._physics_process(dt)
	_check(absf(aim.aim_offset.y - 3.0) < 0.3, "two shots: 1.5 deg of each stay (%.2f deg, want 3.0)" % aim.aim_offset.y)
	aim.free()


func _game() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/beam_rifle_4.tres") as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(100)
	var player := switcher.mech
	var rifle := (player.get_node("WeaponController") as WeaponController).right_weapon as ParticleRifleWeapon
	_check(rifle != null, "the player holds Beam Rifle 4")
	if rifle == null:
		return
	var rig := player.get_node("CameraRig") as MechCameraRig
	var free_aim := rig.free_aim
	var shares: Array[float] = [0.0, rifle.aim_return_share]
	var results: Array[Dictionary] = []
	for share in shares:
		rifle.aim_return_share = share
		# Ready again (the cool down is 6 s).
		rifle._cooldown = 0.0
		await _frames(60)
		free_aim._kick_offset = Vector2.ZERO
		free_aim._kick_shown = Vector2.ZERO
		await _frames(2)
		var base := free_aim.aim_offset.y
		var pitch_before := rig.pitch
		Input.action_press("use_left_arm")
		await _frames(25)
		Input.action_release("use_left_arm")
		var trace: Array[float] = []
		for i in 150:
			await _frames(1)
			trace.append(free_aim.aim_offset.y - base)
		var peak := 0.0
		var peak_at := 0
		for i in trace.size():
			if trace[i] > peak:
				peak = trace[i]
				peak_at = i
		var step := 0.0
		for i in range(peak_at + 1, trace.size()):
			step = maxf(step, trace[i - 1] - trace[i])
		var at03: float = trace[mini(peak_at + 18, trace.size() - 1)]
		var at06: float = trace[mini(peak_at + 36, trace.size() - 1)]
		results.append({"peak": peak, "end": trace[-1], "step": step})
		print("     return %.0f%%: peak %.2f deg, +0.3 s %.2f, +0.6 s %.2f, end (+%.1f s) %.2f, largest step back %.3f deg/frame, camera pitch moved %.2f deg" % [
				share * 100.0, peak, at03, at06, (trace.size() - peak_at) / 60.0, trace[-1], step, rad_to_deg(rig.pitch - pitch_before)])
	var off := results[0]
	var on := results[1]
	_check(off.peak > 2.0 and off.end > off.peak * 0.9, "return off: the crosshair stays up (peak %.2f, end %.2f)" % [off.peak, off.end])
	_check(on.peak > 2.0 and on.end < on.peak * 0.4 and on.end > on.peak * 0.2, "return on: 60 to 80%% comes back, the rest stays (peak %.2f, end %.2f)" % [on.peak, on.end])
	_check(on.step < 0.25, "the return is smooth (%.3f deg per frame at most)" % on.step)
