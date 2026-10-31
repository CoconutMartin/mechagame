extends SceneTree
## Drone Pack test (2026-10-31, user picture: "the circle thing on the side should be detachable, we'll make it to
## an attack drone"). The Drone Pack is in the garage catalog (1 aux slot, no bonus). Its model has Drone1 and
## Drone2: each one a single node that holds every mesh of its disc (so the game can take the drone off), a
## DroneDock1..2 empty at the same place, and Aux1. No boost outlets. At rest the drone discs do not overlap the
## mech's other meshes (DRONE_LIST=1 prints the meshes near them).
## Drones (user design 2026-10-31, "3 drones each side"): 6 drones, 3 per side. Hold T with a target dummy 100 m
## ahead in the aim: it locks; release: a pair launches (one each side). They reach the target in about 2 s, hold
## opposite flanks (a pincer), fire 3 bursts and move between them, hit the dummy, and are gone at 5 s. The
## status line counts them. A drone shot down explodes. Exits with code 1 on a failure. DRONE_SHOT=<png> with a
## window: a picture of the attack.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_drone_pack.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_drone.tres"
## The disc shape for the clearance check (m; the model: radius 0.28, thickness 0.2, less 2 to 3 cm).
const DISC_RADIUS := 0.25
const DISC_HALF_THICKNESS := 0.08

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


## World box of every mesh under node.
func _box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var aabb := mesh.global_transform * mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
	return box


func _run() -> void:
	var pack := load(PACK) as BackPackPart
	var catalog := load("res://data/garage_catalog.tres") as GarageCatalog
	_check(pack in catalog.back_packs, "the Drone Pack is in the garage catalog")
	_check(pack.aux_slots == 1 and pack.get_mod_stat() == -1, "1 aux slot, no bonus")
	change_scene_to_file(MAP)
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = pack
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var mech := switcher.mech
	var holder := mech.get_node_or_null(^"BackPackMount") as BackPackMount
	_check(holder != null and holder.model != null, "the pack is on the mech")
	if holder == null or holder.model == null:
		_finish()
		return
	var model := holder.model
	_check(model.find_child("Aux1", true, false) != null, "Aux1 hardpoint")
	_check(mech.get_node_or_null(^"BackPackOutlets") == null, "no boost outlets")
	var pack_meshes := model.find_children("*", "MeshInstance3D", true, false)
	_check(model.find_child("Drone6", true, false) != null and model.find_child("Drone7", true, false) == null,
			"6 drones in the model")
	for i in 6:
		var drone := model.find_child("Drone%d" % (i + 1), true, false) as Node3D
		var dock := model.find_child("DroneDock%d" % (i + 1), true, false) as Node3D
		_check(drone != null and dock != null, "Drone%d and DroneDock%d in the model" % [i + 1, i + 1])
		if drone == null or dock == null:
			continue
		var meshes := drone.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() >= 15 and drone.find_child("DroneMuzzle*", true, false) != null, "Drone%d holds its disc meshes (%d)" % [i + 1, meshes.size()])
		_check(drone.global_position.distance_to(dock.global_position) < 0.01, "Drone%d sits on its dock" % (i + 1))
		var side := (drone.global_position - mech.global_position).dot(mech.global_basis.x)
		_check(absf(side) > 0.7 and signf(side) == (-1.0 if i < 3 else 1.0),
				"Drone%d is on the %s side (%.2f m)" % [i + 1, "left" if i < 3 else "right", side])
		# No other mech mesh inside the disc's box (shrunk 5 cm).
		var box := _box(drone).grow(-0.05)
		var hits: Array[String] = []
		for mesh: MeshInstance3D in mech.find_children("*", "MeshInstance3D", true, false):
			if mesh in pack_meshes or not mesh.is_visible_in_tree():
				continue
			if not box.intersects(mesh.global_transform * mesh.get_aabb()) or mesh.mesh == null:
				continue
			# A box overlap is not enough (the torso box is big, the disc is round): count the mesh points inside
			# the disc (in the drone's frame: the axis is X).
			var inside := 0
			var to_drone := drone.global_transform.affine_inverse() * mesh.global_transform
			for p: Vector3 in mesh.mesh.get_faces():
				var q := to_drone * p
				if absf(q.x) < DISC_HALF_THICKNESS and Vector2(q.y, q.z).length() < DISC_RADIUS:
					inside += 1
			if inside > 0:
				hits.append("%s (%d points)" % [mesh.name, inside])
		if OS.get_environment("DRONE_LIST") == "1":
			print("Drone%d box %s near: %s" % [i + 1, box, hits])
		_check(hits.is_empty(), "Drone%d clears the mech at rest %s" % [i + 1, hits])
	await _flight_test(mech)
	_finish()


func _flight_test(mech: Mech) -> void:
	var launcher := DroneLauncher.find(mech)
	_check(launcher != null and launcher.docked_left.size() == 3 and launcher.docked_right.size() == 3,
			"DroneLauncher with 3 drones each side")
	_check(InputMap.has_action(&"drone_launch") and (InputMap.action_get_events(&"drone_launch")[0] as InputEventKey)
			.physical_keycode == KEY_T, "T is the drone key")
	if launcher == null:
		return
	# A target dummy 100 m ahead along the aim, on the ground.
	var aim := mech.get_node("MechAim") as MechAim
	var flat := aim.aim_direction
	flat.y = 0.0
	flat = flat.normalized()
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
	dummy.global_position = mech.global_position + flat * 100.0
	await _frames(5)
	var event := InputEventAction.new()
	event.action = &"drone_launch"
	event.pressed = true
	Input.parse_input_event(event)
	for i in 120:
		await _frames(1)
		if launcher.locked != null:
			break
	_check(launcher.locked == dummy, "holding T locks the dummy 100 m ahead")
	var status := root.find_child("DroneStatus", true, false) as DroneStatus
	_check(status != null and status.text.contains("6/6"), "status line: %s" % (status.text if status != null else "none"))
	if launcher.locked != dummy:
		launcher.locked = dummy  # Go on with the flight checks.
	var release := InputEventAction.new()
	release.action = &"drone_launch"
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)
	_check(launcher.flying.size() == 2 and launcher.docked_count() == 4, "release launches a pair (%d flying, %d left)"
			% [launcher.flying.size(), launcher.docked_count()])
	if launcher.flying.size() != 2:
		return
	var drones: Array[AttackDrone] = launcher.flying.duplicate()
	_check(drones[0].flank != drones[1].flank, "the pair takes both flanks")
	var hp_before := dummy.hp
	var right := flat.cross(Vector3.UP)
	var arrive := [-1.0, -1.0]
	var sides_ok := true
	var places: Array = [[], []]
	var last_bursts := [0, 0]
	var end_age := [-1.0, -1.0]
	var shot_path := OS.get_environment("DRONE_SHOT")
	for f in 400:
		await _frames(1)
		for k in 2:
			var d := drones[k]
			if not is_instance_valid(d):
				continue
			end_age[k] = d.age
			if arrive[k] < 0.0 and d.phase == AttackDrone.Phase.ATTACK:
				arrive[k] = d.age
				print("Drone %d arrives at %.2f s, %.1f m from the target" % [k, d.age,
						d.global_position.distance_to(dummy.get_lock_point())])
			if d.phase == AttackDrone.Phase.ATTACK:
				# The pincer: the drone stays on its flank of the line mech -> target.
				var off := (d.global_position - dummy.global_position).dot(right)
				sides_ok = sides_ok and signf(off) == d.flank and absf(off) > 5.0
				if d.bursts_fired != last_bursts[k]:
					last_bursts[k] = d.bursts_fired
					places[k].append(d.global_position)
		if shot_path != "" and f == 200:
			root.get_viewport().get_texture().get_image().save_png(shot_path)
		if not is_instance_valid(drones[0]) and not is_instance_valid(drones[1]):
			break
	for k in 2:
		_check(arrive[k] > 1.8 and arrive[k] < 2.2, "drone %d reaches the target in about 2 s (%.2f s)" % [k, arrive[k]])
		_check(last_bursts[k] == 3, "drone %d fires 3 bursts (%d)" % [k, last_bursts[k]])
		var moved := true
		for j in range(1, places[k].size()):
			moved = moved and (places[k][j] as Vector3).distance_to(places[k][j - 1]) > 4.0
		_check(moved, "drone %d moves between bursts" % k)
		_check(end_age[k] > 4.7 and end_age[k] <= 5.05, "drone %d is gone at 5 s (%.2f s)" % [k, end_age[k]])
	_check(sides_ok, "the drones stay on opposite flanks (a pincer) while they attack")
	print("dummy damage from one pair: %.0f" % (hp_before - dummy.hp))
	_check(dummy.hp < hp_before, "the drones hit the dummy")
	await _frames(2)
	_check(launcher.flying.is_empty(), "no drones left in the air")
	# Shot down: a launched drone takes damage until 0 HP and explodes.
	_check(launcher.launch(dummy) == 2, "a second pair launches")
	await _frames(10)
	var target_drone := launcher.flying[0]
	target_drone.on_hit(launcher.data.hp * 0.5)
	_check(is_instance_valid(target_drone) and not target_drone.is_queued_for_deletion(), "half HP: still flying")
	target_drone.on_hit(launcher.data.hp)
	_check(target_drone.shot_down and target_drone.is_queued_for_deletion(), "shot down at 0 HP")
	_check(status.text.contains("2/6"), "status line counts the drones left (%s)" % status.text)
	dummy.queue_free()


func _finish() -> void:
	print("drone pack test: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
