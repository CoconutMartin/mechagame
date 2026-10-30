extends SceneTree
## Fist hold to charge (user request 2026-10-30): the right fist's button is held HOLD seconds (the charging clip
## must loop while held) and released at a target 8 m ahead: one punch lands, its damage grows with the hold. A short
## click (6 frames) punches at once with the base damage. Exits with code 1 on a failure. Headless:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_fist_charge.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"

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
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var click := await _punch(map, switcher, 6)
	var held := await _punch(map, switcher, 90)
	_check(click[0] == 1 and not click[1], "click: one hit (%s), no charging clip" % [click[2]])
	_check(held[0] == 1 and held[1], "hold 1.5 s: one hit (%s), charging clip looped" % [held[2]])
	_check(held[3] > click[3] * 1.4, "hold 1.5 s hits harder (%.0f against %.0f)" % [held[3], click[3]])
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## Holds RMB for frames and releases; returns [hits, charging clip seen, hit list, damage].
func _punch(map: Node, switcher: LoadoutSwitcher, frames: int) -> Array:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = null
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var weapons := player.get_node("WeaponController") as WeaponController
	var forward := weapons.mech_aim.aim_point - player.global_position
	forward.y = 0.0
	var target := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	target.position = player.global_position + forward.normalized() * 8.0
	map.add_child(target)
	target.remove_from_group(&"player")
	target.add_to_group(&"lockable")
	for child_name in ["MechInput", "CameraRig"]:
		var node := target.find_child(child_name, true, false)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for camera in node.find_children("*", "Camera3D", true, false):
				(camera as Camera3D).current = false
	target.look_at(player.global_position, Vector3.UP)
	await _frames(20)
	for key: String in target.health.max_hp:
		target.health.max_hp[key] = 100000.0
		target.health.hp[key] = 100000.0
	var hits: Array = []
	var total := [0.0]
	target.health.damaged.connect(func(part: String, amount: float) -> void:
		hits.append("%s %.0f" % [part, amount])
		total[0] += amount)
	var melee := player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	var looped := false
	Input.action_press("use_right_arm")
	for i in frames:
		await _frames(1)
		looped = looped or (melee.is_playing and melee._loop)
	Input.action_release("use_right_arm")
	for i in 150:
		await _frames(1)
	target.queue_free()
	await _frames(5)
	return [hits.size(), looped, hits, total[0]]
