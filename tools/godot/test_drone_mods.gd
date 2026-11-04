extends SceneTree
## Drone aux mods test (phase B, user design 2026-10-31: "(a) double drone usage: the drone comes back and can be
## relaunched; (b) launch all drones simultaneously: all drones get destroyed after"; aux mods are interchangeable
## aux equipment in the back pack's 1 aux slot).
##   Catalog: the garage aux list has the pulse scans and both drone mods.
##   Swarm: with the swarm mod in the aux slot (no pulse scan then), one launch sends all 6 drones; none comes back.
##   Recall: a pair attacks a dummy 100 m ahead (3 bursts, a move after each; the last move is the way home),
##   flies back and docks (the drone model on the pack at its dock again,
##   6 on the pack); a drone on its second flight explodes after its attack; a returning drone shot down is gone.
##   The HUD line names the mod. User 2026-11-04 ("for now"): no cool down, unlimited use (the pack stays full, the
##   copies fly), a launch while drones are in the air; the old rules are tested again with the DroneData switches
##   (unlimited, cooldown_s, one_launch_at_a_time) set back. Way home (user 2026-11-04: "drones clip through the body
##   when returning"): the closest a returning drone's center gets to any hitbox of the mech (the back pack only
##   until 1.5 m from the dock) stays over the hit radius, with the old straight way for comparison, with the mech
##   turning, and for targets ahead, beside, close and behind. A returning drone is hit like one in the fire phase (a
##   Bullet at it destroys it). Squad (user 2026-11-04: "drones switching places and firing should be
##   synchronized"): the six swarm drones start each burst within 0.05 s and hop within 0.05 s.
## Exits with code 1 on a failure.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_drone_mods.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_drone.tres"
const RECALL := "res://data/equipment/drone_recall.tres"
const SWARM := "res://data/equipment/drone_swarm.tres"

var _failures: int = 0
var _through: int = 0
var _last_pos: Dictionary = {}
## Way home: the closest a returning drone's center got to a mech hitbox (m) and to which part, and to the back pack
## farther than 1.5 m from the dock.
var _clear_min: float = INF
var _clear_part: String = ""
var _pack_min: float = INF


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		_track()


## The launcher ready for the next test launch: the cool down skipped (its own check is in the classic rules part).
func _armed(launcher: DroneLauncher) -> DroneLauncher:
	if launcher != null:
		launcher.cooldown_left = 0.0
	return launcher


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
		var before: Vector3 = _last_pos.get(id, now)
		if before.distance_to(now) > 0.001:
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(before, now, 17)).is_empty():
				_through += 1
		if drone.phase == AttackDrone.Phase.RETURN and is_instance_valid(drone.launcher_mech) \
				and is_instance_valid(drone.dock):
			# Sub-steps: a fast drone moves over a meter a frame.
			for i in range(1, 9):
				_sample_clearance(before.lerp(now, i / 8.0), drone)
		_last_pos[id] = now


## Updates the closest distance from point p to the mech's hitboxes. The back pack counts only farther than 1.5 m
## from the dock (the last approach goes into it).
func _sample_clearance(p: Vector3, drone: AttackDrone) -> void:
	var dock_distance := p.distance_to(drone.dock.global_position)
	var hitboxes := drone.launcher_mech.health.hitboxes
	for key: String in hitboxes:
		for hitbox: PartHitbox in hitboxes[key]:
			if not is_instance_valid(hitbox):
				continue
			for child in hitbox.get_children():
				var shape_node := child as CollisionShape3D
				if shape_node == null or not shape_node.shape is BoxShape3D:
					continue
				var d := _box_distance(shape_node, p)
				if key == "Back Pack":
					if dock_distance > 1.5:
						_pack_min = minf(_pack_min, d)
				elif d < _clear_min:
					_clear_min = d
					_clear_part = key


## Distance from point p to the surface of a box shape (negative inside).
static func _box_distance(shape_node: CollisionShape3D, p: Vector3) -> float:
	var half := (shape_node.shape as BoxShape3D).size * 0.5
	var local := shape_node.global_transform.affine_inverse() * p
	var q := local.abs() - half
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


func _clear_reset() -> void:
	_clear_min = INF
	_clear_part = ""
	_pack_min = INF


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


## Watches drones until all are gone. Returns the ages (the drone's own clock; all launched together) at which each
## drone started burst k and its hop k: {"bursts": [[age per drone, ...] per k], "hops": [...]}.
func _watch_sync(drones: Array[AttackDrone], frames: int) -> Dictionary:
	var bursts: Array = [[], [], []]
	var hops: Array = [[], [], []]
	var seen_burst: Dictionary = {}
	var seen_hop: Dictionary = {}
	for f in frames:
		await _frames(1)
		var alive := false
		for d in drones:
			if not is_instance_valid(d) or d.is_queued_for_deletion():
				continue
			alive = true
			var id := d.get_instance_id()
			if d.phase == AttackDrone.Phase.FIRE and d.step == AttackDrone.Step.BURST \
					and int(seen_burst.get(id, 0)) < d.bursts_fired and d.bursts_fired <= 3:
				seen_burst[id] = d.bursts_fired
				bursts[d.bursts_fired - 1].append(d.age)
			if d.phase == AttackDrone.Phase.FIRE and d.step == AttackDrone.Step.SHIFT \
					and int(seen_hop.get(id, 0)) < d.bursts_fired and d.bursts_fired <= 3:
				seen_hop[id] = d.bursts_fired
				hops[d.bursts_fired - 1].append(d.age)
		if not alive:
			break
	return {"bursts": bursts, "hops": hops}


## Largest gap (s) between the start times of one event over the drones, over all k with 2 or more drones.
static func _sync_spread(times: Array) -> float:
	var worst := 0.0
	for list: Array in times:
		if list.size() >= 2:
			worst = maxf(worst, float(list.max()) - float(list.min()))
	return worst


static func _ages(list: Array) -> String:
	var parts: PackedStringArray = []
	for age: float in list:
		parts.append("%.2f" % age)
	return "[" + ", ".join(parts) + "]"


func _run() -> void:
	var catalog := load("res://data/garage_catalog.tres") as GarageCatalog
	var recall := load(RECALL) as DroneModData
	var swarm := load(SWARM) as DroneModData
	_check(recall in catalog.aux_items and swarm in catalog.aux_items and catalog.aux_items.size() == 5,
			"the garage aux list has 3 pulse scans and both drone mods")
	_check(recall.kind == DroneModData.Kind.RECALL and recall.flights_per_drone == 2
			and swarm.kind == DroneModData.Kind.SWARM, "Drone Recall (2 flights per drone) and Drone Swarm")
	var pack := load(PACK) as BackPackPart
	_check(pack.aux_slots == 1, "the Drone Pack keeps 1 aux slot")
	var data := pack.drone
	# User 2026-11-04, "for now": no cool down, unlimited use, a launch while drones fly.
	_check(is_zero_approx(data.cooldown_s) and data.unlimited and not data.one_launch_at_a_time,
			"drone data: no cool down, unlimited, no one-at-a-time rule (%.1f, %s, %s)"
			% [data.cooldown_s, data.unlimited, data.one_launch_at_a_time])
	change_scene_to_file(MAP)
	await _frames(30)
	await _swarm_test(swarm)
	await _recall_test(recall)
	await _classic_rules_test(recall)
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
	# Unlimited (user 2026-11-04): copies fly, the pack stays full.
	_check(count == 6 and launcher.docked_count() == 6, "swarm: one launch sends all 6 drones, the pack stays full (%d, %d)"
			% [count, launcher.docked_count()])
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	var squad: DroneSquad = drones[0].squad if not drones.is_empty() else null
	var one_squad := squad != null
	for d in drones:
		one_squad = one_squad and d.squad == squad
	_check(one_squad, "swarm: all 6 drones are one squad")
	var back := [0]
	for d in drones:
		d.docked.connect(func(_x: AttackDrone, _m: Node3D) -> void: back[0] += 1)
	var sync := await _watch_sync(drones, 600)
	var bursts: Array = sync["bursts"]
	var hops: Array = sync["hops"]
	var burst_spread := _sync_spread(bursts)
	var hop_spread := _sync_spread(hops)
	print("swarm: burst starts %s %s %s, hop starts %s %s %s" % [_ages(bursts[0]), _ages(bursts[1]), _ages(bursts[2]),
			_ages(hops[0]), _ages(hops[1]), _ages(hops[2])])
	print("swarm: burst start spread %.3f s, hop start spread %.3f s" % [burst_spread, hop_spread])
	_check((bursts[0] as Array).size() >= 4 and (bursts[2] as Array).size() >= 4,
			"swarm: at least 4 of 6 drones fired bursts 1 and 3 (%d, %d)" % [(bursts[0] as Array).size(),
			(bursts[2] as Array).size()])
	_check(burst_spread <= 0.05, "swarm: the drones start each burst within 0.05 s (%.3f s)" % burst_spread)
	_check((hops[0] as Array).size() >= 4, "swarm: at least 4 of 6 drones hopped after burst 1")
	_check(hop_spread <= 0.05, "swarm: the drones start each hop within 0.05 s (%.3f s)" % hop_spread)
	await _frames(2)
	_check(launcher.flying.is_empty() and back[0] == 0 and launcher.docked_count() == 6,
			"swarm: all drones are destroyed after (none docks); the pack still shows 6")
	_check(dummy.hp < hp_before, "swarm: the drones hit the dummy")
	print("swarm: dummy damage %.0f" % (hp_before - dummy.hp))
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
	# 1. A pair attacks and comes back; a second launch right after (no cool down, drones in the air).
	var hp_before := dummy.hp
	var models: Array[Node3D] = [launcher.docked_left[0], launcher.docked_right[0]]
	var homes: Array[Transform3D] = [models[0].transform, models[1].transform]
	var parents: Array[Node] = [models[0].get_parent(), models[1].get_parent()]
	_clear_reset()
	_check(launcher.launch(dummy) == 2 and launcher.docked_count() == 6, "recall: a pair launches, the pack stays full")
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	await _frames(2)
	_check(drones[0].is_copy and drones[1].is_copy and not models[0].visible,
			"recall: copies fly; the real models hide while the copies pop out")
	_check(drones[0].squad == drones[1].squad and drones[0].squad != null, "recall: the pair is one squad")
	_check(launcher.can_launch() and launcher.launch(dummy) == 2 and launcher.flying.size() == 4,
			"cool down off: a second pair launches while the first flies (%d in the air)" % launcher.flying.size())
	_check(status.text.contains("ACTIVE") and status.text.contains("6/6") and not status.text.contains(" s"),
			"cool down off: HUD line %s" % status.text)
	drones = launcher.flying.duplicate()
	var docks := [0]
	var returned := {}
	for d in drones:
		d.docked.connect(func(_x: AttackDrone, _m: Node3D) -> void: docks[0] += 1)
	var waited := 0
	for i in 900:
		await _frames(1)
		for k in drones.size():
			var d := drones[k]
			if is_instance_valid(d) and d.phase == AttackDrone.Phase.RETURN and not returned.has(k):
				returned[k] = true
				# Saucer rule (user 2026-11-02): 3 bursts = 3 position changes; the way home is the last one.
				_check(d.bursts_fired == 3 and d.shifts_done == 3,
						"recall: drone %d fired 3 bursts and made 3 moves (the last one is the way home): %d, %d"
						% [k, d.bursts_fired, d.shifts_done])
		waited = i
		if launcher.flying.is_empty():
			break
	print("recall: all back after %.2f s, dummy damage %.0f, closest to a hitbox %.2f m (%s), to the pack %.2f m"
			% [waited / 60.0, hp_before - dummy.hp, _clear_min, _clear_part, _pack_min])
	_check(dummy.hp < hp_before, "recall: the pairs hit the dummy")
	_check(returned.size() == 4, "recall: all 4 drones fly back after the attack (%d)" % returned.size())
	_check(docks[0] == 4 and launcher.docked_count() == 6, "recall: all 4 dock again (%d), the pack shows 6" % docks[0])
	await _frames(25)
	for k in 2:
		var model := models[k]
		_check(is_instance_valid(model) and model.visible and model.get_parent() == parents[k]
				and model.transform.is_equal_approx(homes[k]), "recall: drone model %d is on its dock, visible" % k)
	_check(get_nodes_in_group(&"attack_drones").is_empty(), "recall: no flying drone is left")
	_check(is_zero_approx(launcher.cooldown_left), "cool down off: none after the drones are back (%.2f s)"
			% launcher.cooldown_left)
	var after_flight := launcher.launch(dummy)
	_check(after_flight == 2, "cool down off: a pair launches at once after the drones are back (%d)" % after_flight)
	for d in launcher.flying.duplicate():
		d.on_hit(1000.0)
	await _frames(5)
	# 2. Way home, user 2026-11-04: clear of the body. The old straight way first, to see that the test catches it.
	var data := launcher.data
	var results := {}
	data.return_avoid_body = false
	results["old"] = await _return_run(launcher, mech, flat * 100.0, false)
	data.return_avoid_body = true
	var cases := [["ahead 100 m", flat * 100.0, false], ["close, ahead 25 m", flat * 25.0, false],
			["beside, 40 m right", flat.cross(Vector3.UP) * 40.0, false], ["behind, 30 m", -flat * 30.0, false],
			["ahead 100 m, the mech turns", flat * 100.0, true]]
	for case in cases:
		var r: Dictionary = await _return_run(launcher, mech, case[1], case[2])
		results[case[0]] = r
		_check(r["docks"] == 2, "way home (%s): both drones dock (%d)" % [case[0], r["docks"]])
		_check(r["clear"] > data.hit_radius,
				"way home (%s): the hit sphere stays clear of the body, closest %.2f m to %s (hit radius %.2f)"
				% [case[0], r["clear"], r["part"], data.hit_radius])
		_check(r["pack"] > data.hit_radius, "way home (%s): clear of the back pack until 1.5 m from the dock, closest %.2f m"
				% [case[0], r["pack"]])
	var old: Dictionary = results["old"]
	print("way home, old straight way: closest %.2f m to %s, to the pack %.2f m, docks %d"
			% [old["clear"], old["part"], old["pack"], old["docks"]])
	_check(old["clear"] < data.hit_radius,
			"way home: the old straight way did clip the body, so the measure sees it (%.2f m)" % old["clear"])
	dummy.queue_free()
	# 3. A returning drone is hit like one in the fire phase: a Bullet from outside destroys it.
	dummy = _dummy(mech.global_position + flat * 100.0)
	await _frames(5)
	for phase_name in ["fire", "return"]:
		var launched_pair := _armed(launcher).launch(dummy) == 2
		var pair: Array[AttackDrone] = launcher.flying.duplicate()
		var want := AttackDrone.Phase.FIRE if phase_name == "fire" else AttackDrone.Phase.RETURN
		for i in 900:
			await _frames(1)
			if launched_pair and is_instance_valid(pair[0]) and pair[0].phase == want \
					and (phase_name == "fire" or pair[0].return_time > 0.3):
				break
		var victim := pair[0]
		var phase_ok := is_instance_valid(victim) and victim.phase == want
		_check(launched_pair and phase_ok, "bullet (%s): the drone is in the %s phase" % [phase_name, phase_name])
		if phase_ok:
			await _bullet_hit(victim, mech)
			_check(not is_instance_valid(victim) or (victim.is_queued_for_deletion() and victim.shot_down),
					"bullet (%s): a Bullet shot at the drone destroys it" % phase_name)
		for d in launcher.flying.duplicate():
			if is_instance_valid(d):
				d.on_hit(1000.0)
		await _frames(5)
	dummy.queue_free()


## One return flight: a pair attacks a dummy at offset from the mech, flies home and docks; the mech turns during
## the way home when spin is true. Returns the closest distances to the hitboxes and the number of docked drones.
func _return_run(launcher: DroneLauncher, mech: Mech, offset: Vector3, spin: bool) -> Dictionary:
	var dummy := _dummy(mech.global_position + offset)
	await _frames(70)
	_clear_reset()
	var docks := [0]
	_armed(launcher).launch(dummy)
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	for d in drones:
		d.docked.connect(func(_x: AttackDrone, _m: Node3D) -> void: docks[0] += 1)
	var yaw := mech.rotation.y
	for i in 900:
		await _frames(1)
		if spin:
			for d in drones:
				if is_instance_valid(d) and d.phase == AttackDrone.Phase.RETURN:
					mech.rotation.y += 0.03
					break
		if OS.has_environment("DRONE_TRACE") and i % 10 == 0:
			for d in drones:
				if is_instance_valid(d) and d.phase == AttackDrone.Phase.RETURN:
					print("  return t%.2f pos %s dock %s dist %.1f vel %.1f" % [d.return_time,
							d.global_position.snapped(Vector3.ONE * 0.1), d.dock.global_position.snapped(Vector3.ONE * 0.1),
							d.global_position.distance_to(d.dock.global_position), d.velocity.length()])
		if launcher.flying.is_empty():
			break
	mech.rotation.y = yaw
	dummy.queue_free()
	await _frames(5)
	return {"clear": _clear_min, "part": _clear_part, "pack": _pack_min, "docks": docks[0]}


## Shoots a bullet at the drone from 4 m outside (away from the mech), with the drone held in place for the
## shot, and lets it fly until it hits.
func _bullet_hit(drone: AttackDrone, mech: Mech) -> void:
	drone.set_physics_process(false)
	drone.velocity = Vector3.ZERO
	var away := drone.global_position - mech.global_position
	away.y = 0.0
	var origin := drone.global_position + away.normalized() * 4.0
	var bullet := (load("res://scenes/weapons/bullet.tscn") as PackedScene).instantiate() as Bullet
	bullet.damage = 1000.0
	bullet.velocity = (drone.global_position - origin).normalized() * 300.0
	current_scene.add_child(bullet)
	bullet.global_position = origin
	for i in 10:
		await _frames(1)
		if not is_instance_valid(drone) or drone.is_queued_for_deletion():
			break
	if is_instance_valid(drone):
		drone.set_physics_process(true)


## The rules before 2026-11-04, set back with the DroneData switches: the drones leave the pack, one launch at a time,
## a cool down from when the last one is back, 2 flights per recall drone, a returning drone shot down is gone.
func _classic_rules_test(recall: DroneModData) -> void:
	var mech: Mech = await _build(recall)
	var launcher := DroneLauncher.find(mech)
	var data := launcher.data
	data.unlimited = false
	data.one_launch_at_a_time = true
	data.cooldown_s = 10.0
	var status := root.find_child("DroneStatus", true, false) as DroneStatus
	var aim := mech.get_node("MechAim") as MechAim
	var flat := Vector3(aim.aim_direction.x, 0.0, aim.aim_direction.z).normalized()
	var dummy := _dummy(mech.global_position + flat * 100.0)
	await _frames(5)
	var models: Array[Node3D] = [launcher.docked_left[0], launcher.docked_right[0]]
	var homes: Array[Transform3D] = [models[0].transform, models[1].transform]
	var parents: Array[Node] = [models[0].get_parent(), models[1].get_parent()]
	_check(launcher.launch(dummy) == 2 and launcher.docked_count() == 4,
			"classic: a pair leaves the pack (%d left)" % launcher.docked_count())
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	await _frames(2)
	_check(not drones[0].is_copy and launcher.launch(dummy) == 0 and launcher.flying.size() == 2,
			"classic: no launch while drones are active")
	_check(status.text.contains("ACTIVE"), "classic: HUD line %s" % status.text)
	var waited := 0
	for i in 900:
		await _frames(1)
		waited = i
		if launcher.docked_count() == 6:
			break
	_check(launcher.docked_count() == 6, "classic: both drones dock again (%d on the pack, %.2f s)"
			% [launcher.docked_count(), waited / 60.0])
	for k in 2:
		var model := models[k]
		_check(is_instance_valid(model) and model.get_parent() == parents[k] and model.transform.is_equal_approx(homes[k]),
				"classic: drone %d is back at its dock" % k)
	# Their second flight: they do not come back. The 10 s cool down from the docking.
	launcher.docked_left.erase(models[0])
	launcher.docked_left.push_front(models[0])
	launcher.docked_right.erase(models[1])
	launcher.docked_right.push_front(models[1])
	await _frames(2)
	print("classic: cool down after the docking: %.2f s, HUD %s" % [launcher.cooldown_left, status.text])
	_check(launcher.cooldown_left > 9.5 and launcher.launch(dummy) == 0, "classic: no launch just after the drones are back")
	_check(status.text.contains("10 s"), "classic: HUD line shows the seconds")
	await _frames(int(launcher.cooldown_left * 60.0) + 3)
	_check(launcher.can_launch(), "classic: ready 10 s after the drones are back")
	_check(launcher.launch(dummy) == 2, "classic: the same pair launches again")
	drones = launcher.flying.duplicate()
	_check(not drones[0].return_home and not drones[1].return_home, "classic: on the second flight they will not return")
	await _wait_gone(drones, 600)
	await _frames(2)
	_check(launcher.docked_count() == 4, "classic: after the second flight they are gone (%d on the pack)"
			% launcher.docked_count())
	# A returning drone shot down is gone.
	_check(_armed(launcher).launch(dummy) == 2, "classic: a fresh pair launches")
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
	_check(hit and launcher.docked_count() == 3, "classic: a drone shot down on its way back is gone (%d on the pack)"
			% launcher.docked_count())
	data.unlimited = true
	data.one_launch_at_a_time = false
	data.cooldown_s = 0.0
	dummy.queue_free()
