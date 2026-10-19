extends SceneTree
## Jump and landing test and render tool (user request 2026-10-15: the Mixamo jump clips). The player
## holds jump for JUMP_CHARGE seconds (3 = a full 9 m jump), releases, and falls; the tool logs the
## clip layers, the predicted time to impact, the lowest foot point (under the ground = negative) and
## the landing recovery, and with a window saves a side picture every JUMP_STEP physics frames.
## Render (frames in JUMP_OUT, default user://jump_renders/):
##   JUMP_CHARGE=3 JUMP_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##     --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_jump.gd
## Environment: JUMP_CHARGE (s, default 3), JUMP_OUT, JUMP_STEP (frames between pictures, default 6),
## JUMP_WEAPONS ("" = the map loadout; else slot=weapon pairs, e.g.
## "right=auto_cannon,left=warden_shield,back_left=missile_pod_l,back_right=missile_pod_r", "-" = empty),
## JUMP_FALL (a start height in m: the mech is dropped from there), JUMP_VIEW (side, front, front_left), JUMP_CAM_DIST (m, default 30), JUMP_FOV (degrees, default 32),
## JUMP_CLEAR=0 (no clearance check: faster).
## Clearance (phase 4, 2026-10-19): every frame the points of the weapon, shield, pod and hand meshes are
## tested against the leg armor boxes (each leg mesh's rest box on its main bone, CLEAR_MARGIN smaller);
## the log column "clear" counts the points inside, and the summary names the worst frame and the meshes.

const MAP := "res://maps/urban_small/urban_small.tscn"

var _out_dir := ""
var _render := false


func _initialize() -> void:
	_render = DisplayServer.get_name() != "headless"
	_out_dir = OS.get_environment("JUMP_OUT")
	if _out_dir == "":
		_out_dir = ProjectSettings.globalize_path("user://jump_renders")
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
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	for pair in OS.get_environment("JUMP_WEAPONS").split(",", false):
		var slot := pair.get_slice("=", 0).strip_edges()
		var weapon := pair.get_slice("=", 1).strip_edges()
		loadout.set("weapon_" + slot if slot in ["right", "left"] else slot,
				null if weapon == "-" else load("res://data/weapons/%s.tres" % weapon) as WeaponData)
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	var player := switcher.mech
	var forward := Basis(Vector3.UP, player.get_aim_yaw()) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	# JUMP_VIEW: "side" (default), "front" or "front_left" (between the front and the left side).
	match OS.get_environment("JUMP_VIEW"):
		"front":
			side = forward
		"front_left":
			side = (forward - forward.cross(Vector3.UP)).normalized()
	var camera := Camera3D.new()
	camera.fov = float(OS.get_environment("JUMP_FOV")) if OS.get_environment("JUMP_FOV") != "" else 32.0
	map.add_child(camera)
	camera.current = true
	_hide_trees_near(map, player.global_position + side * 40.0, player.global_position)
	var probe := LegProbe.new()
	probe.mech = player
	(player.find_child("Skeleton3D", true, false) as Skeleton3D).add_child(probe)
	var pose := player.find_child("JumpPose", true, false) as SkeletalJumpPose
	var recovery := player.landing_recovery
	await _frames(5)
	var origin := player.global_position
	var charge := float(OS.get_environment("JUMP_CHARGE")) if OS.get_environment("JUMP_CHARGE") != "" else 3.0
	var step := int(OS.get_environment("JUMP_STEP")) if OS.get_environment("JUMP_STEP") != "" else 6
	var drop := float(OS.get_environment("JUMP_FALL")) if OS.get_environment("JUMP_FALL") != "" else 0.0
	if drop > 0.0:
		player.global_position = origin + Vector3.UP * drop
		player.velocity = Vector3.ZERO
	else:
		Input.action_press("jump")
	var frame := 0
	var shot := 0
	var released := drop > 0.0
	var jumped := drop > 0.0
	var landed_frame := -1
	var min_low := INF
	var min_low_floor := INF
	var low_after_land := INF
	var peak := 0.0
	var log: PackedStringArray = []
	var clear_worst := 0
	var clear_worst_t := 0.0
	var clear_worst_names := ""
	var clear_frames := 0
	var max_frames := 60 * 14
	while frame < max_frames:
		await _frames(1)
		frame += 1
		var t := frame / 60.0
		if not released and t >= charge:
			Input.action_release("jump")
			released = true
		var lows: Array = probe.lows
		var low := minf(lows[0], lows[1])
		var floor_y := origin.y
		var height := player.global_position.y - floor_y
		peak = maxf(peak, height)
		if player.is_on_floor():
			min_low_floor = minf(min_low_floor, low)
		min_low = minf(min_low, low)
		if not player.is_on_floor():
			jumped = true
		var phase := "ground"
		if not player.is_on_floor():
			phase = "air_up" if player.velocity.y > 0.0 else "air_down"
		elif recovery.is_recovering():
			phase = "landing"
			if landed_frame < 0:
				landed_frame = frame
		if landed_frame >= 0:
			low_after_land = minf(low_after_land, low)
		var d := pose.director
		var w := [0.0, 0.0, 0.0] if d == null else d.weights
		var line := "t=%.2f %s y=%.2f vy=%.1f crouch=%.2f land=%.2f air=%.2f clips=[%.2f %.2f %.2f] times=[%.2f %.2f %.2f] tti=%.2f rec=%.2f feet_low=%.3f" % [
				t, phase, height, player.velocity.y, pose.crouch, pose.landing, pose.air, w[0], w[1], w[2],
				0.0 if d == null else d.times[0], 0.0 if d == null else d.times[1], 0.0 if d == null else d.times[2],
				-1.0 if d == null or d.time_to_impact == INF else d.time_to_impact, recovery.time_left, low]
		var hits := probe.clearance(player) if OS.get_environment("JUMP_CLEAR") != "0" else {"count": 0, "names": ""}
		line += " clear=%d" % hits.count
		if hits.count > 0:
			clear_frames += 1
			line += " " + hits.names
		if hits.count > clear_worst:
			clear_worst = hits.count
			clear_worst_t = t
			clear_worst_names = hits.names
		log.append(line)
		_follow(camera, player, side, origin)
		# During the charge only the last pictures are saved.
		var wanted := frame % step == 0 and (released or t >= charge - 0.4 or drop > 0.0)
		if _render and wanted and shot < 400:
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			image.save_png("%s/jump_%03d_%s.png" % [_out_dir, shot, phase])
			shot += 1
		if landed_frame >= 0 and not recovery.is_recovering() and frame > landed_frame + 90:
			break
	var file := FileAccess.open(_out_dir + "/jump_log.txt", FileAccess.WRITE)
	for line in log:
		if frame >= 0:
			file.store_line(line)
	file.close()
	print("JUMP SUMMARY charge=%.1f drop=%.1f peak_height=%.2f landed_frame=%d fall_height=%.2f recovery=%.2f s" % [
			charge, drop, peak, landed_frame, recovery.fall_height, recovery.duration])
	print("  lowest foot point on the floor: %.3f m (negative = under the ground), whole run: %.3f, after landing: %.3f" % [
			min_low_floor, min_low, low_after_land])
	print("  CLEAR weapons/hands inside leg armor: worst %d points at t=%.2f (%s), %d frames with any" % [
			clear_worst, clear_worst_t, clear_worst_names, clear_frames])
	quit()


func _follow(camera: Camera3D, player: Mech, side: Vector3, origin: Vector3) -> void:
	var y := player.global_position.y - origin.y
	var middle := origin + Vector3(0, 4.5 + y * 0.7, 0)
	var distance := float(OS.get_environment("JUMP_CAM_DIST")) if OS.get_environment("JUMP_CAM_DIST") != "" else 30.0
	camera.global_position = middle + side * (distance + y * 0.6)
	camera.look_at(middle, Vector3.UP)


## Lowest point of the left and right leg meshes under the mech's ground (m, negative = under it),
## measured after every pose modifier ran (a probe modifier at the end of the skeleton; a plain read of
## the bones from a script would show the pose before the modifiers).
class LegProbe extends SkeletonModifier3D:
	var mech: Mech
	var lows := [0.0, 0.0]
	## Name of the lowest mesh per side.
	var names := ["", ""]
	## Bone poses (skeleton space) after all modifiers, from the last update.
	var globals: Array[Transform3D] = []
	var _cache := {}
	## Leg mesh -> [main bone, rest box in that bone's space].
	var _boxes := {}
	## Mesh -> sampled local points.
	var _points := {}
	const CLEAR_MARGIN := 0.05

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
		self.globals = globals

	## Points of the held items and hands inside the leg armor boxes now: {count, names}.
	func clearance(player: Mech) -> Dictionary:
		var skeleton := get_skeleton()
		if globals.is_empty():
			return {"count": 0, "names": ""}
		var legs := skeleton.find_children("Leg_*", "MeshInstance3D", true, false)
		var inverse := skeleton.global_transform.affine_inverse()
		var count := 0
		var hit_names := {}
		for node in player.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.skin != null or not mesh.is_visible_in_tree() or mesh.mesh == null or String(mesh.name).begins_with("HPIndicator"):
				continue
			if not _points.has(mesh):
				var pts := PackedVector3Array()
				var all := mesh.mesh.get_faces()
				var stride := maxi(1, all.size() / 400)
				for i in range(0, all.size(), stride):
					pts.append(all[i])
				_points[mesh] = pts
			var to_skeleton := inverse * mesh.global_transform
			for point: Vector3 in _points[mesh]:
				var local := to_skeleton * point
				var hit := ""
				for leg in legs:
					for box: Array in _boxes_of(skeleton, leg as MeshInstance3D):
						if (box[1] as AABB).has_point(globals[box[0]].affine_inverse() * local):
							hit = leg.name
							break
					if hit != "":
						break
				if hit != "":
					count += 1
					hit_names["%s>%s" % [_label(mesh), hit]] = true
		return {"count": count, "names": ",".join(hit_names.keys())}

	func _label(mesh: MeshInstance3D) -> String:
		var parent := mesh.get_parent()
		return "%s/%s" % [parent.name if parent else "", mesh.name]

	## Boxes of a skinned leg mesh: per bone, the rest box (in that bone's space, CLEAR_MARGIN smaller) of
	## the vertices that bone moves most. Returns [[bone, box], ...].
	func _boxes_of(skeleton: Skeleton3D, mesh: MeshInstance3D) -> Array:
		if _boxes.has(mesh):
			return _boxes[mesh]
		var per_bone := {}
		for s in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(vertices.size(), 1)
			for v in vertices.size():
				var best := 0
				for k in per:
					if weights[v * per + k] > weights[v * per + best]:
						best = k
				var index := bones[v * per + best]
				var p := mesh.skin.get_bind_pose(index) * vertices[v]
				per_bone[index] = (per_bone[index] as AABB).expand(p) if per_bone.has(index) else AABB(p, Vector3.ZERO)
		var out := []
		for index: int in per_bone:
			var bone := mesh.skin.get_bind_bone(index)
			if bone < 0:
				bone = skeleton.find_bone(mesh.skin.get_bind_name(index))
			out.append([bone, (per_bone[index] as AABB).grow(-CLEAR_MARGIN)])
		_boxes[mesh] = out
		if OS.get_environment("CLEAR_DEBUG") != "":
			for item: Array in out:
				print("box %s bone %s size %s pos %s" % [mesh.name, skeleton.get_bone_name(item[0]), (item[1] as AABB).size, (item[1] as AABB).position])
		return out

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
