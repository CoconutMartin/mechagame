extends SceneTree
## Melee test and render tool. Plays the fist and hammer attacks against a target mech in front of the
## player (inside the crosshair), logs hits, chain combos, the cooldown and the lowest foot point, and
## with a window saves a strip of frames per attack.
## Headless (log only; the targets stand 12 m and 7 m ahead):
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/render_melee.gd
## Render (frames in user://melee_renders/ or the folder in MELEE_OUT; one distance, 12 m):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_melee.gd
## Environment: MELEE_ONLY (part of a case name), MELEE_OUT (folder), MELEE_TRACE (print the strike
## point), MELEE_DISTANCES (for example "12,7"), MELEE_CAMERA ("side" default, "behind").

const MAP := "res://maps/urban_small/urban_small.tscn"
const MECH_SCENE := "res://scenes/mech/sanggigilid.tscn"
const FIST := "res://data/weapons/fist.tres"
const HAMMER := "res://data/weapons/hammer.tres"
## Frames saved per attack.
const FRAMES_PER_ATTACK := 9
## Longest case (physics frames).
const MAX_FRAMES := 900

## Cases: name, weapon ("fist" or "hammer"), button ("right" = RMB, "left" = LMB), move key ("" or an
## action), kind ("attack", "combo", "cooldown"), the combo delays (seconds after each hit to the next
## press), the move key of each combo press (optional; "" = no key; empty list = the case key stays) and
## the expected swings (optional, MeleeAttack file names; the log says CHECK ok or CHECK FAIL) and
## options (optional: "hits" = the hit count when a swing misses; "stagger" = the expected stagger points
## per hit on the target, " knock" marks a knock-down; the log says STAGGER ok or STAGGER FAIL).
## Chain combo cases (user rules 2026-10-18): any attack chains into any other, up to 3 swings, press
## within 0.6 s after the hit, S ends the chain, then the 5 s cooldown. Hammer stagger (user decision
## 2026-10-18): swings 1 and 2 give 25 points (a flinch), the S strike and the third swing 45 (knock-down).
const CASES := [
	["fist_straight_r", "fist", "right", "", "attack", []],
	["fist_straight_l", "fist", "left", "", "attack", []],
	["fist_uppercut_W", "fist", "right", "move_forward", "attack", []],
	["fist_swipe_S", "fist", "right", "move_back", "attack", []],
	["fist_hook_A", "fist", "left", "move_left", "attack", []],
	["fist_hook_D", "fist", "right", "move_right", "attack", []],
	["fist_combo_L", "fist", "left", "", "combo", [0.1, 0.1], [], ["straight_l", "straight_r_chain", "uppercut_l"]],
	["fist_combo_R", "fist", "right", "", "combo", [0.2, 0.3], [], ["straight_r", "straight_l_chain", "uppercut_r"]],
	["fist_combo_late", "fist", "left", "", "combo", [0.7, 0.1], [], ["straight_l"]],
	["fist_combo_window", "fist", "left", "", "combo", [0.55, 0.55], [], ["straight_l", "straight_r_chain", "uppercut_l"]],
	["fist_hook_A_plain_W", "fist", "left", "move_left", "combo", [0.1, 0.1], ["", "move_forward"],
			["hook_l", "straight_r_chain", "uppercut_l"]],
	["fist_W_S_ends", "fist", "right", "move_forward", "combo", [0.1, 0.1], ["move_back", "move_left"],
			["uppercut_r", "swipe_r"]],
	["fist_cooldown", "fist", "right", "", "cooldown", []],
	["hammer_none", "hammer", "right", "", "attack", []],
	["hammer_S", "hammer", "right", "move_back", "attack", []],
	["hammer_A", "hammer", "right", "move_left", "attack", []],
	["hammer_D", "hammer", "right", "move_right", "attack", []],
	["hammer_D_A_S", "hammer", "right", "move_right", "combo", [0.1, 0.1], ["move_left", "move_back"],
			["hammer_swing_d", "hammer_swing_a", "hammer_down"], {"stagger": ["25", "25", "45 knock"]}],
	# The fourth press comes after three swings: it starts nothing, the cooldown follows.
	["hammer_A_RMB_D", "hammer", "right", "move_left", "combo", [0.1, 0.1, 0.1], ["", "move_right", ""],
			["hammer_swing_a", "hammer_down_light", "hammer_swing_d"], {"stagger": ["25", "25", "45 knock"]}],
	["hammer_S_ends", "hammer", "right", "move_back", "combo", [0.1], ["move_left"], ["hammer_down"],
			{"stagger": ["45 knock"]}],
	["hammer_timeout", "hammer", "right", "move_right", "combo", [0.7], ["move_left"], ["hammer_swing_d"],
			{"stagger": ["25"]}],
	["hammer_lmb", "hammer", "left", "", "attack", []],
]

var _out_dir := ""
var _render := false
var _log: Array = []
var _skin_cache := {}


func _initialize() -> void:
	_render = DisplayServer.get_name() != "headless"
	_out_dir = OS.get_environment("MELEE_OUT")
	if _out_dir == "":
		_out_dir = ProjectSettings.globalize_path("user://melee_renders")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	_hide_spawner_enemies(map)
	var only := OS.get_environment("MELEE_ONLY")
	var distances: Array = [12.0] if _render else [12.0, 7.0]
	if OS.get_environment("MELEE_DISTANCES") != "":
		distances = []
		for text in OS.get_environment("MELEE_DISTANCES").split(","):
			distances.append(float(text))
	for case: Array in CASES:
		if only != "" and not (case[0] as String).contains(only):
			continue
		for distance: float in distances:
			await _play(map, switcher, case, distance)
	print("MELEE SUMMARY")
	for line: String in _log:
		print("  ", line)
	quit()


## The spawner enemies would walk into the test and shoot.
func _hide_spawner_enemies(map: Node) -> void:
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false


func _play(map: Node, switcher: LoadoutSwitcher, case: Array, distance: float) -> void:
	var name: String = "%s_%d" % [case[0], int(distance)] if not _render else case[0]
	# A fresh player with the weapon, at the map start place.
	var loadout := switcher.current_loadout.duplicate() as Loadout
	if case[1] == "fist":
		loadout.weapon_right = load(FIST)
		loadout.weapon_left = load(FIST)
	else:
		loadout.weapon_right = load(HAMMER)
		loadout.weapon_left = null
	var place := Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	switcher.rebuild(loadout, place)
	await _frames(40)
	var player := switcher.mech
	var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
	if OS.get_environment("MELEE_TRACE") != "":
		print("  player after rebuild=%s yaw=%.1f" % [player.global_position, rad_to_deg(player.get_aim_yaw())])
	# The target: the same mech, no input, no camera, high HP, a lockable enemy like the spawner's.
	var target := (load(MECH_SCENE) as PackedScene).instantiate() as Mech
	target.name = "MeleeTarget"
	# Placed before it enters the tree (at the player's place it would push the player away).
	target.position = player.global_position + forward * distance
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
	await _frames(20)
	var health := target.health
	for key: String in health.max_hp:
		health.max_hp[key] = 100000.0
		health.hp[key] = 100000.0
	var options: Dictionary = case[8] if case.size() > 8 else {}
	# Stagger points per hit on the target, with " stagger" or " knock" when the hit staggered or knocked
	# it down.
	var reactions: Array[String] = []
	if health.stability != null:
		health.stability.hit_taken.connect(func(points: float, _from: Vector3) -> void: reactions.append("%.0f" % points))
		health.stability.staggered.connect(func(_from: Vector3) -> void:
			if not reactions.is_empty():
				reactions[-1] += " stagger")
		health.stability.knocked_down.connect(func(_from: Vector3) -> void:
			if not reactions.is_empty():
				reactions[-1] += " knock")
	var hits: Array = []
	health.damaged.connect(func(key: String, amount: float) -> void: hits.append("%s %.0f" % [key, amount]))
	var melee := player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	# MELEE_NOLIFT: the foot clamp off, to compare the foot numbers with and without it.
	melee.lift_feet = OS.get_environment("MELEE_NOLIFT") == ""
	if OS.get_environment("MELEE_LIMITLEGS") != "":
		melee.free_legs = false
	var side_camera := _side_camera(map, player, target)
	_hide_trees_near(map, side_camera.global_position, (player.global_position + target.global_position) * 0.5)
	if OS.get_environment("MELEE_NOANKLE") != "":
		for modifier in player.find_children("*", "SkeletalAnklePitch", true, false):
			(modifier as SkeletonModifier3D).active = false
	var probe := LegProbe.new()
	probe.mech = player
	(player.find_child("Skeleton3D", true, false) as Skeleton3D).add_child(probe)
	await _frames(3)
	var idle_low := probe.lows.duplicate()
	var key: String = case[3]
	if key != "":
		Input.action_press(key)
	await _frames(3)
	var button := "use_right_arm" if case[2] == "right" else "use_left_arm"
	var start_distance := player.global_position.distance_to(target.global_position)
	if OS.get_environment("MELEE_TRACE") != "":
		print("  player=%s target=%s group=%s can_process=%s wrecked=%s" % [player.global_position, target.global_position,
				target.is_in_group(&"lockable"), target.can_process(), target.is_wrecked])
	var result := {}
	if case[4] == "cooldown":
		result = await _cooldown_case(melee, button)
	else:
		result = await _attack_case(case, name, button, player, target, melee, side_camera, hits, place, probe)
	if key != "":
		Input.action_release(key)
	var lows := result.get("lows", idle_low) as Array
	var stagger_text := "stagger=%s" % [reactions]
	if options.has("stagger"):
		var expected_stagger := Array(options["stagger"], TYPE_STRING, &"", null)
		stagger_text = ("STAGGER %s " % ("ok" if reactions == expected_stagger else "FAIL")) + stagger_text
	var line := "%s: start_dist=%.1f %s %s foot_low L=%.2f R=%.2f (idle L=%.2f R=%.2f)" % [name, start_distance,
			stagger_text, result.get("text", ""), lows[0], lows[1], idle_low[0], idle_low[1]]
	print(line)
	_log.append(line)
	side_camera.queue_free()
	target.queue_free()
	await _frames(5)


## Presses the button once, follows the attack and the combo presses. Returns {text, lows}.
func _attack_case(case: Array, name: String, button: String, player: Mech, target: Mech, melee: SkeletalMeleeAnimation,
		side_camera: Camera3D, hits: Array, place: Transform3D, probe: LegProbe) -> Dictionary:
	print("[%s] can_attack=%s dist=%.2f" % [name, melee._can_attack(), player.global_position.distance_to(target.global_position)])
	Input.action_press(button)
	await _frames(2)
	Input.action_release(button)
	var started := melee.is_playing
	if started:
		print("  target=%s aim=%s" % [melee._target, melee.weapons.mech_aim.aim_direction if melee.weapons.mech_aim != null else "none"])
	var delays: Array = case[5]
	var press_keys: Array = case[6] if case.size() > 6 else []
	var expected: Array = case[7] if case.size() > 7 else []
	var options: Dictionary = case[8] if case.size() > 8 else {}
	var held_key: String = case[3]
	var swings: Array[String] = []
	var last_count := 0
	var hit_distances: Array[String] = []
	var min_center := INF
	var swing_hit_frame := {}
	var press_at := -1
	var presses_done := 0
	var frame := 0
	var after_end := 0
	var min_distance := INF
	var hit_distance := -1.0
	var lows := [INF, INF]
	var min_sole := 0.0
	var min_after := 0.0
	var worst_names := ["", ""]
	var step := 8
	var shot := 0
	var step_set := false
	var last_attack: MeleeAttack = null
	var first_hit_swing := -1
	while frame < MAX_FRAMES:
		await _frames(1)
		frame += 1
		# A new swing: another attack, or the same attack again in a chain.
		if melee.is_playing and (melee._attack != last_attack or melee.chain_count != last_count):
			last_attack = melee._attack
			last_count = melee.chain_count
			swings.append(last_attack.resource_path.get_file().get_basename())
		if melee.is_playing and not step_set:
			step_set = true
			step = maxi(int((melee._attack.get_length() + 0.5) * 60.0) / FRAMES_PER_ATTACK, 1)
			if case[4] == "combo":
				# A chain plays several swings: more frames.
				step = 8
		# Combo presses: after the swing hit, wait the delay, then press again.
		if melee.is_playing and melee._landed and not swing_hit_frame.has(swings.size()):
			swing_hit_frame[swings.size()] = frame
			var center := player.global_position.distance_to(target.global_position)
			if hit_distance < 0.0:
				hit_distance = center
			hit_distances.append("%.1f" % center)
			if presses_done < delays.size():
				press_at = frame + int(float(delays[presses_done]) * 60.0)
		if press_at > 0 and frame >= press_at:
			press_at = -1
			# The move key of this press (the chain picks the attack from it).
			if presses_done < press_keys.size() and press_keys[presses_done] != held_key:
				if held_key != "":
					Input.action_release(held_key)
				held_key = press_keys[presses_done]
				if held_key != "":
					Input.action_press(held_key)
				await _frames(2)
				frame += 2
			presses_done += 1
			Input.action_press(button)
			await _frames(2)
			Input.action_release(button)
			frame += 2
		if melee.is_playing:
			min_center = minf(min_center, player.global_position.distance_to(target.global_position))
		if melee.is_playing and is_instance_valid(melee._weapon):
			var point := melee._weapon.get_strike_point()
			for hitbox in target.find_children("*", "PartHitbox", true, false):
				min_distance = minf(min_distance, (hitbox as Node3D).global_position.distance_to(point))
			if OS.get_environment("MELEE_TRACE") != "" and frame % 3 == 0:
				var local := player.global_transform.affine_inverse() * point
				print("  t=%.2f strike_local=(%.1f, %.1f, %.1f) dist=%.1f target=%s lunge=%.1f done=%s hold=%.2f target_down=%s" % [melee._time,
						local.x, local.y, local.z, player.global_position.distance_to(target.global_position),
						melee._target != null, melee._lunge_velocity, melee._lunge_done, melee._hold_time, target.is_fallen])
		min_sole = minf(min_sole, melee.sole_low)
		min_after = minf(min_after, melee.sole_after)
		var current: Array = probe.lows
		for side in 2:
			if current[side] < lows[side]:
				worst_names[side] = probe.names[side]
		lows = [minf(lows[0], current[0]), minf(lows[1], current[1])]
		_follow(side_camera, player, target)
		if _render and frame % step == 0 and shot < 40:
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			image.save_png("%s/%s_%02d.png" % [_out_dir, name, shot])
			shot += 1
		if started and not melee.is_playing:
			after_end += 1
			if after_end > 20:
				break
		elif not started and frame > 60:
			break
	if held_key != "" and held_key != case[3]:
		Input.action_release(held_key)
	var text := "started=%s swings=%s hits=%s landed_dist=%.1f closest_hitbox_to_strike=%.2f m cooldown_left=%.1f clip_sole_low=%.2f after_clamp=%.2f" % [
			started, swings, hits, hit_distance, min_distance, melee.get_cooldown_left(), min_sole, min_after]
	if case[4] == "combo":
		text += " presses=%d hit_dist_per_swing=%s closest_center=%.1f" % [presses_done, hit_distances, min_center]
	if not expected.is_empty():
		# Each swing hits once (option "hits": the hit count when a swing misses).
		var ok := swings == Array(expected, TYPE_STRING, &"", null) and hits.size() == int(options.get("hits", expected.size())) \
				and melee.get_cooldown_left() > melee.cooldown - 1.0
		text = ("CHECK %s " % ("ok" if ok else "FAIL")) + text
	return {"text": text + " lowest=%s" % [worst_names], "lows": lows}


## One attack, then presses during the cooldown (no attack may start) and after it.
func _cooldown_case(melee: SkeletalMeleeAnimation, button: String) -> Dictionary:
	Input.action_press(button)
	await _frames(2)
	Input.action_release(button)
	var first := melee.is_playing
	var frames := 0
	while melee.is_playing and frames < MAX_FRAMES:
		await _frames(1)
		frames += 1
	var results := []
	# Seconds after the end of the attack at which a press is tried.
	var since := 0
	for wait in [1.0, 3.0, 4.8, 5.3]:
		var goal := int(float(wait) * 60.0)
		await _frames(maxi(goal - since, 0))
		since = goal
		var left := melee.get_cooldown_left()
		Input.action_press(button)
		await _frames(2)
		Input.action_release(button)
		since += 2
		results.append("t+%.1f s: left=%.1f started=%s" % [wait, left, melee.is_playing])
		if melee.is_playing:
			break
	return {"text": "first_started=%s cooldown=%.1f %s" % [first, melee.cooldown, results]}


## Lowest point of the left and right leg meshes under the mech's ground (m, negative = under it),
## measured after every pose modifier ran (a probe modifier at the end of the skeleton; a plain read of
## the bones from a script would show the pose before the modifiers).
class LegProbe extends SkeletonModifier3D:
	var mech: Mech
	var lows := [0.0, 0.0]
	## Name of the lowest mesh per side.
	var names := ["", ""]
	var _cache := {}

	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton := get_skeleton()
		var globals: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(bone)
			var local := skeleton.get_bone_pose(bone)
			globals.append(globals[parent] * local if parent >= 0 else local)
		var result := [INF, INF]
		var result_names := ["", ""]
		for node in skeleton.find_children("Leg_*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var side := 0 if String(mesh.name).begins_with("Leg_L") else 1
			var low := _mesh_low(skeleton, globals, mesh) - mech.global_position.y
			if low < result[side]:
				result[side] = low
				result_names[side] = String(mesh.name)
		lows = result
		names = result_names

	## Lowest world height of a skinned mesh (CPU skinning, bone weights blended).
	func _mesh_low(skeleton: Skeleton3D, globals: Array[Transform3D], mesh: MeshInstance3D) -> float:
		if not _cache.has(mesh):
			var surfaces := []
			for s in mesh.mesh.get_surface_count():
				surfaces.append(mesh.mesh.surface_get_arrays(s))
			var binds := []
			for i in mesh.skin.get_bind_count():
				var bone := mesh.skin.get_bind_bone(i)
				if bone < 0:
					bone = skeleton.find_bone(mesh.skin.get_bind_name(i))
				binds.append([bone, mesh.skin.get_bind_pose(i)])
			_cache[mesh] = [surfaces, binds]
		var surfaces: Array = _cache[mesh][0]
		var binds: Array = _cache[mesh][1]
		var matrices := {}
		var low := INF
		var to_world := skeleton.global_transform
		for arrays: Array in surfaces:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(vertices.size(), 1)
			for v in vertices.size():
				var point := Vector3.ZERO
				var total := 0.0
				for k in per:
					var weight := weights[v * per + k]
					if weight <= 0.0:
						continue
					var index := bones[v * per + k]
					if not matrices.has(index):
						matrices[index] = globals[binds[index][0]] * (binds[index][1] as Transform3D)
					point += (matrices[index] * vertices[v]) * weight
					total += weight
				if total > 0.0:
					low = minf(low, (to_world * (point / total)).y)
		return low


## A camera to the side of the two mechs (or behind the player), looking at the middle.
func _side_camera(map: Node, player: Mech, target: Mech) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 50.0
	map.add_child(camera)
	_follow(camera, player, target)
	camera.current = true
	return camera


func _follow(camera: Camera3D, player: Mech, target: Mech) -> void:
	var middle := (player.global_position + target.global_position) * 0.5 + Vector3(0, 6, 0)
	var along := (target.global_position - player.global_position)
	along.y = 0.0
	var side := along.normalized().cross(Vector3.UP)
	var distance := maxf(26.0, along.length() * 1.6)
	if OS.get_environment("MELEE_CAMERA") == "behind":
		camera.global_position = player.global_position - along.normalized() * 22.0 + Vector3(0, 12, 0) + side * 4.0
		camera.look_at(middle, Vector3.UP)
		return
	camera.global_position = middle + side * distance + Vector3(0, 3, 0)
	camera.look_at(middle, Vector3.UP)


## Trees between the camera and the mechs block the view.
func _hide_trees_near(map: Node, from: Vector3, to: Vector3) -> void:
	for node in map.find_children("*", "Node3D", true, false):
		var lower := String(node.name).to_lower()
		if not (lower.contains("tree") or lower.contains("palm")):
			continue
		var point := (node as Node3D).global_position
		var segment := Geometry3D.get_closest_point_to_segment(point, from, to)
		if Vector2(point.x - segment.x, point.z - segment.z).length() < 8.0:
			(node as Node3D).visible = false
