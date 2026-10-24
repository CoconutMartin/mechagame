extends SceneTree
## Shield raise, shoulder cannon brace and stop to fire test in the game (user requests 2026-10-22). The player
## mech uses the real input path (Input.action_press into MechInput, WeaponController, ShoulderBrace). It checks:
##  1. LMB with a shield in the left hand does nothing (user request 2026-10-24, MechShield.lmb_raises off).
##     With lmb_raises on, LMB raises it (MechShield.amount 0 to 1, the left hand goes to the guard place) and
##     releasing lowers it again (the pose the shield dash uses).
##  2. Shoulder cannon, standing: the first shot comes after the brace wind-up (ShoulderBrace.brace_time), with
##     the brace set and the mech still; a short tap still fires; the brace holds after the shot and recovers.
##  3. Shoulder cannon, walking (W held): the mech stops, the shot comes only when it is still, and W does not
##     move it while the cannon waits and fires.
##  4. Both cannons (Q and E) fire in the same frame.
##  5. Missile pod on the ground: the mech stops for the volley; in the air the pod fires and nothing stops.
##  6. Ground boost: the pod fires without the stop. The cannon key ends the boost: the mech stops at once and
##     snaps to the brace (user request 2026-10-24), then the cannon fires with the mech still.
##  7. Air: the cannon does not fire.
## Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_shoulder_stop.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const CANNON := "res://data/weapons/auto_cannon_shoulder.tres"
const POD_L := "res://data/weapons/missile_pod_l.tres"
const POD_R := "res://data/weapons/missile_pod_r.tres"
const HEX := "res://data/weapons/warden_shield.tres"
const SMALL := "res://data/weapons/small_shield.tres"
const SMG := "res://data/weapons/smg.tres"

var _failures: int = 0
var _switcher: LoadoutSwitcher
var _player: Mech
var _weapons: WeaponController
var _level: Node
var _shots: Array[int] = []
## Mech speed at the last shot (read in the fired signal, before any push back).
var _shot_speed: float = 0.0
var _frame: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		_frame += 1


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _release_all() -> void:
	for action in ["use_left_arm", "use_right_arm", "fire_back_left", "fire_back_right", "move_forward", "boost", "jump"]:
		Input.action_release(action)


func _finish() -> void:
	_release_all()
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _build(left: String, right: String, back_left: String, back_right: String) -> void:
	_release_all()
	var loadout := _switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_left = _data(left)
	loadout.weapon_right = _data(right)
	loadout.back_left = _data(back_left)
	loadout.back_right = _data(back_right)
	_switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(45)
	_player = _switcher.mech
	_weapons = _player.get_node("WeaponController") as WeaponController
	_shots.clear()
	for weapon: MechWeapon in [_weapons.back_left, _weapons.back_right]:
		if weapon != null:
			weapon.fired.connect(func() -> void:
				_shots.append(_frame)
				_shot_speed = _player.get_horizontal_speed())


func _data(path: String) -> WeaponData:
	return null if path == "" else load(path) as WeaponData


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	_level = current_scene
	for node in _level.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	_switcher = _level.get_node("LoadoutSwitcher") as LoadoutSwitcher
	await _shield(HEX)
	await _shield(SMALL)
	await _cannon_standing()
	await _cannon_walking()
	await _cannon_dual()
	await _pods()
	await _boost_and_air()
	_finish()


## 1. LMB raises the shield, release lowers it.
func _shield(path: String) -> void:
	await _build(path, SMG, "", "")
	var shield := _player.get_node("MechShield") as MechShield
	var pose := _player.find_child("ShieldPose", true, false) as ShieldPose
	var name := (load(path) as WeaponData).display_name
	_check(shield.enabled and shield.amount == 0.0, "%s: down at start" % name)
	var rest := pose.hand_target.position
	Input.action_press("use_left_arm")
	await _frames(60)
	_check(shield.amount == 0.0, "%s: LMB does nothing (amount %.2f)" % [name, shield.amount])
	Input.action_release("use_left_arm")
	await _frames(5)
	shield.lmb_raises = true
	Input.action_press("use_left_arm")
	var frames := 0
	while shield.amount < 0.999 and frames < 300:
		await _frames(1)
		frames += 1
	_check(frames > 10 and frames < 90, "%s: LMB raises it in %.2f s" % [name, frames / 60.0])
	await _frames(20)
	var up := pose.hand_target.position
	_check(pose.has_guard and up.distance_to(pose.raised.position) < 0.01 and up.distance_to(rest) > 0.5,
			"%s: the left hand goes to the guard place (%.2f, %.2f, %.2f)" % [name, up.x, up.y, up.z])
	Input.action_release("use_left_arm")
	frames = 0
	while shield.amount > 0.001 and frames < 300:
		await _frames(1)
		frames += 1
	await _frames(20)
	_check(frames < 60, "%s: release lowers it in %.2f s" % [name, frames / 60.0])
	_check(pose.hand_target.position.distance_to(rest) < 0.01, "%s: the left hand is back at its rest place" % name)


## 2. Standing: wind-up before the first shot, tap fires, the brace holds and recovers.
func _cannon_standing() -> void:
	await _build("", SMG, CANNON, CANNON)
	var brace := _weapons.shoulder_brace
	_check(brace != null and brace.brace_time >= 0.3 and brace.brace_time <= 0.5, "brace_time in 0.3 to 0.5 s (%.2f)" % brace.brace_time)
	await _frames(20)
	var press := _frame
	var place := _player.global_position
	Input.action_press("fire_back_left")
	var amount_at_shot := -1.0
	var speed_at_shot := -1.0
	var frames := 0
	while _shots.is_empty() and frames < 200:
		await _frames(1)
		frames += 1
		if not _shots.is_empty():
			amount_at_shot = brace.amount
			speed_at_shot = _shot_speed
	_check(not _shots.is_empty(), "standing: the cannon fires")
	var delay := (_shots[0] - press) / 60.0 if not _shots.is_empty() else -1.0
	_check(delay >= brace.brace_time - 0.03 and delay <= brace.brace_time + 0.12,
			"standing: first shot %.2f s after the key (wind-up %.2f s)" % [delay, brace.brace_time])
	_check(amount_at_shot >= 0.99 and speed_at_shot < 0.5, "standing: brace set (%.2f) and the mech still (%.2f m/s) at the shot" % [amount_at_shot, speed_at_shot])
	_check(absf(brace.feet_out - brace.feet_out_per_cannon) < 0.01, "one cannon: the feet stand %.2f m wider (0.5)" % brace.feet_out)
	await _frames(20)
	var back := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.BACK
	var pushed := (_player.global_position - place).dot(back)
	_check(absf(pushed - 0.5) < 0.12, "one cannon: the shot pushes the mech back %.2f m (0.5)" % pushed)
	Input.action_release("fire_back_left")
	_check(brace.amount > 0.99, "the brace holds after the shot (%.2f at %.2f s)" % [brace.amount, brace.hold_time - 0.33])
	await _frames(int(brace.recover_time * 60.0) + 40)
	_check(brace.amount < 0.01, "the brace recovers (%.2f)" % brace.amount)
	# A short tap (key down 6 frames) still fires. The cannon is on its 5 s cool down: use the right cannon.
	_shots.clear()
	Input.action_press("fire_back_right")
	await _frames(6)
	Input.action_release("fire_back_right")
	await _frames(int(brace.brace_time * 60.0) + 30)
	_check(_shots.size() == 1, "a short tap fires after the wind-up (%d shots)" % _shots.size())
	await _frames(int((brace.hold_time + brace.recover_time) * 60.0) + 20)


## 3. Walking: stop, then the shot; W does not move the mech while the cannon waits and fires.
func _cannon_walking() -> void:
	await _build("", SMG, CANNON, CANNON)
	var brace := _weapons.shoulder_brace
	Input.action_press("move_forward")
	await _frames(150)
	var walking := _player.get_horizontal_speed()
	_check(walking > 5.0, "walking at %.1f m/s" % walking)
	var press := _frame
	Input.action_press("fire_back_left")
	var speed_at_shot := -1.0
	var fastest_after_stop := 0.0
	var frames := 0
	var stopped_at := -1
	while frames < 240:
		await _frames(1)
		frames += 1
		var speed := _player.get_horizontal_speed()
		if stopped_at < 0 and speed < 0.5:
			stopped_at = _frame
		if stopped_at >= 0:
			fastest_after_stop = maxf(fastest_after_stop, speed)
		if not _shots.is_empty():
			speed_at_shot = _shot_speed
			break
	_check(not _shots.is_empty(), "walking: the cannon fires")
	var delay := (_frame - press) / 60.0
	_check(speed_at_shot >= 0.0 and speed_at_shot < 0.5, "walking: %.2f m/s at the shot, %.2f s after the key (the stop took %.2f s)" % [
			speed_at_shot, delay, (stopped_at - press) / 60.0 if stopped_at >= 0 else -1.0])
	# W still held: the mech does not walk on while the brace holds (the shot only pushes it back).
	var at_shot := _player.global_position
	var ahead := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.FORWARD
	await _frames(30)
	var walked := (_player.global_position - at_shot).dot(ahead)
	_check(_player.get_horizontal_speed() < 0.5 and walked < 0.05,
			"W held: the mech does not walk on while the cannon fires (%.2f m forward, %.2f m/s)" % [walked, _player.get_horizontal_speed()])
	Input.action_release("fire_back_left")
	Input.action_release("move_forward")
	await _frames(150)


## 4. Both cannons together.
func _cannon_dual() -> void:
	await _build("", SMG, CANNON, CANNON)
	await _frames(20)
	var place := _player.global_position
	Input.action_press("fire_back_left")
	Input.action_press("fire_back_right")
	await _frames(int(_weapons.shoulder_brace.brace_time * 60.0) + 40)
	_check(_shots.size() == 2 and _shots[0] == _shots[1], "dual: both cannons fire in the same frame (%s)" % str(_shots))
	_check(absf(_weapons.shoulder_brace.feet_out - 1.0) < 0.01, "dual: the feet stand %.2f m wider (1.0)" % _weapons.shoulder_brace.feet_out)
	var back := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.BACK
	var pushed := (_player.global_position - place).dot(back)
	_check(absf(pushed - 1.0) < 0.2, "dual: the shots push the mech back %.2f m (1.0)" % pushed)
	Input.action_release("fire_back_left")
	Input.action_release("fire_back_right")
	await _frames(100)


## 5. Pods: the volley stops the mech on the ground.
func _pods() -> void:
	await _build("", SMG, POD_L, POD_R)
	Input.action_press("move_forward")
	await _frames(150)
	var speed_before := _player.get_horizontal_speed()
	Input.action_press("fire_back_left")
	await _frames(10)
	Input.action_release("fire_back_left")
	await _frames(8)
	var braking := _player.is_bracing
	var slowest := 99.0
	for i in 60:
		await _frames(1)
		slowest = minf(slowest, _player.get_horizontal_speed())
	_check(speed_before > 5.0 and braking and slowest < 0.5, "pod on the ground: the mech stops for the volley (%.1f to %.2f m/s, bracing %s)" % [speed_before, slowest, braking])
	Input.action_release("move_forward")
	await _frames(100)
	# Standing: one missile (no lock) pushes the mech back 0.25 m.
	var place := _player.global_position
	_shots.clear()
	Input.action_press("fire_back_right")
	await _frames(10)
	Input.action_release("fire_back_right")
	await _frames(60)
	var back := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.BACK
	var pushed := (_player.global_position - place).dot(back)
	_check(_shots.size() == 1 and absf(pushed - 0.25) < 0.08, "pod: one missile pushes the mech back %.2f m (0.25)" % pushed)


## 6 and 7. Boost and air.
func _boost_and_air() -> void:
	await _build("", SMG, CANNON, POD_R)
	Input.action_press("move_forward")
	Input.action_press("boost")
	var frames := 0
	while not _player.is_boosting and frames < 400:
		await _frames(1)
		frames += 1
	_check(_player.is_boosting, "the mech boosts on the ground")
	await _frames(30)
	var speed := _player.get_horizontal_speed()
	Input.action_press("fire_back_right")
	await _frames(10)
	Input.action_release("fire_back_right")
	await _frames(20)
	_check(_player.is_boosting and not _player.is_bracing and _player.get_horizontal_speed() > speed * 0.8,
			"boosting: the pod fires and nothing stops the mech (%.1f m/s)" % _player.get_horizontal_speed())
	_shots.clear()
	speed = _player.get_horizontal_speed()
	Input.action_press("fire_back_left")
	await _frames(3)
	_check(not _player.is_boosting and not _player.is_running, "boosting: the cannon key ends the boost (boosting %s)" % _player.is_boosting)
	var brace_now := _weapons.shoulder_brace
	_check(_player.get_horizontal_speed() < 0.5 and brace_now.amount >= 0.999,
			"boosting: the mech stops at once and snaps to the brace (%.2f m/s, brace %.2f, 3 frames)" % [_player.get_horizontal_speed(), brace_now.amount])
	var waited := 0
	var still_at_shot := false
	while _shots.is_empty() and waited < 600:
		await _frames(1)
		waited += 1
		if not _shots.is_empty():
			still_at_shot = _player.get_horizontal_speed() < 0.5
	_check(not _shots.is_empty() and still_at_shot,
			"boosting: the mech stops from %.1f m/s and the cannon fires still (%d shots after %d frames)" % [speed, _shots.size(), waited])
	Input.action_release("fire_back_left")
	Input.action_release("boost")
	Input.action_release("move_forward")
	await _frames(240)
	# Air: lift the mech. The cannon does not fire; the pod fires and the mech is not braced.
	_shots.clear()
	_player.global_position += Vector3.UP * 80.0
	_player.velocity = Vector3.ZERO
	await _frames(5)
	Input.action_press("fire_back_left")
	await _frames(40)
	var air := not _player.is_on_floor()
	_check(air and _shots.is_empty() and not _player.is_bracing, "air: the cannon does not fire and no brace (%d shots)" % _shots.size())
	Input.action_release("fire_back_left")
	await _frames(5)
	Input.action_press("fire_back_right")
	await _frames(10)
	Input.action_release("fire_back_right")
	await _frames(20)
	_check(not _player.is_on_floor() and _shots.size() == 1 and not _player.is_bracing, "air: the pod fires (%d volley), no brace (on floor %s, bracing %s)" % [_shots.size(), _player.is_on_floor(), _player.is_bracing])
