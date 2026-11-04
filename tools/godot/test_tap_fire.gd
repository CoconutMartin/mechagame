extends SceneTree
## Tap fire test (user request 2026-11-04: "autocannon should fire when triggered, when able; a quick tap should fire
## it"). The player mech holds the Auto Cannon (WeaponData.queue_tap) and uses the real input path
## (Input.action_press into MechInput, WeaponController, GunWeapon). It checks:
##  1. Control: with queue_tap off a 0.1 s tap fires nothing (the gun is not raised yet when the button goes up).
##  2. A 0.1 s tap fires one round once the gun is raised, the gun stays raised for it and lowers after it.
##  3. A tap while the gun cools down fires when the cooldown ends if that comes within GunWeapon.tap_queue_s, and
##     fires nothing late when the cooldown is longer.
##  4. Holding the button keeps the automatic fire (a second round after the cooldown) and a tap leaves no extra
##     round after the button is let go.
##  5. The Shoulder Cannon (own brace path) still fires on a tap.
##  6. The Heavy Rifle (queue_tap off) is not changed: a tap fires nothing, a hold fires.
##  7. An AI mech with the Auto Cannon fires.
## Times are game time (physics frames), so --fixed-fps 60 runs fast and still measures right.
## Exits with code 1 on any failure. Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_tap_fire.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const AUTO_CANNON := "res://data/weapons/auto_cannon.tres"
const SHOULDER_CANNON := "res://data/weapons/auto_cannon_shoulder.tres"
const HEAVY_RIFLE := "res://data/weapons/heavy_rifle.tres"

var _failures: int = 0
var _switcher: LoadoutSwitcher
var _shots: Array[float] = []


func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


## Game time in seconds (physics frames).
func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


func _seconds(seconds: float) -> void:
	await _frames(roundi(seconds * 60.0))


func _on_fired() -> void:
	_shots.append(_now())


func _finish() -> void:
	for action in ["use_left_arm", "use_right_arm", "fire_back_left", "fire_back_right"]:
		Input.action_release(action)
	print("TAP FIRE: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Puts a weapon in the right hand (nothing in the left) and counts its shots in _shots.
func _equip(file: String, back: String = "") -> MechWeapon:
	var loadout := _switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(file) as WeaponData
	loadout.weapon_left = null
	if back != "":
		loadout.back_left = load(back) as WeaponData
	_switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(90)
	var weapons := _switcher.mech.find_child("WeaponController", true, false) as WeaponController
	_shots.clear()
	var weapon := weapons.right_weapon
	if weapon != null:
		weapon.fired.connect(_on_fired)
	return weapon


## Presses the fire button for `seconds` and lets go. Returns the game time of the press.
func _tap(action: String, seconds: float) -> float:
	var at := _now()
	Input.action_press(action)
	await _seconds(seconds)
	Input.action_release(action)
	return at


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	TestMode.settings().free_energy = true
	_switcher = current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher

	var cannon := await _equip(AUTO_CANNON) as GunWeapon
	_check(cannon != null and cannon.data.queue_tap, "the player holds the Auto Cannon and it queues a tap")
	if cannon == null:
		_finish()
		return
	var weapons := cannon.controller
	var pose := weapons.weapon_pose

	# 1. Control: the old rule (queue_tap off) loses a quick tap.
	cannon.data.queue_tap = false
	await _tap("use_right_arm", 0.1)
	await _seconds(1.5)
	_check(_shots.is_empty(), "control: with queue_tap off a 0.1 s tap fires nothing (%d shots)" % _shots.size())
	await _seconds(2.0)
	cannon.data.queue_tap = true

	# 2. A quick tap fires one round once the gun is raised.
	_shots.clear()
	var ammo := cannon.ammo
	var t_tap := await _tap("use_right_arm", 0.1)
	var raised_in_wait := false
	for i in 90:
		await _frames(1)
		raised_in_wait = raised_in_wait or pose.aim_amount > 0.9
	_check(_shots.size() == 1, "a 0.1 s tap fires exactly one round (%d shots)" % _shots.size())
	if not _shots.is_empty():
		var delay := _shots[0] - t_tap
		_check(delay > 0.1 and delay < 0.6, "the round leaves when the gun is up, %.2f s after the press" % delay)
	_check(cannon.ammo == ammo - 1, "one round used (%d -> %d)" % [ammo, cannon.ammo])
	_check(raised_in_wait, "the gun stayed raised for the tap")
	_check(not cannon.is_busy(), "the gun no longer waits for a shot")
	await _seconds(3.0)
	_check(pose.aim_amount < 0.5, "the gun lowers again after the shot (aim %.2f)" % pose.aim_amount)
	_check(_shots.size() == 1, "no extra round after the tap (%d shots)" % _shots.size())

	# 3. A tap during the cooldown. The cooldown is 1 / fire_rate seconds from the last shot.
	await _seconds(maxf(1.0 / cannon.data.fire_rate - (_now() - _shots[0]), 0.0) + 0.5)
	_shots.clear()
	await _tap("use_right_arm", 0.1)
	await _seconds(1.0)
	_check(_shots.size() == 1, "a tap with the gun ready fires (%d shots)" % _shots.size())
	var first := _shots[0] if not _shots.is_empty() else _now()
	# 1.5 s into the cooldown: too early, nothing fires late.
	await _seconds(1.4 - (_now() - first))
	var count := _shots.size()
	await _tap("use_right_arm", 0.1)
	await _seconds(1.0)
	_check(_shots.size() == count, "a tap with the cooldown still long fires nothing, not even late (%d shots)" % _shots.size())
	# Cooldown ends within the queue time: fires at the end of the cooldown.
	var ends := first + 1.0 / cannon.data.fire_rate
	await _seconds(ends - _now() - 0.3)
	count = _shots.size()
	await _tap("use_right_arm", 0.1)
	await _seconds(1.0)
	_check(_shots.size() == count + 1, "a tap 0.3 s before the cooldown ends fires when it ends (%d shots)" % (_shots.size() - count))
	if _shots.size() > count:
		_check(absf(_shots[count] - ends) < 0.25, "...at the end of the cooldown (%.2f s off)" % (_shots[count] - ends))

	# 4. Holding keeps the automatic fire.
	await _seconds(5.0)
	_shots.clear()
	Input.action_press("use_right_arm")
	await _seconds(5.5)
	Input.action_release("use_right_arm")
	var held := _shots.size()
	_check(held >= 2, "holding the button keeps firing (%d shots in 5.5 s, cooldown %.1f s)" % [held, 1.0 / cannon.data.fire_rate])
	await _seconds(1.5)
	_check(_shots.size() == held, "no extra round after the hold ends (%d shots)" % _shots.size())

	# 5. Shoulder Cannon: a tap fires (own brace path).
	Input.action_release("use_right_arm")
	var holder := await _equip(HEAVY_RIFLE, SHOULDER_CANNON)
	var shoulder := _switcher.mech.find_child("WeaponController", true, false).back_left as MechWeapon
	_check(shoulder != null, "the player has a Shoulder Cannon")
	if shoulder != null:
		var shoulder_shots := [0]
		shoulder.fired.connect(func() -> void: shoulder_shots[0] += 1)
		await _tap("fire_back_left", 0.1)
		await _seconds(3.0)
		_check(shoulder_shots[0] == 1, "a tap fires the Shoulder Cannon (%d shots)" % shoulder_shots[0])

	# 6. The Heavy Rifle (queue_tap off): unchanged.
	if holder != null:
		_check(not holder.data.queue_tap, "the Heavy Rifle does not queue a tap")
		_shots.clear()
		await _seconds(1.0)
		await _tap("use_right_arm", 0.1)
		await _seconds(1.5)
		var tap_shots := _shots.size()
		await _seconds(1.0)
		Input.action_press("use_right_arm")
		await _seconds(1.5)
		Input.action_release("use_right_arm")
		print("INFO Heavy Rifle: a 0.1 s tap fired %d shots, a 1.5 s hold fired %d" % [tap_shots, _shots.size() - tap_shots])
		_check(_shots.size() - tap_shots >= 1, "the Heavy Rifle fires while held")

	# 7. An AI mech with the Auto Cannon.
	await _ai_fires()
	_finish()


func _ai_fires() -> void:
	var spawner: MechSpawner = null
	for node in get_nodes_in_group(&"mech_spawner"):
		if (node as MechSpawner).pilot == MechSpawner.Pilot.AI:
			spawner = node as MechSpawner
	_check(spawner != null, "the map has an AI spawner")
	if spawner == null:
		return
	spawner.set_right_weapon(load(AUTO_CANNON) as WeaponData)
	spawner.set_active(true)
	await _frames(60)
	var player := _switcher.mech
	var ai := spawner.mech
	var ai_weapons := ai.get_node("WeaponController") as WeaponController
	var weapon := ai_weapons.right_weapon
	_check(weapon != null and weapon.data.queue_tap, "the AI mech holds the Auto Cannon")
	if weapon == null:
		return
	var ai_shots := [0]
	weapon.fired.connect(func() -> void: ai_shots[0] += 1)
	ai.global_position = player.global_position + player.global_basis * Vector3(0.0, 0.0, -25.0)
	await _seconds(20.0)
	_check(ai_shots[0] >= 2, "the AI mech fires the Auto Cannon (%d shots in 20 s)" % ai_shots[0])
