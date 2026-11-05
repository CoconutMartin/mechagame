extends SceneTree
## Optimal range cue of the aim reticle (user request 2026-11-04: "crosshair should turn green if any weapon is in
## optimal range"). Unit part: AimReticle.is_in_optimal_range against fake weapon sets (hand weapons, back weapons, a
## shield, an empty gun, an overheated beam, a weapon with no falloff that uses range_m). Map part: the real player in
## the urban map aims at the road at several camera pitches; the reticle's in_optimal_range must match the distance it
## shows and the loadout's optimal range (SMG 32.5 m).
## Exit code 1 on a failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_reticle_range.gd

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


func _weapon(file: String) -> MechWeapon:
	var weapon := MechWeapon.new()
	weapon.setup(load("res://data/weapons/%s.tres" % file) as WeaponData, null)
	return weapon


func _run() -> void:
	_unit()
	await _map()
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _unit() -> void:
	var reticle := AimReticle.new()
	var controller := WeaponController.new()
	reticle.weapons = controller
	_check(not reticle.is_in_optimal_range(10.0), "no weapons: no cue")
	controller.right_weapon = _weapon("shotgun")
	_check(reticle.is_in_optimal_range(100.0), "Shotgun (optimal 135 m) at 100 m: green")
	_check(reticle.is_in_optimal_range(135.0), "Shotgun at exactly 135 m: green")
	_check(not reticle.is_in_optimal_range(140.0), "Shotgun at 140 m: not green")
	_check(not reticle.is_in_optimal_range(-1.0), "no distance: not green")
	controller.right_weapon = _weapon("smg")
	_check(not reticle.is_in_optimal_range(40.0), "SMG (optimal 32.5 m) at 40 m: not green")
	controller.back_left = _weapon("auto_cannon_shoulder")
	_check(reticle.is_in_optimal_range(100.0), "SMG in the hand plus a Shoulder Cannon (112.5 m) on the back: green at 100 m")
	_check(not reticle.is_in_optimal_range(120.0), "both out of range at 120 m: not green")
	controller.back_left = null
	controller.left_weapon = _weapon("auto_cannon")
	_check(reticle.is_in_optimal_range(100.0), "Auto Cannon in the left hand: green at 100 m")
	var spent := _weapon("auto_cannon")
	spent.ammo = 0
	spent.reserve_ammo = 0
	controller.left_weapon = spent
	_check(not reticle.is_in_optimal_range(100.0), "an empty Auto Cannon (no reserve) does not count")
	controller.left_weapon = null
	var hot := _weapon("beam_rifle")
	hot.overheated = true
	controller.right_weapon = hot
	_check(not reticle.is_in_optimal_range(50.0), "an overheated Beam Rifle does not count")
	hot.overheated = false
	_check(reticle.is_in_optimal_range(100.0) and not reticle.is_in_optimal_range(120.0), "Beam Rifle (optimal 112.5 m): green at 100 m, not at 120 m")
	var shield := MechWeapon.new()
	var shield_data := WeaponData.new()
	shield_data.kind = WeaponData.Kind.SHIELD
	shield_data.effective_range_m = 999.0
	shield.setup(shield_data, null)
	controller.right_weapon = null
	controller.left_weapon = shield
	_check(not reticle.is_in_optimal_range(10.0), "a shield does not count")
	controller.left_weapon = null
	controller.right_weapon = _weapon("missile_pod_r")
	_check(reticle.is_in_optimal_range(200.0) and not reticle.is_in_optimal_range(260.0), "no falloff (Missile Pod, effective 0): range_m 250 m is the optimal range")
	_check(is_equal_approx(AimReticle.optimal_range_of(_weapon("auto_cannon")), 112.5), "optimal_range_of(Auto Cannon) = 112.5")
	var loose := _weapon("smg")
	controller.right_weapon = null
	controller.left_weapon = null
	_check(not reticle.is_in_optimal_range(10.0), "a weapon the hands do not hold does not count")
	loose.free()
	reticle.free()
	controller.free()


func _map() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/smg.tres") as WeaponData
	loadout.weapon_left = null
	loadout.back_left = null
	loadout.back_right = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(100)
	var player := switcher.mech
	var rig := player.get_node("CameraRig") as MechCameraRig
	var reticle: AimReticle = null
	for node in map.find_children("*", "AimReticle", true, false):
		reticle = node as AimReticle
	_check(reticle != null and reticle.weapons != null, "the map has an AimReticle wired to the weapons")
	if reticle == null:
		return
	var seen_green := false
	var seen_white := false
	for pitch in [8.0, 0.0, -6.0, -12.0, -25.0]:
		rig._target_pitch = deg_to_rad(pitch)
		rig._pitch_spring.value = deg_to_rad(pitch)
		await _frames(20)
		var distance := reticle.mech_aim.aim_origin.global_position.distance_to(reticle.mech_aim.target_point) if reticle.mech_aim.target != null else -1.0
		var want := distance >= 0.0 and distance <= 32.5
		print("     pitch %+.0f: aimed point %.1f m, in_optimal_range %s" % [pitch, distance, reticle.in_optimal_range])
		_check(reticle.in_optimal_range == want, "pitch %+.0f (%.1f m): the cue %s" % [pitch, distance, "on" if want else "off"])
		seen_green = seen_green or reticle.in_optimal_range
		seen_white = seen_white or not reticle.in_optimal_range
	_check(seen_green and seen_white, "the pitches cover both a green and a not green case")
	reticle.optimal_cue = false
	await _frames(3)
	_check(not reticle.in_optimal_range, "optimal_cue off: no green")
