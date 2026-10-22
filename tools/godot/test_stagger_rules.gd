extends SceneTree
## Stagger rules test (user request 2026-10-22). Real weapons, a real enemy mech (the map's target dummy,
## the same SGG-101 as the AI enemy, 59.6 t = medium class, stagger scale 1.0, standing). Each rule is
## proved from both sides, with the real input path (Input.action_press into MechInput, WeaponController,
## the weapon scripts, the bullets and the beam) and the real stagger reaction (SkeletalStaggerAnimation):
##   Auto Cannon: 2 hits no stagger, 3 hits stagger (4 s between shots; the meter is held 4.6 s).
##   SMG: 80% of the magazine (36 of 45) no stagger, 85% (38) stagger.
##   Beam Rifle: a full charge that hits the whole beam staggers; a 95% charge, an 80% charge, or a full
##   beam that hits only 90% of its ticks does not.
## The stagger points are not scaled by the range, so the rules hold at any distance inside the weapon's max
## range; the test runs near (RANGE_NEAR) and the Auto Cannon also far (RANGE_FAR, inside its 112.5 m optimal).
## A part of the test works on the stability API with the real weapon values (no map). Exits with code 1 on
## any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_stagger_rules.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const WEAPON_DIR := "res://data/weapons/"
## Muzzle to target distances, in meters (about; the dummy is placed this far in front of the player).
const RANGE_NEAR := 25.0
const RANGE_FAR := 100.0
const DUMMY_Z := -30.0

var _failures: int = 0
var _checks: int = 0
var _level: Node
var _switcher: LoadoutSwitcher
var _player: Mech
var _weapons: WeaponController
var _dummy: Mech
var _meter: MechStability
var _stagger: SkeletalStaggerAnimation
var _hits: int = 0
var _staggers: int = 0
var _knocks: int = 0
## True once the stagger reaction played since the last _calm (it is checked every frame).
var _saw_stagger: bool = false
var _saw_down: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		if _stagger != null:
			if _stagger.is_down:
				_saw_down = true
			elif _stagger.is_staggered():
				_saw_stagger = true


func _check(ok: bool, text: String) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _run() -> void:
	_test_api_values()
	change_scene_to_file(MAP)
	await _frames(30)
	_level = current_scene
	for node in _level.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	_switcher = _level.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var spawner := _level.get_node("Targets/DummyMech") as MechSpawner
	spawner.process_mode = Node.PROCESS_MODE_INHERIT
	spawner.set_active(true)
	await _frames(40)
	_dummy = spawner.mech
	_dummy.process_mode = Node.PROCESS_MODE_INHERIT
	_dummy.visible = true
	for key: String in _dummy.health.max_hp:
		_dummy.health.max_hp[key] = 1.0e9
		_dummy.health.hp[key] = 1.0e9
	_meter = _dummy.health.stability
	_stagger = _dummy.find_child("StaggerAnimation", true, false) as SkeletalStaggerAnimation
	_check(_meter != null and _stagger != null, "the enemy mech has a stagger meter and the stagger animation")
	if _meter == null or _stagger == null:
		quit(1)
		return
	_meter.hit_taken.connect(func(_points: float, _from: Vector3) -> void: _hits += 1)
	_meter.staggered.connect(func(_from: Vector3) -> void: _staggers += 1)
	_meter.knocked_down.connect(func(_from: Vector3) -> void: _knocks += 1)
	_check(_meter.get_scale() == 1.0, "enemy mech: medium class, standing, scale 1.0 (got %.2f)" % _meter.get_scale())

	await _auto_cannon(RANGE_NEAR)
	await _auto_cannon(RANGE_FAR)
	await _smg()
	await _beam_rifle()
	_release()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- part 1: the stability API with the real weapon values -------------------------------------------

func _load(file: String) -> WeaponData:
	return load(WEAPON_DIR + file + ".tres") as WeaponData


## Fires `shots` hits of a gun at its real fire interval into a meter (no mech: medium scale) and returns the
## number of staggers. `gap` replaces the fire interval when above 0.
func _api_hits(data: WeaponData, shots: int, gap: float = 0.0) -> Array:
	var meter := MechStability.new()
	var staggers := [0]
	var knocks := [0]
	meter.staggered.connect(func(_from: Vector3) -> void: staggers[0] += 1)
	meter.knocked_down.connect(func(_from: Vector3) -> void: knocks[0] += 1)
	var interval := gap if gap > 0.0 else 1.0 / data.fire_rate
	for i in shots:
		meter.add_hit(data.stagger_points, 0, data.stagger_cap_per_shot, Vector3.INF, data.stagger_hold_s)
		if i < shots - 1:
			for step in int(round(interval * 60.0)):
				meter.advance(1.0 / 60.0)
	var result := [staggers[0], knocks[0], meter.value]
	meter.free()
	return result


func _test_api_values() -> void:
	var cannon := _load("auto_cannon")
	var two := _api_hits(cannon, 2)
	var three := _api_hits(cannon, 3)
	_check(two[0] == 0 and two[1] == 0, "API: Auto Cannon 2 shots (%.0f points): no stagger" % two[2])
	_check(three[0] == 1 and three[1] == 0, "API: Auto Cannon 3 shots: one stagger, no knock-down")
	var slow := _api_hits(cannon, 3, cannon.stagger_hold_s + 0.5)
	_check(slow[0] == 0, "API: Auto Cannon 3 shots with %.1f s between them (past the hold): no stagger" % (cannon.stagger_hold_s + 0.5))
	_check(cannon.stagger_hold_s > 1.0 / cannon.fire_rate, "API: the hold (%.1f s) is longer than the time between shots (%.1f s)" % [cannon.stagger_hold_s, 1.0 / cannon.fire_rate])
	var smg := _load("smg")
	var magazine := smg.magazine
	var low := int(round(magazine * 0.8))
	var high := int(round(magazine * 0.85))
	var below := _api_hits(smg, low)
	var above := _api_hits(smg, high)
	_check(below[0] == 0, "API: SMG %d of %d bullets (80%%, %.1f points): no stagger" % [low, magazine, below[2]])
	_check(above[0] == 1, "API: SMG %d of %d bullets (85%%): stagger" % [high, magazine])
	var just_below := _api_hits(smg, high - 1)
	_check(just_below[0] == 0, "API: SMG %d bullets (%.1f%%, %.1f points): no stagger" % [high - 1, 100.0 * (high - 1) / magazine, just_below[2]])
	# Other guns keep their rhythm: a heavy rifle (3 s between shots) does not add up.
	var rifle := _load("heavy_rifle")
	_check(rifle.stagger_hold_s == 0.0, "API: Heavy Rifle has no hold (unchanged)")
	_check(_api_hits(rifle, 12)[0] == 0, "API: 12 Heavy Rifle shots 3 s apart: no stagger (unchanged)")


# --- part 2: real weapons, real enemy mech ---------------------------------------------------------------

func _release() -> void:
	for action in ["use_left_arm", "use_right_arm", "aim"]:
		Input.action_release(action)


## Builds the player with this right hand weapon `distance` m in front of the dummy and aims at its torso.
func _setup(file: String, distance: float) -> void:
	_release()
	var loadout := _switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = _load(file)
	loadout.weapon_left = null
	_switcher.current_loadout = loadout
	# The aim ray runs straight ahead at about torso height, 7 m right of the mech origin.
	_dummy.global_position = Vector3(2.07, 0.0, DUMMY_Z)
	_switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.0, DUMMY_Z + distance)))
	await _frames(60)
	_player = _switcher.mech
	_weapons = _player.get_node("WeaponController") as WeaponController
	var aim := _player.get_node("MechAim") as MechAim
	# No aim recoil in this test: the player would pull the aim back by hand, the test cannot.
	var free_aim := _player.find_child("FreeAim", true, false) as FreeAim
	_check(free_aim != null, "the player has a FreeAim")
	if free_aim != null:
		free_aim.recoil_multiplier = 0.0
	var camera_x: float = (_player.get_node("CameraRig/Pitch/SpringArm/Camera") as Camera3D).global_position.x
	_dummy.global_position = Vector3(camera_x, 0.0, DUMMY_Z)
	await _frames(20)
	var on_target := aim.target is PartHitbox and (aim.target as PartHitbox).health == _dummy.health
	_check(on_target, "%s: the aim point is on the enemy mech (%.0f m)" % [file, _player.global_position.distance_to(_dummy.global_position)])
	await _calm()


## Waits until the enemy mech plays no reaction and its meter is empty.
func _calm(max_frames: int = 1500) -> void:
	await _frames(30)
	var guard := 0
	while (_stagger.is_staggered() or _stagger.is_down or _meter.value > 0.0 or _meter.is_protected()) and guard < max_frames:
		await _frames(1)
		guard += 1
	_hits = 0
	_staggers = 0
	_knocks = 0
	_saw_stagger = false
	_saw_down = false


## Holds a button until `count` hits landed on the enemy mech (or the time is up), then releases it.
## Returns the seconds it took.
func _fire_until(action: String, count: int, max_seconds: float) -> float:
	var frames := 0
	Input.action_press(action)
	while _hits < count and frames < int(max_seconds * 60.0):
		await _frames(1)
		frames += 1
	Input.action_release(action)
	return frames / 60.0


## A stagger reaction (not a knock-down) now plays.
func _is_staggering() -> bool:
	return _saw_stagger


func _auto_cannon(distance: float) -> void:
	await _setup("auto_cannon", distance)
	var from_muzzle := _player.global_position.distance_to(_dummy.global_position)
	# 2 shots.
	var time := await _fire_until("use_right_arm", 2, 20.0)
	await _frames(40)
	_check(_hits == 2 and _staggers == 0 and not _is_staggering() and _knocks == 0,
			"Auto Cannon %.0f m: 2 hits in %.1f s: no stagger (hits %d, staggers %d, meter %.0f)" % [from_muzzle, time, _hits, _staggers, _meter.value])
	_check(absf(_meter.value - 68.0) < 1.0, "Auto Cannon: the meter holds the 2 hits (68, got %.1f)" % _meter.value)
	# The 3rd shot, 4 s after the 2nd.
	time = await _fire_until("use_right_arm", 3, 20.0)
	await _frames(20)
	_check(_hits == 3 and _staggers == 1 and _knocks == 0,
			"Auto Cannon %.0f m: 3rd hit: stagger (hits %d, staggers %d, knock-downs %d)" % [from_muzzle, _hits, _staggers, _knocks])
	_check(_saw_stagger and not _saw_down, "Auto Cannon: the stagger reaction plays (no knock-down)")
	await _calm()


func _smg() -> void:
	await _setup("smg", RANGE_NEAR)
	var data := _load("smg")
	var low := int(round(data.magazine * 0.8))
	var high := int(round(data.magazine * 0.85))
	var from_muzzle := _player.global_position.distance_to(_dummy.global_position)
	var time := await _fire_until("use_right_arm", low, 60.0)
	await _frames(30)
	_check(_hits == low and _staggers == 0 and not _is_staggering(),
			"SMG %.0f m: %d of %d bullets landed (80%%) in %.1f s: no stagger (meter %.1f, staggers %d)" % [from_muzzle, _hits, data.magazine, time, _meter.value, _staggers])
	# Same magazine: go on with the 85% (the meter has not fallen: no gap above 1 s).
	time = await _fire_until("use_right_arm", high, 30.0)
	await _frames(10)
	_check(_hits == high and _staggers == 1 and _knocks == 0,
			"SMG %.0f m: %d of %d bullets landed (85%%): stagger (staggers %d, knock-downs %d)" % [from_muzzle, _hits, data.magazine, _staggers, _knocks])
	await _calm()


## Charges the beam rifle to `charge` (0 to 1), releases and waits for the end of the beam.
## `cut_after_hits` above 0: the enemy mech steps out of the beam after that many hit ticks.
func _beam_shot(charge: float, cut_after_hits: int = 0) -> void:
	var rifle := _weapons.right_weapon as BeamRifleWeapon
	Input.action_press("use_left_arm")
	var guard := 0
	while rifle.charge < charge and guard < 600:
		await _frames(1)
		guard += 1
	Input.action_release("use_left_arm")
	var start_pos := _dummy.global_position
	guard = 0
	await _frames(2)
	while (rifle.discharge_left > 0.0 or guard < 5) and guard < 400:
		await _frames(1)
		guard += 1
		if cut_after_hits > 0 and _hits >= cut_after_hits and _dummy.global_position == start_pos:
			_dummy.global_position = start_pos + Vector3(60.0, 0.0, 0.0)
	_dummy.global_position = start_pos
	await _frames(30)


func _beam_rifle() -> void:
	await _setup("beam_rifle", RANGE_NEAR)
	var data := _load("beam_rifle")
	var from_muzzle := _player.global_position.distance_to(_dummy.global_position)
	var cases := [
		["80% charge, whole beam hits", 0.8, 0, false],
		["95% charge, whole beam hits", 0.95, 0, false],
		["full charge, 90% of the ticks hit", 1.0, 18, false],
		["full charge, whole beam hits", 1.0, 0, true],
	]
	for entry: Array in cases:
		var rifle := _weapons.right_weapon as BeamRifleWeapon
		# Cool the rifle (no overheat between the shots).
		rifle.heat = 0.0
		rifle.overheated = false
		await _calm()
		await _beam_shot(entry[1], entry[2])
		var points := _meter.value
		var staggered := _staggers > 0
		_check(staggered == entry[3] and _knocks == 0 and _saw_stagger == entry[3] and not _saw_down,
				"Beam Rifle %.0f m, %s: %s (ticks that hit %d, staggers %d, knock-downs %d)" % [from_muzzle, entry[0],
				"stagger" if staggered else "no stagger", _hits, _staggers, _knocks])
		if not staggered:
			_check(points < data.stagger_points - 1.0, "Beam Rifle, %s: meter %.1f stays under 100" % [entry[0], points])
		await _calm()
