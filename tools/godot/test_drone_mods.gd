extends SceneTree
## Drone aux mods test (phase B, user design 2026-10-31: "(a) double drone usage: the drone comes back and can be
## relaunched; (b) launch all drones simultaneously: all drones get destroyed after"; aux mods are interchangeable
## aux equipment in the back pack's 1 aux slot).
##   Catalog: the garage aux list has the pulse scans and both drone mods.
##   Swarm: with the swarm mod in the aux slot (no pulse scan then), one launch sends all 6 drones; none comes back.
##   Recall: a pair attacks a dummy 100 m ahead, flies back and docks (the drone model on the pack at its dock again,
##   6 on the pack); a drone on its second flight explodes after its attack; a returning drone shot down is gone.
##   The HUD line names the mod. No drone step passes through a wall or building.
## Exits with code 1 on a failure.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_drone_mods.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_drone.tres"
const RECALL := "res://data/equipment/drone_recall.tres"
const SWARM := "res://data/equipment/drone_swarm.tres"

var _failures: int = 0
var _through: int = 0
var _last_pos: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		_track()


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _track() -> void:
	if current_scene == null:
		return
	var space := current_scene.get_viewport().world_3d.direct_space_state
	for node in get_nodes_in_group(&"attack_drones"):
		var drone := node as AttackDrone
		var now := drone.global_position
		var id := drone.get_instance_id()
		if _last_pos.has(id) and (_last_pos[id] as Vector3).distance_to(now) > 0.001:
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(_last_pos[id], now, 17)).is_empty():
				_through += 1
		_last_pos[id] = now


## Builds the player mech with the Drone Pack and aux in its slot. Returns the new mech.
func _build(aux: EquipmentData) -> Mech:
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = load(PACK) as BackPackPart
	var items: Array[EquipmentData] = []
	if aux != null:
		items.append(aux)
	loadout.aux = items
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	return switcher.mech


func _dummy(place: Vector3) -> TargetDummy:
	var dummy := TargetDummy.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 10.0, 4.0)
	shape.shape = box
	shape.position.y = 5.0
	dummy.add_child(shape)
	dummy.collision_layer = 2 | 8
	dummy.max_hp = 100000.0
	current_scene.add_child(dummy)
	dummy.global_position = place
	return dummy


## Waits until none of drones is in the air (or frames run out). Returns the frames waited.
func _wait_gone(drones: Array[AttackDrone], frames: int) -> int:
	for i in frames:
		await _frames(1)
		if drones.all(func(d: Variant) -> bool: return not is_instance_valid(d) or (d as Node).is_queued_for_deletion()):
			return i
	return frames


func _run() -> void:
	var catalog := load("res://data/garage_catalog.tres") as GarageCatalog
	var recall := load(RECALL) as DroneModData
	var swarm := load(SWARM) as DroneModData
	_check(recall in catalog.aux_items and swarm in catalog.aux_items and catalog.aux_items.size() == 5,
			"the garage aux list has 3 pulse scans and both drone mods")
	_check(recall.kind == DroneModData.Kind.RECALL and recall.flights_per_drone == 2
			and swarm.kind == DroneModData.Kind.SWARM, "Drone Recall (2 flights per drone) and Drone Swarm")
	_check((load(PACK) as BackPackPart).aux_slots == 1, "the Drone Pack keeps 1 aux slot")
	change_scene_to_file(MAP)
	await _frames(30)
	await _swarm_test(swarm)
	await _recall_test(recall)
	_check(_through == 0, "no drone step passed through a wall or building (%d)" % _through)
	print("drone mods test: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _swarm_test(swarm: DroneModData) -> void:
	var mech: Mech = await _build(swarm)
	var launcher := DroneLauncher.find(mech)
	_check(launcher != null and launcher.get_mod() == swarm, "swarm: the mod is in the aux slot")
	_check(AuxMount.find_device(mech, PulseScanner) == null, "swarm: no pulse scan with the mod (1 aux slot)")
	var status := root.find_child("DroneStatus", true, false) as DroneStatus
	await _frames(2)
	_check(status != null and status.text.contains("SWARM"), "swarm: HUD line %s" % (status.text if status else "none"))
	var aim := mech.get_node("MechAim") as MechAim
	var flat := Vector3(aim.aim_direction.x, 0.0, aim.aim_direction.z).normalized()
	var dummy := _dummy(mech.global_position + flat * 100.0)
	await _frames(5)
	var hp_before := dummy.hp
	var count := launcher.launch(dummy)
	_check(count == 6 and launcher.docked_count() == 0, "swarm: one launch sends all 6 drones (%d)" % count)
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	var back := [0]
	for d in drones:
		d.docked.connect(func(_x: AttackDrone, _m: Node3D) -> void: back[0] += 1)
	var waited := await _wait_gone(drones, 600)
	print("swarm: all gone after %.2f s, dummy damage %.0f" % [waited / 60.0, hp_before - dummy.hp])
	_check(waited < 600 and back[0] == 0 and launcher.docked_count() == 0, "swarm: all drones are destroyed after")
	_check(dummy.hp < hp_before, "swarm: the drones hit the dummy")
	dummy.queue_free()


func _recall_test(recall: DroneModData) -> void:
	var mech: Mech = await _build(recall)
	var launcher := DroneLauncher.find(mech)
	_check(launcher != null and launcher.get_mod() == recall, "recall: the mod is in the aux slot")
	var status := root.find_child("DroneStatus", true, false) as DroneStatus
	await _frames(2)
	_check(status != null and status.text.contains("RECALL"), "recall: HUD line %s" % (status.text if status else "none"))
	var aim := mech.get_node("MechAim") as MechAim
	var flat := Vector3(aim.aim_direction.x, 0.0, aim.aim_direction.z).normalized()
	var dummy := _dummy(mech.global_position + flat * 100.0)
	await _frames(5)
	# 1. A pair attacks and comes back.
	var hp_before := dummy.hp
	var models: Array[Node3D] = [launcher.docked_left[0], launcher.docked_right[0]]
	var homes: Array[Transform3D] = [models[0].transform, models[1].transform]
	var parents: Array[Node] = [models[0].get_parent(), models[1].get_parent()]
	_check(launcher.launch(dummy) == 2, "recall: a pair launches")
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	var returned := [false, false]
	var waited := 0
	for i in 900:
		await _frames(1)
		for k in 2:
			if is_instance_valid(drones[k]) and drones[k].phase == AttackDrone.Phase.RETURN:
				returned[k] = true
		waited = i
		if launcher.docked_count() == 6:
			break
	print("recall: back on the pack after %.2f s, dummy damage %.0f" % [waited / 60.0, hp_before - dummy.hp])
	_check(dummy.hp < hp_before, "recall: the pair hit the dummy")
	_check(returned[0] and returned[1], "recall: both drones fly back after the attack")
	_check(launcher.docked_count() == 6, "recall: both drones dock again (%d on the pack)" % launcher.docked_count())
	for k in 2:
		var model := models[k]
		_check(is_instance_valid(model) and model.get_parent() == parents[k] and model.transform.is_equal_approx(homes[k]),
				"recall: drone %d is back at its dock" % k)
	# 2. Their second flight: they do not come back.
	launcher.docked_left.erase(models[0])
	launcher.docked_left.push_front(models[0])
	launcher.docked_right.erase(models[1])
	launcher.docked_right.push_front(models[1])
	_check(launcher.launch(dummy) == 2, "recall: the same pair launches again")
	drones = launcher.flying.duplicate()
	_check(not drones[0].return_home and not drones[1].return_home, "recall: on the second flight they will not return")
	await _wait_gone(drones, 600)
	await _frames(2)
	_check(launcher.docked_count() == 4, "recall: after the second flight they are gone (%d on the pack)"
			% launcher.docked_count())
	# 3. A returning drone shot down is gone.
	_check(launcher.launch(dummy) == 2, "recall: a fresh pair launches")
	drones = launcher.flying.duplicate()
	var hit := false
	for i in 600:
		await _frames(1)
		if not hit and is_instance_valid(drones[0]) and drones[0].phase == AttackDrone.Phase.RETURN:
			drones[0].on_hit(drones[0].hp + 1.0)
			hit = true
		if launcher.flying.is_empty() and hit:
			break
	await _frames(2)
	_check(hit and launcher.docked_count() == 3, "recall: a drone shot down on its way back is gone (%d on the pack)"
			% launcher.docked_count())
	dummy.queue_free()
