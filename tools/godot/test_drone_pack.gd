extends SceneTree
## Drone Pack test (2026-10-31, user picture and rules). Model: the pack is in the garage catalog (1 aux slot, no
## bonus) and holds 6 drones, 3 stacked on one axle per side (Drone1..3 left, outer first; Drone4..6 right). Each
## Drone<n> holds its disc meshes and a DroneMuzzle, sits on DroneDock<n>, and no mech mesh point is inside a disc
## at rest. Flight (user rules): T locks a dummy 100 m ahead; the release launches a pair. In the open the pair
## takes both flanks, stops at a firing place within 20 m that sees the dummy, does not move from the first shot,
## fires 3 bursts, hits, and is gone at 5 s. A low wall (6 m) in the way: the drones fly over it. A tall wall
## (40 m) in the way: they fly around it. Cover after the release (the dummy moves into a U of 30 m walls, open toward
## the mech): the drones seek a place that sees it and hit. No drone step passes through a wall or building, no drone touches one
## (its hit sphere stays free), and no drone is over 12.5 m above the ground. The mech's own weapons skip its drones (get_hit_exclude). A drone shot down
## explodes (an AI drone). AI: an AI enemy with the Drone Pack launches drones at the player; it shoots enemy
## drones at it with a heavy rifle (it hits the small drones); with an SMG (its spread misses them: not efficient)
## it takes cover; with a beam rifle it charges and shoots them. "One hit" and charged shots hit 75% of the time
## (the roll), a miss aims past the drone. Exits with code 1 on a failure.
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/test_drone_pack.gd
## DRONE_SHOT=<png> with a window: a picture of the attack in the open. DRONE_TRACE=1 prints the drone flights,
## touches and steps through walls; AI_TRACE=1 prints the AI against the drones (heavy rifle).

const MAP := "res://maps/urban_small/urban_small.tscn"
const PACK := "res://data/parts/backpacks/backpack_drone.tres"
## The disc shape for the clearance check (m; the model: radius 0.45, thickness 0.1, less 1 to 3 cm).
const DISC_RADIUS := 0.42
const DISC_HALF_THICKNESS := 0.04

var _failures: int = 0
## Drone steps that passed through a wall or building (all flights).
var _through: int = 0
var _last_pos: Dictionary = {}
## Frames where a drone's hit sphere touched a wall or building, and the highest height over the ground seen.
var _touches: int = 0
var _top_height: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		_track_drones()


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


## Counts drone steps that cross the world or a building (a ray from the last place to the new one).
func _track_drones() -> void:
	if current_scene == null:
		return
	var space := current_scene.get_viewport().world_3d.direct_space_state
	for node in get_nodes_in_group(&"attack_drones"):
		var drone := node as AttackDrone
		var now := drone.global_position
		if _last_pos.has(drone.get_instance_id()):
			var before: Vector3 = _last_pos[drone.get_instance_id()]
			if before.distance_to(now) > 0.001:
				var query := PhysicsRayQueryParameters3D.create(before, now, 17)
				if not space.intersect_ray(query).is_empty():
					_through += 1
					if OS.has_environment("DRONE_TRACE"):
						print("THROUGH %s -> %s phase %d age %.2f" % [before, now, drone.phase, drone.age])
		_last_pos[drone.get_instance_id()] = now
		var shape := SphereShape3D.new()
		shape.radius = drone.data.hit_radius
		var touch := PhysicsShapeQueryParameters3D.new()
		touch.shape = shape
		touch.transform = Transform3D(Basis.IDENTITY, now)
		touch.collision_mask = 17
		if not space.intersect_shape(touch, 1).is_empty():
			_touches += 1
			if OS.has_environment("DRONE_TRACE"):
				print("TOUCH at %s phase %d age %.2f" % [now, drone.phase, drone.age])
		var ground := DroneNavigator.ground_height(drone, now, 17, 0.0)
		_top_height = maxf(_top_height, now.y - ground)


func _run() -> void:
	var pack := load(PACK) as BackPackPart
	var catalog := load("res://data/garage_catalog.tres") as GarageCatalog
	_check(pack in catalog.back_packs, "the Drone Pack is in the garage catalog")
	_check(pack.aux_slots == 1 and pack.get_mod_stat() == -1 and pack.drone != null, "1 aux slot, no bonus, drones")
	_check(is_equal_approx(pack.drone.gun.range_m, 20.0), "the drone gun reaches 20 m")
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
	_model_checks(mech, holder.model)
	await _flight_tests(mech)
	await _ai_tests((current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher).mech)
	_finish()


func _model_checks(mech: Mech, model: Node3D) -> void:
	_check(model.find_child("Aux1", true, false) != null, "Aux1 hardpoint")
	_check(mech.get_node_or_null(^"BackPackOutlets") == null, "no boost outlets")
	_check(model.find_child("Drone6", true, false) != null and model.find_child("Drone7", true, false) == null,
			"6 drones in the model")
	var pack_meshes := model.find_children("*", "MeshInstance3D", true, false)
	var stacked := true
	for i in 6:
		var drone := model.find_child("Drone%d" % (i + 1), true, false) as Node3D
		var dock := model.find_child("DroneDock%d" % (i + 1), true, false) as Node3D
		_check(drone != null and dock != null, "Drone%d and DroneDock%d in the model" % [i + 1, i + 1])
		if drone == null or dock == null:
			continue
		var meshes := drone.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() >= 15 and drone.find_child("DroneMuzzle*", true, false) != null,
				"Drone%d holds its disc meshes (%d) and a muzzle" % [i + 1, meshes.size()])
		_check(drone.global_position.distance_to(dock.global_position) < 0.01, "Drone%d sits on its dock" % (i + 1))
		var side := (drone.global_position - mech.global_position).dot(mech.global_basis.x)
		_check(absf(side) > 0.7 and signf(side) == (-1.0 if i < 3 else 1.0),
				"Drone%d is on the %s side (%.2f m)" % [i + 1, "left" if i < 3 else "right", side])
		# The stack: the drones of a side share the axle, the first one outermost.
		var first := model.find_child("Drone%d" % (1 if i < 3 else 4), true, false) as Node3D
		var along := (drone.position - first.position)
		stacked = stacked and Vector2(along.y, along.z).length() < 0.01 and (i % 3 == 0 or absf(drone.position.x)
				< absf(model.find_child("Drone%d" % i, true, false).position.x))
		var hits: Array[String] = []
		for mesh: MeshInstance3D in mech.find_children("*", "MeshInstance3D", true, false):
			if mesh in pack_meshes or not mesh.is_visible_in_tree() or mesh.mesh == null:
				continue
			# Mesh points inside the disc (in the drone's frame: the axis is X).
			var inside := 0
			var to_drone := drone.global_transform.affine_inverse() * mesh.global_transform
			for p: Vector3 in mesh.mesh.get_faces():
				var q := to_drone * p
				if absf(q.x) < DISC_HALF_THICKNESS and Vector2(q.y, q.z).length() < DISC_RADIUS:
					inside += 1
			if inside > 0:
				hits.append("%s (%d points)" % [mesh.name, inside])
		_check(hits.is_empty(), "Drone%d clears the mech at rest %s" % [i + 1, hits])
	_check(stacked, "3 drones stacked on one axle per side, outer first")


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


## A wall (layer 5, buildings) centered at center, size (x across, y up, z thick) turned to face along facing.
func _wall(center: Vector3, size: Vector3, facing: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	current_scene.add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP), center)
	return wall


## Watches a launched pair until both are gone. Returns per drone: [fire_start_age, bursts, end_age, moved after
## the first shot (m), distance to the target at the first shot, flank sign of the firing place, flank].
func _watch(drones: Array[AttackDrone], dummy: TargetDummy, right: Vector3, shot_path: String = "") -> Array:
	var out := []
	for k in drones.size():
		out.append([-1.0, 0, -1.0, 0.0, -1.0, 0.0, drones[k].flank])
	var fire_pos := {}
	for f in 420:
		await _frames(1)
		var alive := false
		for k in drones.size():
			var d := drones[k]
			if not is_instance_valid(d) or d.is_queued_for_deletion():
				continue
			alive = true
			out[k][2] = d.age
			out[k][1] = d.bursts_fired
			if d.phase == AttackDrone.Phase.FIRE:
				if not fire_pos.has(k):
					fire_pos[k] = d.global_position
					out[k][0] = d.age
					out[k][4] = d.global_position.distance_to(dummy.get_lock_point())
					out[k][5] = signf((d.global_position - dummy.global_position).dot(right))
				out[k][3] = maxf(out[k][3], d.global_position.distance_to(fire_pos[k]))
		if OS.has_environment("DRONE_TRACE") and f % 15 == 0:
			for k in drones.size():
				var d := drones[k]
				if is_instance_valid(d) and not d.is_queued_for_deletion():
					print("  t%.2f d%d phase %d pos %s goal %s place %s path %s" % [d.age, k, d.phase, d.global_position.snapped(Vector3.ONE * 0.1),
							d.goal.snapped(Vector3.ONE * 0.1), d.has_place, d._nav._path])
					var sh := SphereShape3D.new()
					sh.radius = 2.0
					var q := PhysicsShapeQueryParameters3D.new()
					q.shape = sh
					q.transform = Transform3D(Basis.IDENTITY, d.global_position)
					q.collision_mask = 17
					var near: Array = []
					for h in current_scene.get_viewport().world_3d.direct_space_state.intersect_shape(q, 4):
						var c := h.collider as Node3D
						near.append("%s %s L%d" % [c.name, c.global_position.snapped(Vector3.ONE * 0.1), (c as CollisionObject3D).collision_layer])
					if not near.is_empty():
						print("     near: %s" % [near])
		if shot_path != "" and f == 170:
			root.get_viewport().get_texture().get_image().save_png(shot_path)
		if not alive:
			break
	return out


func _flight_tests(mech: Mech) -> void:
	var launcher := DroneLauncher.find(mech)
	_check(launcher != null and launcher.docked_left.size() == 3 and launcher.docked_right.size() == 3,
			"DroneLauncher with 3 drones each side")
	_check(InputMap.has_action(&"drone_launch") and (InputMap.action_get_events(&"drone_launch")[0] as InputEventKey)
			.physical_keycode == KEY_T, "T is the drone key")
	if launcher == null:
		return
	var aim := mech.get_node("MechAim") as MechAim
	var flat := aim.aim_direction
	flat.y = 0.0
	flat = flat.normalized()
	var right := flat.cross(Vector3.UP)
	var start := mech.global_position
	# 1. Open: a dummy 100 m ahead, locked with T.
	var dummy := _dummy(start + flat * 100.0)
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
	var rids := mech.get_hit_exclude()
	_check(drones[0].get_rid() in rids and drones[1].get_rid() in rids, "the mech's own weapons skip its drones")
	var hp_before := dummy.hp
	var result := await _watch(drones, dummy, right, OS.get_environment("DRONE_SHOT"))
	for k in 2:
		var r: Array = result[k]
		print("open, drone %d: fires at %.2f s from %.1f m, %d bursts, moved %.2f m after the first shot, gone at %.2f s"
				% [k, r[0], r[4], r[1], r[3], r[2]])
		_check(r[0] > 1.8 and r[0] < 2.8, "open: drone %d fires about 2 s after the launch (%.2f s)" % [k, r[0]])
		_check(r[4] > 0.0 and r[4] <= 20.0, "open: drone %d fires from within 20 m (%.1f m)" % [k, r[4]])
		_check(r[3] < 0.05, "open: drone %d does not move after its first shot (%.2f m)" % [k, r[3]])
		_check(r[1] == 3, "open: drone %d fires 3 bursts (%d)" % [k, r[1]])
		_check(r[2] <= 5.05, "open: drone %d is gone by 5 s (%.2f s)" % [k, r[2]])
		_check(r[5] == r[6], "open: drone %d fires from its own flank (a pincer)" % k)
	print("open: dummy damage from one pair: %.0f" % (hp_before - dummy.hp))
	_check(dummy.hp < hp_before, "open: the drones hit the dummy")
	await _frames(2)
	_check(launcher.flying.is_empty(), "no drones left in the air")
	# 2. A low wall in the way (200 m wide, 6 m high, at 45 m): the drones fly over it and hit. Then a tall wall
	# (60 m wide, 40 m high, at 50 m): they fly around it (the ceiling is 12.5 m) and hit.
	for case in [["low wall", Vector3(200.0, 6.0, 2.0)], ["tall wall", Vector3(60.0, 40.0, 2.0)]]:
		var size: Vector3 = case[1]
		var wall := _wall(start + flat * (45.0 if size.y < 10.0 else 50.0) + Vector3.UP * size.y * 0.5, size, flat)
		# Past the path cell cache time (DroneData.cell_cache_time: it knew this air as free).
		await _frames(70)
		hp_before = dummy.hp
		if launcher.docked_count() < 2:
			await _refill(mech)
		mech = (current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher).mech
		launcher = DroneLauncher.find(mech)
		_check(launcher.launch(dummy) == 2, "%s: a pair launches" % case[0])
		drones = launcher.flying.duplicate()
		result = await _watch(drones, dummy, right)
		print("%s: fires at %.2f s and %.2f s, dummy damage %.0f" % [case[0], result[0][0], result[1][0],
				hp_before - dummy.hp])
		_check(result[0][0] > 0.0 and result[1][0] > 0.0, "%s: both drones reach a firing place" % case[0])
		_check(dummy.hp < hp_before, "%s: the drones hit the dummy" % case[0])
		wall.queue_free()
	# 3. Cover after the release: 1 s after the launch the dummy moves 15 m back along the street into a U of walls
	# (30 m high, over the ceiling) open toward the mech. The side walls hide it from the flank places: the drones
	# seek a place in front that sees it.
	await _frames(2)
	hp_before = dummy.hp
	if launcher.docked_count() < 2:
		await _refill(mech)
		mech = (current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher).mech
		launcher = DroneLauncher.find(mech)
	_check(launcher.launch(dummy) == 2, "cover: a pair launches")
	drones = launcher.flying.duplicate()
	await _frames(60)
	var hide := start + flat * 85.0
	_wall(hide + flat * 9.0 + Vector3.UP * 15.0, Vector3(20.0, 30.0, 2.0), flat)
	_wall(hide - right * 9.0 - flat * 2.0 + Vector3.UP * 15.0, Vector3(22.0, 30.0, 2.0), right)
	_wall(hide + right * 9.0 - flat * 2.0 + Vector3.UP * 15.0, Vector3(22.0, 30.0, 2.0), right)
	dummy.global_position = hide
	result = await _watch(drones, dummy, right)
	print("cover: fires at %.2f s and %.2f s, dummy damage %.0f" % [result[0][0], result[1][0], hp_before - dummy.hp])
	_check(result[0][0] > 0.0 or result[1][0] > 0.0, "cover: the drones find a firing place that sees the dummy")
	_check(dummy.hp < hp_before, "cover: the drones hit the dummy in cover")
	_check(_through == 0, "no drone step passed through a wall or building (%d)" % _through)
	_check(_touches == 0, "no drone touched a wall, a roof or a corner (%d frames)" % _touches)
	_check(_top_height <= 12.55, "no drone flew over 12.5 m above the ground (top %.2f m)" % _top_height)
	_check(_status_count(status) == launcher.docked_count(), "status line counts the drones left (%s)" % status.text)
	dummy.queue_free()


## Builds the player mech again in place with a full Drone Pack (the test uses more than 3 pairs). Returns true.
func _refill(mech: Mech) -> bool:
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = load(PACK) as BackPackPart
	switcher.rebuild(loadout, Transform3D(mech.global_basis, mech.global_position))
	for i in 40:
		await physics_frame
	return true


func _status_count(status: DroneStatus) -> int:
	var parts := status.text.split(" ")
	for part in parts:
		if part.contains("/"):
			return int(part.split("/")[0])
	return -1


## The AI: an AI enemy with the Drone Pack launches drones at the player. Then the player's drones fly at an AI:
## with a heavy rifle it shoots them down, with an SMG it takes cover.
func _ai_tests(player: Mech) -> void:
	var spawner := current_scene.find_child("Enemy1", true, false) as MechSpawner
	_check(spawner != null, "the map has the AI enemy spawner")
	if spawner == null:
		return
	var pack := load(PACK) as BackPackPart
	spawner.set_right_weapon(load("res://data/weapons/heavy_rifle.tres") as WeaponData)
	spawner.set_back_pack(pack)
	spawner.set_active(true)
	await _frames(30)
	var enemy := spawner.mech
	var launcher := DroneLauncher.find(enemy)
	_check(launcher != null and launcher.docked_count() == 6, "the AI enemy has the Drone Pack and 6 drones")
	# Bring the player into the enemy's sight, 80 m in front of it.
	player.global_position = enemy.global_position - enemy.global_basis.z * 80.0
	player.velocity = Vector3.ZERO
	var tactics := enemy.find_child("AIDroneTactics", true, false) as AIDroneTactics
	var launched_at_player := false
	for i in 600:
		await _frames(1)
		for node in get_nodes_in_group(&"attack_drones"):
			var d := node as AttackDrone
			if d.launcher_mech == enemy and d.target == player:
				launched_at_player = true
		if launched_at_player:
			break
	_check(launched_at_player, "the AI launches drones at the player")
	# Shot down: a drone takes damage until 0 HP and explodes.
	var one: AttackDrone = null
	for node in get_nodes_in_group(&"attack_drones"):
		one = node as AttackDrone
	if one != null:
		one.on_hit(one.data.hp * 0.5)
		_check(not one.is_queued_for_deletion(), "half HP: the drone still flies")
		one.on_hit(one.data.hp)
		_check(one.shot_down and one.is_queued_for_deletion(), "shot down at 0 HP")
	# Clear the air, then the player's drones fly at the AI (heavy rifle: it shoots them).
	for node in get_nodes_in_group(&"attack_drones"):
		node.queue_free()
	await _frames(2)
	# The player's pack used its drones above: a fresh pack.
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.back_pack = pack
	var place := Transform3D(player.global_basis, player.global_position)
	switcher.rebuild(loadout, place)
	await _frames(40)
	player = switcher.mech
	var mine := DroneLauncher.find(player)
	var shot := false
	var enemy_gun := (enemy.get_node("WeaponController") as WeaponController).right_weapon
	var rounds_fired := 0
	var covered := false
	var last_ammo := enemy_gun.ammo
	_check(mine != null and mine.launch(enemy) == 2, "the player's pair flies at the AI (heavy rifle)")
	var mine_drones: Array[AttackDrone] = mine.flying.duplicate()
	var downed: Array[int] = [0]
	for d in mine_drones:
		d.finished.connect(func(x: AttackDrone) -> void:
			if x.shot_down:
				downed[0] += 1)
	for i in 360:
		await _frames(1)
		if tactics != null and tactics.mode == AIDroneTactics.Mode.SHOOT:
			if not shot:
				# Ready to fire when it turns to the drones (it may have just fired at the player: the heavy rifle has a
				# 3 s cooldown).
				enemy_gun.ammo = enemy_gun.data.magazine
				enemy_gun.reload_left = 0.0
				enemy_gun._cooldown = 0.0
				last_ammo = enemy_gun.ammo
			shot = true
		if tactics != null and tactics.mode == AIDroneTactics.Mode.COVER:
			covered = true
			if enemy_gun.ammo < last_ammo:
				rounds_fired += last_ammo - enemy_gun.ammo
		if OS.has_environment("AI_TRACE") and i % 10 == 0:
			var inp := enemy.get_node("MechInput") as MechInput
			var dt := tactics.drone_target
			print("AI f%d mode %d target %s yaw err %.1f can_use %s ammo %d fire %s/%s threats %d" % [i, tactics.mode,
					dt.global_position.snapped(Vector3.ONE * 0.1) if is_instance_valid(dt) else "none",
					rad_to_deg(absf(wrapf(inp.aim_yaw - enemy.get_aim_yaw(), -PI, PI))), enemy_gun.can_use(), enemy_gun.ammo,
					inp.fire_held, inp.left_fire_held, tactics._threats().size()])
		last_ammo = enemy_gun.ammo
		if mine_drones.all(func(d: Variant) -> bool: return not is_instance_valid(d)):
			break
	for node in get_nodes_in_group(&"attack_drones"):
		node.queue_free()
	# One round each 3 s, 75% of them aimed to hit: shooting a drone down is likely, not sure (printed only).
	print("heavy rifle: %d rounds at the drones, %d of 2 shot down" % [rounds_fired, downed[0]])
	# When buildings hide the drones from it, taking cover is the right answer too (user rule).
	_check(shot and (rounds_fired >= 1 or covered), "the AI with a heavy rifle turns to shoot the drones (%d rounds%s)"
			% [rounds_fired, ", cover while they were hidden" if covered else ""])
	# SMG: its spread misses the small drones too often (not efficient), so it takes cover.
	var smg := load("res://data/weapons/smg.tres") as WeaponData
	var drone_data := pack.drone
	var probe := AttackDrone.new()
	probe.data = drone_data
	probe.hp = drone_data.hp
	print("kill times at 20 m: SMG %.1f s, heavy rifle %.1f s" % [AIDroneTactics.kill_time(smg, probe, 20.0),
			AIDroneTactics.kill_time(load("res://data/weapons/heavy_rifle.tres") as WeaponData, probe, 20.0)])
	probe.free()
	spawner.set_right_weapon(smg)
	await _frames(30)
	enemy = spawner.mech
	tactics = enemy.find_child("AIDroneTactics", true, false) as AIDroneTactics
	player.global_position = enemy.global_position - enemy.global_basis.z * 80.0
	await _frames(5)
	_check(mine.launch(enemy) == 2, "the player's pair flies at the AI (SMG)")
	var took_cover := false
	var start := enemy.global_position
	for i in 300:
		await _frames(1)
		if tactics != null and tactics.mode == AIDroneTactics.Mode.COVER and tactics.cover.is_finite():
			took_cover = true
		if took_cover and enemy.global_position.distance_to(start) > 3.0:
			break
	_check(took_cover, "the AI with an SMG seeks cover from the drones")
	_check(enemy.global_position.distance_to(start) > 2.0 or tactics.cover.distance_to(start) < 3.0,
			"the AI walks to the cover (or is in cover already)")
	print("AI moved %.1f m toward cover; cover %s, %.1f m from the start, mode %d" % [enemy.global_position.distance_to(start),
			tactics.cover, tactics.cover.distance_to(start) if tactics.cover.is_finite() else -1.0, tactics.mode])
	# 75% for "one hit" and charged shots (user rule): the roll, and the aim of a miss.
	var hits := 0
	for i in 4000:
		if tactics.roll_hit():
			hits += 1
	_check(is_equal_approx(tactics.hit_rate_limited, 0.75) and absf(hits / 4000.0 - 0.75) < 0.03,
			"one hit and charged shots: %.1f%% of the rolls hit" % (hits / 40.0))
	var test_drone := AttackDrone.new()
	test_drone.data = drone_data
	test_drone.hp = drone_data.hp
	current_scene.add_child(test_drone)
	test_drone.global_position = enemy.get_lock_point() - enemy.global_basis.z * 20.0 + Vector3.UP * 3.0
	tactics._roll_hit = true
	var on := tactics.aim_point_for(test_drone, 100000.0, true).distance_to(test_drone.global_position)
	tactics._roll_hit = false
	var off := tactics.aim_point_for(test_drone, 100000.0, true).distance_to(test_drone.global_position)
	_check(on < 0.01 and off > drone_data.hit_radius + 1.0, "a hit aims at the drone (%.2f m), a miss past it (%.2f m)"
			% [on, off])
	test_drone.free()
	# Beam rifle (charged): it charges to the charge that kills a drone and shoots.
	var beam_data := load("res://data/weapons/beam_rifle.tres") as WeaponData
	spawner.set_right_weapon(beam_data)
	await _frames(30)
	enemy = spawner.mech
	tactics = enemy.find_child("AIDroneTactics", true, false) as AIDroneTactics
	var rifle := (enemy.get_node("WeaponController") as WeaponController).right_weapon as BeamRifleWeapon
	player.global_position = enemy.global_position - enemy.global_basis.z * 80.0
	await _frames(5)
	_check(rifle != null and mine.launch(enemy) == 2, "the player's pair flies at the AI (beam rifle)")
	var beamed := false
	var charged := 0.0
	var beam_drones: Array[AttackDrone] = mine.flying.duplicate()
	for i in 330:
		await _frames(1)
		if tactics.mode == AIDroneTactics.Mode.SHOOT and rifle != null:
			charged = maxf(charged, rifle.charge)
			if rifle.discharge_left > 0.0:
				beamed = true
		if beam_drones.all(func(d: Variant) -> bool: return not is_instance_valid(d)):
			break
	print("beam rifle: kill time %.2f s at 20 m, top charge %.2f, beam fired %s" % [AIDroneTactics.kill_time_of(rifle,
			beam_drones[0] if is_instance_valid(beam_drones[0]) else _probe(drone_data), 20.0), charged, beamed])
	_check(beamed and charged > 0.1, "the AI with a beam rifle charges and fires at the drones")
	spawner.set_active(false)


func _probe(drone_data: DroneData) -> AttackDrone:
	var probe := AttackDrone.new()
	probe.data = drone_data
	probe.hp = drone_data.hp
	probe.queue_free()
	return probe


func _finish() -> void:
	print("drone pack test: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
