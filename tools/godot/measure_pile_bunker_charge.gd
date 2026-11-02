extends SceneTree
## Pile Bunker charge and leap probe (user request 2026-11-02: a stable charge pose with the forearm flat, walk while
## charging, the leap punch, no fist in the face). The player holds the Pile Bunker (SIDE=R or L, BUNKER=data path) and:
##   stand: holds the button 90 frames standing still;
##   walk: keeps holding and walks forward (W) 120 frames;
##   leap: releases at a target TARGET m ahead (default 15) and follows the leap to the landing.
## Prints per phase: the forearm pitch (deg, 0 = level; the forearm bone to the hand bone), the largest frame-to-frame
## change of the fist place and of the elbow place in the torso frame (stability), the closest the hand bone comes to
## the head bone, the walked distance, and for the leap: flight time, peak height, ground distance, hit.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_pile_bunker_charge.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"

var _skeleton: Skeleton3D
var _side := "R"


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _bone(name: String) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(name))


func _run() -> void:
	_side = _env("SIDE", "R")
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var data := load(_env("BUNKER", "res://data/weapons/pile_bunker.tres")) as WeaponData
	loadout.weapon_right = data if _side == "R" else null
	loadout.weapon_left = data if _side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	_skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
	var weapons := player.get_node("WeaponController") as WeaponController
	var bunker := (weapons.right_weapon if _side == "R" else weapons.left_weapon) as PileBunkerWeapon
	var forward := weapons.mech_aim.aim_point - player.global_position
	forward.y = 0.0
	var target: Mech = null
	if _env("TARGET", "15") != "0":
		target = _make_target(map, player.global_position + forward.normalized() * float(_env("TARGET", "15")), player)
		await _frames(20)
		for key: String in target.health.max_hp:
			target.health.max_hp[key] = 100000.0
			target.health.hp[key] = 100000.0
	var hits: Array = []
	if target != null:
		target.health.damaged.connect(func(part: String, amount: float) -> void: hits.append("%s %.0f" % [part, amount]))
	var button := "use_right_arm" if _side == "R" else "use_left_arm"
	Input.action_press(button)
	await _frames(30)  # The pose comes in.
	await _phase("stand", 60, player)
	Input.action_press("move_forward")
	await _frames(20)
	await _phase("walk", 100, player)
	Input.action_release("move_forward")
	await _frames(30)
	print("  state before release: %d (POWER = 1)" % bunker.state)
	var start := player.global_position
	Input.action_release(button)
	var peak := start.y
	var air_frames := 0
	var left_floor := false
	var closest := INF
	for frame in 150:
		await _skeleton.skeleton_updated
		closest = minf(closest, _bone("hand_" + _side).origin.distance_to(_bone("head").origin))
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		if not player.is_on_floor():
			left_floor = true
			air_frames += 1
		elif left_floor:
			break
	var flat := player.global_position - start
	flat.y = 0.0
	print("leap: flight %.2f s, peak %.2f m, ground distance %.2f m (reach %.1f), hand-head closest %.2f m" % [
			air_frames / 60.0, peak - start.y, flat.length(), bunker.leap_reach(), closest])
	await _frames(60)
	print("hits: %s, state now %d" % [hits, bunker.state])
	quit()


func _phase(name: String, count: int, player: Mech) -> void:
	var start := player.global_position
	var pitch_min := INF
	var pitch_max := -INF
	var fist_jump := 0.0
	var elbow_jump := 0.0
	var closest := INF
	var last_fist := Vector3.INF
	var last_elbow := Vector3.INF
	for i in count:
		await _skeleton.skeleton_updated
		var torso := _bone("torso")
		var fore := _bone("forearm_" + _side)
		var hand := _bone("hand_" + _side)
		var dir := (hand.origin - fore.origin).normalized()
		var pitch := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
		pitch_min = minf(pitch_min, pitch)
		pitch_max = maxf(pitch_max, pitch)
		var fist := torso.affine_inverse() * hand.origin
		var elbow := torso.affine_inverse() * fore.origin
		if last_fist.is_finite():
			fist_jump = maxf(fist_jump, fist.distance_to(last_fist))
			elbow_jump = maxf(elbow_jump, elbow.distance_to(last_elbow))
		last_fist = fist
		last_elbow = elbow
		closest = minf(closest, hand.origin.distance_to(_bone("head").origin))
		await physics_frame
	var moved := player.global_position - start
	moved.y = 0.0
	print("%s: forearm pitch %.1f to %.1f deg, largest step fist %.3f m elbow %.3f m (torso frame), hand-head closest %.2f m, moved %.2f m" % [
			name, pitch_min, pitch_max, fist_jump, elbow_jump, closest, moved.length()])


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
