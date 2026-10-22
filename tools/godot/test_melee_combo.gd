extends SceneTree
## Melee combo test in the game (user report 2026-10-22, "melee combo is not working using baton, war hammer,
## empty hand"). The player mech (baton, War Hammer or empty hands) clicks the mouse button like a person
## does (a click of CLICK_FRAMES, a new click every `interval` seconds, from the start of the first click)
## against a target mech in the crosshair, and the test counts the swings of the chain. Every weapon must play
## all 3 swings of the chain (each swing hits once), at every click interval. Also checks that the empty hand
## shows no Fist block model and that the hand is visible. Exits with code 1 on any failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_melee_combo.gd
## Environment: COMBO_ONLY (part of a case name, for example "fist"), COMBO_DISTANCE (m, default 8).

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
const HAMMER := "res://data/weapons/hammer.tres"
const BATON := "res://data/weapons/baton.tres"
## Physics frames a click is held.
const CLICK_FRAMES := 6
## Longest case (physics frames).
const MAX_FRAMES := 900

## Cases: name, weapon ("baton", "hammer", "fist_r" = empty hands, RMB, "fist_l" = LMB), move key ("" = none),
## seconds between the clicks, and optional: the target distance in m (0 = no target; swings hit nothing).
const CASES := [
	["baton_0.25", "baton", "", 0.25],
	["baton_0.5", "baton", "", 0.5],
	["baton_0.9", "baton", "", 0.9],
	["baton_W_0.4", "baton", "move_forward", 0.4],
	["hammer_0.25", "hammer", "", 0.25],
	["hammer_0.5", "hammer", "", 0.5],
	["hammer_1.0", "hammer", "", 1.0],
	["hammer_D_0.5", "hammer", "move_right", 0.5],
	["fist_r_0.2", "fist_r", "", 0.2],
	["fist_r_0.4", "fist_r", "", 0.4],
	["fist_r_0.7", "fist_r", "", 0.7],
	["fist_l_0.4", "fist_l", "", 0.4],
	["fist_l_W_0.4", "fist_l", "move_forward", 0.4],
	# No target at all (user report 2026-10-22: a chain needed a hit): the swings hit nothing and chain anyway.
	["baton_air_0.5", "baton", "", 0.5, 0.0],
	["hammer_air_0.5", "hammer", "", 0.5, 0.0],
	["hammer_D_air_0.5", "hammer", "move_right", 0.5, 0.0],
	["fist_r_air_0.4", "fist_r", "", 0.4, 0.0],
	["fist_l_air_0.4", "fist_l", "", 0.4, 0.0],
	# A target out of reach (the swing misses it).
	["hammer_far_0.5", "hammer", "", 0.5, 40.0],
]

var _failures: int = 0


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
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var only := OS.get_environment("COMBO_ONLY")
	var distance := 8.0
	if OS.get_environment("COMBO_DISTANCE") != "":
		distance = float(OS.get_environment("COMBO_DISTANCE"))
	for case: Array in CASES:
		if only != "" and not (case[0] as String).contains(only):
			continue
		await _play(map, switcher, case, float(case[4]) if case.size() > 4 else distance)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _play(map: Node, switcher: LoadoutSwitcher, case: Array, distance: float) -> void:
	var weapon: String = case[1]
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_left = null
	match weapon:
		"baton":
			loadout.weapon_right = load(BATON)
		"hammer":
			loadout.weapon_right = load(HAMMER)
		_:
			loadout.weapon_right = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
	var target: Mech = null
	var hits: Array = []
	if distance > 0.0:
		target = _make_target(map, player.global_position + forward * distance, player)
		await _frames(20)
		for key: String in target.health.max_hp:
			target.health.max_hp[key] = 100000.0
			target.health.hp[key] = 100000.0
		target.health.damaged.connect(func(part: String, amount: float) -> void: hits.append("%s %.0f" % [part, amount]))
	var melee := player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	if weapon.begins_with("fist"):
		_check_bare_hands(player, case[0])
		await _frames(30)
		_check(control.hand_right.mode == MechHand.Mode.RELAXED and control.hand_left.mode == MechHand.Mode.RELAXED,
				"%s: the bare hands rest relaxed (open), modes R=%d L=%d" % [case[0], control.hand_right.mode, control.hand_left.mode])
	var button := "use_left_arm" if weapon == "fist_l" else "use_right_arm"
	var move_key: String = case[2]
	if move_key != "":
		Input.action_press(move_key)
	await _frames(3)
	var interval_frames := int(float(case[3]) * 60.0)
	var swings: Array[String] = []
	var last_attack: MeleeAttack = null
	var last_count := 0
	var clicks := 0
	var frame := 0
	var after_end := 0
	var next_click := 0
	var fist_in_punch := false
	while frame < MAX_FRAMES:
		# A click is CLICK_FRAMES long; the next one starts interval_frames after this one began.
		if frame == next_click and clicks < 6:
			clicks += 1
			next_click += interval_frames
			Input.action_press(button)
		elif clicks > 0 and frame == next_click - interval_frames + CLICK_FRAMES:
			Input.action_release(button)
		await _frames(1)
		frame += 1
		if OS.get_environment("COMBO_TRACE") != "" and (frame % 6 == 0 or frame == next_click):
			print("  f=%d play=%s n=%d landed=%s since=%.2f t=%.2f/%.2f queue=%d cd=%.1f held=%s" % [frame, melee.is_playing, melee.chain_count,
					melee._landed, melee._since_hit, melee._time, melee._end_time, melee._queue.size(), melee.get_cooldown_left(),
					Input.is_action_pressed(button)])
		if melee.is_playing and weapon.begins_with("fist") and control.hand_right.mode == MechHand.Mode.FIST \
				and control.hand_left.mode == MechHand.Mode.FIST:
			fist_in_punch = true
		if melee.is_playing and (melee._attack != last_attack or melee.chain_count != last_count):
			last_attack = melee._attack
			last_count = melee.chain_count
			swings.append(last_attack.resource_path.get_file().get_basename())
		if swings.size() > 0 and not melee.is_playing:
			after_end += 1
			if after_end > 120:
				break
	Input.action_release(button)
	if move_key != "":
		Input.action_release(move_key)
	var expected_hits := 3 if target != null and distance < 30.0 else 0
	_check(swings.size() == 3 and hits.size() == expected_hits, "%s: swings=%s hits=%s (expected %d) clicks=%d" % [case[0], swings, hits, expected_hits, clicks])
	if weapon.begins_with("fist"):
		_check(fist_in_punch, "%s: both hands close to a fist during the punch" % case[0])
		await _frames(60)
		_check(control.hand_right.mode == MechHand.Mode.RELAXED, "%s: the hand opens again after the punch" % case[0])
	if target != null:
		target.queue_free()
	await _frames(5)


## A mech in the crosshair: no input, no camera, a lockable enemy like the spawner's.
func _make_target(map: Node, place: Vector3, player: Mech) -> Mech:
	var target := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	target.position = place
	map.add_child(target)
	target.remove_from_group(&"player")
	target.add_to_group(&"lockable")
	for child_name in ["MechInput", "CameraRig"]:
		var node := target.find_child(child_name, true, false)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is Node3D:
				for camera in node.find_children("*", "Camera3D", true, false):
					(camera as Camera3D).current = false
	target.look_at(player.global_position, Vector3.UP)
	return target


## An empty hand shows the mech's own jointed hand and no Fist block model (user report 2026-10-22).
func _check_bare_hands(player: Mech, name: String) -> void:
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	_check(control != null and is_instance_valid(control.hand_right) and control.hand_right.visible \
			and is_instance_valid(control.hand_left) and control.hand_left.visible, "%s: both jointed hands are visible" % name)
	var weapons := player.get_node("WeaponController") as WeaponController
	for fist: MeleeWeapon in [weapons.right_fist, weapons.left_fist]:
		var model := fist.get_model() if fist != null else null
		var blocks := 0
		if model != null:
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				if (mesh as MeshInstance3D).visible and (mesh as MeshInstance3D).is_visible_in_tree():
					blocks += 1
		_check(blocks == 0, "%s: a fist shows %d mesh(es), 0 expected" % [name, blocks])
