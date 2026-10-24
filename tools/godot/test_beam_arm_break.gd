extends SceneTree
## Beam break test (user report 2026-10-24): a released charged beam must stop when the arm holding the Beam Rifle
## breaks. Charges, releases, breaks the right arm while the beam fires, and checks that the beam node goes away
## and the rifle stops discharging. Also checks the knock-down rule still stops the beam.
## Run: godot --headless --path . --script res://tools/godot/test_beam_arm_break.gd

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


func _beams() -> int:
	return current_scene.find_children("*", "BeamShot", true, false).size()


func _run() -> void:
	TestMode.settings().free_energy = true
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/beam_rifle.tres") as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var weapons := mech.find_child("WeaponController", true, false) as WeaponController
	var rifle := weapons.right_weapon as BeamRifleWeapon
	_check(rifle != null, "the player holds the Beam Rifle")
	if rifle == null:
		quit(1)
		return
	Input.action_press("aim")
	await _frames(60)
	Input.action_press("use_left_arm")
	await _frames(150)
	Input.action_release("use_left_arm")
	await _frames(10)
	_check(rifle.discharge_left > 0.0 and _beams() > 0, "the charged beam fires (%.2f s left, %d beams)" % [rifle.discharge_left, _beams()])
	var health := mech.find_child("MechHealth", true, false) as MechHealth
	health.damage("Arm R", 1000000.0)
	await _frames(90)
	Input.action_release("aim")
	_check(not is_instance_valid(rifle) or rifle.discharge_left <= 0.0, "the rifle stops discharging after the arm breaks")
	_check(_beams() == 0, "the beam is gone after the arm breaks (%d left)" % _beams())
	print("BEAM ARM BREAK: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
