extends SceneTree
## Pile Bunker hit test (2026-10-26, new twin-stake model). The player holds the Pile Bunker in the right or the left
## hand, powers up (the button held POWER_FRAMES), releases, charges at a target mech in the crosshair and punches. Each
## case must hit the target once, fire the stakes out by stake_travel and bring them back in. Exits with code 1 on a
## failure. A drill stake (spin_speed_deg > 0, Pile Bunker 2) must spin at full speed at the release and stop after the
## hit. Claws (claw_paths, Pile Bunker 4) must be closed at the release, open fully after the hit or the miss, and
## close again at rest; telescoping tips (claw_tip_paths, Pile Bunker 4B) must be back in at rest. The "miss" case has the target out of reach: no hit, no stake shot, the drill and the claws
## still react. BUNKER=res://data/weapons/pile_bunker_2.tres tests another Pile Bunker. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_pile_bunker_hit.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
var BUNKER := OS.get_environment("BUNKER") if OS.has_environment("BUNKER") else "res://data/weapons/pile_bunker.tres"
const POWER_FRAMES := 60
const MAX_FRAMES := 480

## Cases: name, side ("R" or "L"), target distance in m.
const CASES := [["right_12", "R", 12.0], ["right_20", "R", 20.0], ["left_12", "L", 12.0], ["left_20", "L", 20.0],
		["both_right_12", "BR", 12.0], ["both_left_12", "BL", 12.0], ["right_miss", "R", 45.0]]

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
	for case: Array in CASES:
		await _play(map, switcher, case)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _play(map: Node, switcher: LoadoutSwitcher, case: Array) -> void:
	var side: String = case[1]
	# "BR" / "BL": a Pile Bunker in both hands, the right or the left one attacks.
	var both := side.begins_with("B")
	side = side.right(1)
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load(BUNKER) if side == "R" or both else null
	loadout.weapon_left = load(BUNKER) if side == "L" or both else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var weapons := player.get_node("WeaponController") as WeaponController
	var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
	# NUMBER: the punch clip to test (PileBunkerWeapon.clip_number).
	if OS.has_environment("NUMBER"):
		bunker.clip_number = int(OS.get_environment("NUMBER"))
	# The target stands on the flat line to the blue ring (the crosshair is above the center and a little right).
	var forward := weapons.mech_aim.aim_point - player.global_position
	forward.y = 0.0
	var target := _make_target(map, player.global_position + forward.normalized() * float(case[2]), player)
	await _frames(20)
	for key: String in target.health.max_hp:
		target.health.max_hp[key] = 100000.0
		target.health.hp[key] = 100000.0
	var hits: Array = []
	target.health.damaged.connect(func(part: String, amount: float) -> void: hits.append("%s %.0f" % [part, amount]))
	var stake := bunker._stake
	var rest := stake.position
	var button := "use_right_arm" if side == "R" else "use_left_arm"
	Input.action_press(button)
	await _frames(POWER_FRAMES)
	if OS.get_environment("PB_TRACE") != "":
		var input := player.find_child("MechInput", true, false)
		print("  state=%d held=%s fire=%s cam_free=%s may=%s" % [bunker.state, bunker.trigger_held, input.fire_held, input.camera_rig.free_camera_on if input.camera_rig else null, weapons._may_fire(bunker)])
	var spin_at_release := bunker._spin
	var angle_at_release := bunker._spin_angle
	Input.action_release(button)
	var most_out := 0.0
	var spin_after_hit := -1.0
	var claw_at_release := bunker._claw_open
	var claw_most := 0.0
	var miss: bool = String(case[0]).ends_with("miss")
	var fired_frame := -1
	for frame in MAX_FRAMES:
		await _frames(1)
		most_out = maxf(most_out, rest.z - stake.position.z)
		claw_most = maxf(claw_most, bunker._claw_open)
		if (bunker.has_fired or (miss and (bunker._clip_missed or bunker.state == PileBunkerWeapon.State.RECOVER))) and fired_frame < 0:
			fired_frame = frame
		if fired_frame >= 0 and frame == fired_frame + int(bunker.spin_down_time * 60.0) + 2:
			spin_after_hit = bunker._spin
		if OS.get_environment("PB_TRACE") != "" and frame % 4 == 0 and bunker.state != PileBunkerWeapon.State.IDLE:
			print("  f=%d state=%d nose=%s aim=%s target=%s player=%s" % [frame, bunker.state, bunker._nose.global_position.snappedf(0.01), bunker._aim_point.snappedf(0.01), target.global_position.snappedf(0.01), player.global_position.snappedf(0.01)])
		if frame > 60 and bunker.state == PileBunkerWeapon.State.IDLE and bunker.stake_out == 0.0:
			break
	await _frames(40)
	if miss:
		_check(hits.is_empty() and most_out == 0.0, "%s: no hit and no stake shot, hits=%s" % [case[0], hits])
	else:
		_check(hits.size() == 1, "%s: one hit on the target, hits=%s" % [case[0], hits])
		_check(absf(most_out - bunker.stake_travel) < 0.05, "%s: stakes out %.2f m (stake_travel %.2f)" % [case[0], most_out, bunker.stake_travel])
	_check(stake.position.distance_to(rest) < 0.001, "%s: stakes back in" % case[0])
	if bunker.spin_speed_deg > 0.0:
		_check(spin_at_release > 0.99 and angle_at_release != 0.0, "%s: drill spins at the release (%.2f)" % [case[0],
				spin_at_release])
		_check(spin_after_hit == 0.0, "%s: drill stopped after the hit or miss (%.2f)" % [case[0], spin_after_hit])
	if not bunker.claw_paths.is_empty():
		_check(claw_at_release == 0.0 and claw_most > 0.99 and bunker._claw_open == 0.0,
				"%s: claws closed at the release (%.2f), open after the hit or miss (%.2f), closed at rest (%.2f)" % [
				case[0], claw_at_release, claw_most, bunker._claw_open])
	for i in bunker._claw_tips.size():
		_check(bunker._claw_tips[i].position.distance_to(bunker._tip_rest[i]) < 0.001, "%s: claw tip %d back in" % [case[0], i])
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
