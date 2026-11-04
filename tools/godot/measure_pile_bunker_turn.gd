extends SceneTree
## Pile Bunker body turn probe (2026-11-04): runs a real attack (power up, release, charge, clip) at a target mech in the
## crosshair and prints how far the stake line passes from the target's center (flat), in the strike window and at the hit,
## how far the mech turned and its largest turn per physics frame. Environment:
##   NUMBER  clip number (3 to 5, default 3)       SIDE   R or L (default R)       DIST  target distance (m, default 12)
##   TURN    0 = no body turn (clip_turn_speed_deg 0), default on
##   NOTARGET  1 = no target mech: the stakes never fire and the miss is measured against the point DIST m ahead on the
##             crosshair line (where the target would stand)
##   ONRAY   1 = the target stands on the camera's crosshair line instead of the mech's aim line
##   FLICK_DEG  the mech is turned this many degrees (left positive) off the crosshair at the release, default 0
## Run: godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_pile_bunker_turn.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
const POWER_FRAMES := 60
const MAX_FRAMES := 480


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(name: String, fallback: String) -> String:
	return OS.get_environment(name) if OS.has_environment(name) else fallback


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var side := _env("SIDE", "R")
	var number := int(_env("NUMBER", "3"))
	var distance := float(_env("DIST", "12"))
	var flick := deg_to_rad(float(_env("FLICK_DEG", "0")))
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/pile_bunker.tres") if side == "R" else null
	loadout.weapon_left = load("res://data/weapons/pile_bunker.tres") if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var weapons := player.get_node("WeaponController") as WeaponController
	var bunker := (weapons.right_weapon if side == "R" else weapons.left_weapon) as PileBunkerWeapon
	bunker.clip_number = number
	if _env("TURN", "1") == "0":
		bunker.clip_turn_speed_deg = 0.0
	var forward := weapons.mech_aim.aim_point - player.global_position
	forward.y = 0.0
	var goal := player.global_position + forward.normalized() * distance
	if _env("ONRAY", "0") == "1":
		# The target stands on the camera's crosshair line (the camera sits to the right of the mech), distance m ahead of
		# the mech, so the crosshair point is on the target like in play.
		var aim := weapons.mech_aim
		var origin := aim.camera.project_ray_origin(aim.get_ring_screen_point())
		var ray := aim.camera.project_ray_normal(aim.get_ring_screen_point())
		ray.y = 0.0
		ray = ray.normalized()
		var foot := origin + ray * (player.global_position - origin).dot(ray)
		goal = foot + ray * distance
		goal.y = player.global_position.y
	var no_target := _env("NOTARGET", "0") == "1"
	var target: Mech = null
	var hits: Array = []
	if not no_target:
		target = _make_target(map, goal, player)
		await _frames(20)
		for key: String in target.health.max_hp:
			target.health.max_hp[key] = 100000.0
			target.health.hp[key] = 100000.0
		target.health.damaged.connect(func(part: String, amount: float) -> void: hits.append("%s %.0f" % [part, amount]))
	var button := "use_right_arm" if side == "R" else "use_left_arm"
	Input.action_press(button)
	await _frames(POWER_FRAMES)
	Input.action_release(button)
	# FLICK_DEG: the mech's legs and torso stand this many degrees off the crosshair at the release (a player who
	# flicks the crosshair onto the target as the Pile Bunker goes off; the legs lag behind).
	if flick != 0.0:
		player.set_heading(player.rotation.y - flick)
	var start_yaw := 0.0
	var last_yaw := 0.0
	var max_step := 0.0
	var best := INF
	var at_fire := -1.0
	var fired := false
	var sum := 0.0
	var count := 0
	var flicked := false
	var window := Vector2.ZERO
	for frame in MAX_FRAMES:
		await _frames(1)
		if bunker.state != PileBunkerWeapon.State.CLIP:
			if frame > 60 and bunker.state == PileBunkerWeapon.State.IDLE and bunker.stake_out == 0.0:
				break
			continue
		if not flicked:
			flicked = true
			start_yaw = player.rotation.y
			last_yaw = start_yaw
			window = bunker.punch_clip().strikes[0]
		var melee := player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
		var t := melee.external_time(bunker)
		max_step = maxf(max_step, absf(rad_to_deg(wrapf(player.rotation.y - last_yaw, -PI, PI))))
		last_yaw = player.rotation.y
		var nose := bunker._nose.global_position
		var line := -bunker._nose.global_basis.z.normalized()
		var miss := _line_distance_flat(goal if no_target else target.global_position, nose, line)
		if OS.has_environment("TRACE") and frame % 6 == 0:
			var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
			var pelvis_y := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).origin).y - player.global_position.y
			print("  pelvis %.2f above the root, fired %s, since fire %.2f" % [pelvis_y, bunker.has_fired, bunker._since_fire])
			print("  t %.2f mech %s yaw %.1f aim %s turn point %s err %.1f nose %s line %s" % [t, player.global_position.snappedf(0.1), rad_to_deg(player.rotation.y), weapons.mech_aim.aim_point.snappedf(0.1), bunker._turn_point().snappedf(0.1), rad_to_deg(bunker._heading_error()), nose.snappedf(0.1), line.snappedf(0.01)])
		if t >= window.x and t <= window.y and not bunker.has_fired:
			best = minf(best, miss)
			if miss < INF and Vector2(line.x, line.z).length() >= 0.6:
				sum += miss
				count += 1
		if bunker.has_fired:
			fired = true
		if bunker.has_fired and at_fire < 0.0:
			at_fire = miss
	var turned := rad_to_deg(wrapf(last_yaw - start_yaw, -PI, PI))
	print("clip %d %s dist %.0f turn %s flick %.0f: fired %s, hits %s, stake line to the target (flat): best in window %.2f m, mean over the window %.2f m (%d frames), at hit %.2f m, turned %.1f deg, largest step %.2f deg/frame, window %s" % [
			number, side, distance, _env("TURN", "1"), rad_to_deg(flick), fired, hits.size(), best, sum / maxf(count, 1), count, at_fire, turned, max_step, window])
	quit()


## Flat distance (m) of point from the line through origin along direction, ahead of the origin only (INF when the
## stakes point sideways or the point is behind the nose).
func _line_distance_flat(point: Vector3, origin: Vector3, direction: Vector3) -> float:
	var d := Vector3(direction.x, 0.0, direction.z)
	if d.length() < 0.3:
		return INF
	d = d.normalized()
	var offset := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	var along := offset.dot(d)
	if along < 0.0:
		return INF
	return (offset - d * along).length()


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
