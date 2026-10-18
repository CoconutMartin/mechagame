extends SceneTree
## Arm look render and check (user reports 2026-10-18: the hammer walk shoulders in a shallow V, fist
## arms swinging with the hands pinned, a left fist "pumping" beside a right gun, a fist snapping to the
## hang after a punch). ARMS_CASE picks the case:
##   hammer_walk, hammer_run (Shift), fists_walk, fistgun_walk (left fist, right smg), fist_combo (a left
##   straight punch while standing, then the hang), fists_run (Shift), fists_slow (the move key at
##   ARMS_THROTTLE, default 0.35: a slow walk), source_clip (the Mixamo clip ARMS_CLIP itself as a stick
##   figure on its own skeleton, one cycle; added 2026-10-18 for the clip arm swing).
## Per physics frame (inside skeleton_updated, where the modifier poses exist) it logs in torso space
## (-Z forward, +X right) the upper arm raise to the side (abduction: its angle out of the plane through the
## shoulder, up and forward) and swing (forward + / back -),
## the hand travel, the hand-to-forearm gap (jointed hand to the hand bone) and the largest hand step
## from one frame to the next, the palm's nearest distance to the leg bone lines (the arm rig's
## leg_clearance is 1.3 m) and the stride phase of each hand's most forward place. It saves front and side pictures at four stride phases (walk cases) or
## every ARMS_EVERY frames (fist_combo), and a strip of them, into ARMS_OUT.
##   ARMS_CASE=hammer_walk ARMS_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##     --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_arms.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
## Picture crop around the mech (pixels) for the strips.
const CROP := Vector2i(520, 720)

var _rows: Array[Dictionary] = []
var _player: Mech
var _skeleton: Skeleton3D
var _weapons: WeaponController
var _melee: SkeletalMeleeAnimation
var _locomotion: SkeletalLocomotion
var _control: MechHandControl
var _frame: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		_frame += 1


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	var case := _env("ARMS_CASE", "hammer_walk")
	var out := _env("ARMS_OUT", ProjectSettings.globalize_path("user://arm_renders")) + "/" + case
	DirAccess.make_dir_recursive_absolute(out)
	if case == "source_clip":
		await _render_source_clip(out)
		quit()
		return
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var right := {"hammer_walk": "hammer", "hammer_run": "hammer", "fistgun_walk": "smg"}.get(case, "") as String
	loadout.weapon_right = load("res://data/weapons/%s.tres" % right) as WeaponData if right != "" else null
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	_player = switcher.mech
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_weapons = _player.get_node("WeaponController") as WeaponController
	_melee = _player.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	_locomotion = _player.find_child("Locomotion", true, false) as SkeletalLocomotion
	_control = _player.find_child("MechHandControl", true, false) as MechHandControl
	print("case %s: right %s, left %s" % [case, _weapons.right_data.display_name if _weapons.right_data else "-",
			_weapons.left_data.display_name if _weapons.left_data else "-"])
	var camera := Camera3D.new()
	camera.fov = 30.0
	map.add_child(camera)
	camera.current = true
	# Software rendering is slow: the 3D view draws only for the pictures.
	root.disable_3d = true
	_skeleton.skeleton_updated.connect(_sample)
	var shots: Array[Image] = []
	if case == "fist_combo":
		await _frames(30)
		_rows.clear()
		var start := _frame
		Input.action_press("use_left_arm")
		await _frames(4)
		Input.action_release("use_left_arm")
		var every := int(_env("ARMS_EVERY", "8"))
		var first := int(_env("ARMS_FIRST", "42"))
		while _frame - start < int(_env("ARMS_FRAMES", "130")):
			if _frame - start >= first and (_frame - start - first) % every == 0:
				shots.append(await _shot(camera, "side", out, "%03d" % (_frame - start)))
			else:
				await _frames(1)
		_report_combo()
	else:
		Input.action_press("move_forward", float(_env("ARMS_THROTTLE", "0.35")) if case == "fists_slow" else 1.0)
		if case == "hammer_run" or case == "fists_run":
			Input.action_press("boost")
		await _frames(150)
		# One stride from a left foot landing; pictures at four phases.
		while _locomotion.get_phase() > 0.1:
			await _frames(1)
		while _locomotion.get_phase() < 0.5:
			await _frames(1)
		while _locomotion.get_phase() >= 0.5:
			await _frames(1)
		_rows.clear()
		var marks := [0.0, 0.25, 0.5, 0.75]
		var front: Array[Image] = []
		for mark: float in marks:
			while _locomotion.get_phase() < mark:
				await _frames(1)
			var name := "p%02d" % int(mark * 100.0)
			front.append(await _shot(camera, "front", out, name))
			shots.append(await _shot(camera, "side", out, name))
		var before := _locomotion.get_phase()
		while _locomotion.get_phase() >= before:
			before = _locomotion.get_phase()
			await _frames(1)
		_save_strip(front, out + "/strip_front.png")
		Input.action_release("move_forward")
		Input.action_release("boost")
		_report_walk()
	_save_strip(shots, out + "/strip_side.png")
	quit()


## One picture from the front or the right side of the mech (the 3D view draws for that frame only).
func _shot(camera: Camera3D, view: String, out: String, name: String) -> Image:
	var forward := Basis(Vector3.UP, _player.get_aim_yaw()) * Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	var chest := _player.global_position + Vector3.UP * 5.0
	var at := chest + (forward * 28.0 if view == "front" else side * 28.0)
	if view == "side" and _env("ARMS_CASE", "") == "fist_combo":
		at = chest + (side * 0.8 + forward * 0.6).normalized() * 28.0
	camera.look_at_from_position(at, chest)
	root.disable_3d = false
	await _frames(1)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	root.disable_3d = true
	image.save_png("%s/%s_%s.png" % [out, view, name])
	return image


func _save_strip(images: Array[Image], path: String) -> void:
	if images.is_empty():
		return
	var strip := Image.create(CROP.x * images.size(), CROP.y, false, images[0].get_format())
	for i in images.size():
		var image := images[i]
		var from := Vector2i((image.get_width() - CROP.x) / 2, (image.get_height() - CROP.y) / 2)
		strip.blit_rect(image, Rect2i(from, CROP), Vector2i(CROP.x * i, 0))
	strip.save_png(path)
	print("saved %s" % path)


## Inside skeleton_updated: the arm joints in torso space.
func _sample() -> void:
	var torso := _weapons.torso.global_transform.affine_inverse()
	var row := {"frame": _frame, "phase": _locomotion.get_phase() if _locomotion != null else 0.0,
			"playing": _melee != null and _melee.is_playing}
	for side in ["L", "R"]:
		var bone := func(name: String) -> Vector3:
			return torso * (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(name + "_" + side))).origin
		var shoulder: Vector3 = bone.call("upper_arm")
		var elbow: Vector3 = bone.call("forearm")
		var hand: Vector3 = bone.call("hand")
		var arm := (elbow - shoulder).normalized()
		var out := arm.x if side == "R" else -arm.x
		row["abd_" + side] = rad_to_deg(asin(clampf(out, -1.0, 1.0)))
		row["swing_" + side] = rad_to_deg(atan2(-arm.z, -arm.y))
		row["hand_" + side] = hand
		# Hand side distance past the knee (the leg's outer line; below 0.6 m the fist nears the thigh armor).
		row["clear_" + side] = absf(hand.x) - absf((bone.call("shin") as Vector3).x)
		row["elbow_" + side] = elbow
		# Palm (grip bone) and wrist distance to the leg bone lines (world, m).
		var legs := _leg_lines()
		var palm := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("grip_" + side)).origin
		var wrist_point := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_" + side)).origin
		row["legd_" + side] = minf(_line_distance(palm, legs), _line_distance(wrist_point, legs))
		var jointed: Node3D = _control.hand_right if side == "R" else _control.hand_left
		var wrist := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_" + side))
		# Part of the moving lower raise the arm rig used (SkeletalArmRig._lower_raise; 1 = all of it).
		var rig := _skeleton.find_children("*", "SkeletalArmRig", false, false)
		var sides: Array = (rig[0] as SkeletalArmRig).get("_sides") if not rig.is_empty() else []
		row["part_" + side] = float((sides[0 if side == "L" else 1] as Dictionary).get("raise_part", 0.0)) if sides.size() == 2 else 0.0
		# Palm and wrist distance to the torso and pelvis armor boxes (SkeletalArmRig._body_distance; below 0 inside).
		var rig_node: SkeletalArmRig = rig[0] if not rig.is_empty() else null
		row["body_" + side] = minf(float(rig_node.call("_body_distance", _skeleton.get_bone_global_pose(_skeleton.find_bone("grip_" + side)).origin)),
				float(rig_node.call("_body_distance", _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_" + side)).origin))) if rig_node != null and rig_node.has_method("_body_distance") else 0.0
		# Turn out to the side that kept the clip swing off the legs (SkeletalArmRig._keep_off_legs, degrees).
		row["out_" + side] = rad_to_deg(float((sides[0 if side == "L" else 1] as Dictionary).get("swing_out", 0.0))) if sides.size() == 2 else 0.0
		row["gap_" + side] = jointed.global_position.distance_to(wrist.origin) if is_instance_valid(jointed) else 0.0
	_rows.append(row)


## The leg bone lines (world): thigh to shin, shin to foot.
func _leg_lines() -> Array:
	var lines: Array = []
	for side in ["L", "R"]:
		var points: Array[Vector3] = []
		for name in ["thigh_", "shin_", "foot_"]:
			points.append(_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(name + side)).origin)
		lines.append([points[0], points[1]])
		lines.append([points[1], points[2]])
	return lines


static func _line_distance(point: Vector3, lines: Array) -> float:
	var nearest := INF
	for line: Array in lines:
		nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, line[0], line[1])))
	return nearest


## The stride phase at which a value is largest.
func _peak_phase(key: String) -> float:
	var best := -INF
	var phase := 0.0
	for row in _rows:
		if float(row[key]) > best:
			best = float(row[key])
			phase = float(row.phase)
	return phase


## The stride phase at which a hand is most forward (torso -Z).
func _forward_phase(key: String) -> float:
	var best := INF
	var phase := 0.0
	for row in _rows:
		if (row[key] as Vector3).z < best:
			best = (row[key] as Vector3).z
			phase = float(row.phase)
	return phase


func _range(key: String, axis: int = -1) -> Vector2:
	var low := INF
	var high := -INF
	for row in _rows:
		var value: float = (row[key] as Vector3)[axis] if axis >= 0 else float(row[key])
		low = minf(low, value)
		high = maxf(high, value)
	return Vector2(low, high)


func _mean(key: String) -> float:
	var total := 0.0
	for row in _rows:
		total += float(row[key])
	return total / maxf(_rows.size(), 1.0)


func _report_walk() -> void:
	print("one stride, %d samples, speed %.2f m/s" % [_rows.size(), _player.get_horizontal_speed()])
	if _env("ARMS_DUMP", "") != "":
		for row in _rows:
			print("  phase %.2f L hand %s out %.1f swing %.0f | R hand %s out %.1f swing %.0f" % [row.phase, (row.hand_L as Vector3).snapped(Vector3.ONE * 0.01),
					row.out_L, row.swing_L, (row.hand_R as Vector3).snapped(Vector3.ONE * 0.01), row.out_R, row.swing_R])
	for side in ["L", "R"]:
		var abd := _range("abd_" + side)
		var swing := _range("swing_" + side)
		var hand_y := _range("hand_" + side, 1)
		var hand_z := _range("hand_" + side, 2)
		var elbow_z := _range("elbow_" + side, 2)
		var elbow_y := _range("elbow_" + side, 1)
		var gap := _range("gap_" + side)
		var clear := _range("clear_" + side)
		var part := _range("part_" + side)
		var legd := _range("legd_" + side)
		print("  %s: lower raise part (arm rig) %.2f to %.2f" % [side, part.x, part.y])
		print("  %s: shoulder raise mean %.1f deg (%.1f to %.1f), swing %.1f to %.1f deg" % [side, _mean("abd_" + side),
				abd.x, abd.y, swing.x, swing.y])
		print("     hand travel: up %.2f m, fore-aft %.2f m; elbow fore-aft %.2f m, up %.2f m; hand-forearm gap max %.3f m; largest hand step %.3f m/frame; hand out past knee min %.2f m" % [
				hand_y.y - hand_y.x, hand_z.y - hand_z.x, elbow_z.y - elbow_z.x, elbow_y.y - elbow_y.x, gap.y, _largest_step("hand_" + side, 0), clear.x])
		print("     clip swing further turn out (keep off) max %.1f deg; palm/wrist to torso and pelvis armor boxes min %.2f m; upper arm most forward at stride phase %.2f" % [
				_range("out_" + side).y, _range("body_" + side).x, _peak_phase("swing_" + side)])
		print("     palm/wrist to leg lines min %.2f m; hand most forward at stride phase %.2f (0 = left foot lands); hand side |x| min %.2f m, up %.2f to %.2f m" % [
				legd.x, _forward_phase("hand_" + side), minf(absf(_range("hand_" + side, 0).x), absf(_range("hand_" + side, 0).y)), hand_y.x, hand_y.y])


## Largest hand move from one sample to the next (m), from sample index start.
func _largest_step(key: String, start: int) -> float:
	var largest := 0.0
	for i in range(maxi(start, 1), _rows.size()):
		largest = maxf(largest, (_rows[i][key] as Vector3).distance_to(_rows[i - 1][key] as Vector3))
	return largest


func _report_combo() -> void:
	var end := -1
	for i in range(1, _rows.size()):
		if _rows[i - 1].playing and not _rows[i].playing:
			end = i
			break
	print("punch: %d samples, attack ends at sample %d" % [_rows.size(), end])
	if end < 0:
		return
	var hand := "hand_L"
	var steps: PackedStringArray = []
	for i in range(maxi(end - 5, 1), mini(end + 60, _rows.size())):
		steps.append("%.2f" % (_rows[i][hand] as Vector3).distance_to(_rows[i - 1][hand] as Vector3))
	print("  left hand step per frame from 5 frames before the end: %s" % ", ".join(steps))
	print("  largest left hand step after the end: %.3f m/frame; hand-forearm gap max %.3f m" % [
			_largest_step(hand, end), _range("gap_L").y])
	var settle := -1
	for i in range(_rows.size() - 1, end, -1):
		if (_rows[i][hand] as Vector3).distance_to(_rows[i - 1][hand] as Vector3) > 0.02:
			settle = i
			break
	print("  hand settles %.2f s after the attack end" % (float(settle - end) / 60.0))


## The source Mixamo clip as a stick figure (a box per bone on its own skeleton): front and side pictures
## at four points of one cycle (0, 25, 50, 75 percent of the clip).
func _render_source_clip(out: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var source := (load(_env("ARMS_CLIP", "res://models/mixamo/library/Slow Run - arm swing.fbx")) as PackedScene).instantiate() as Node3D
	world.add_child(source)
	# The FBX skeleton imports about 0.08 m tall: scaled to about 1.8 m.
	source.scale = Vector3.ONE * 22.0
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.6, 0.65)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	camera.current = true
	await _frames(2)
	var skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clip := player.get_animation_list()[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	var length := player.get_animation(clip).length
	# One box per bone (parent to child), colored: left arm red, right arm blue, legs dark, body grey.
	var sticks: Array = []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var name := skeleton.get_bone_name(bone)
		if parent < 0 or name.contains("Hand") and not name.ends_with("Hand") or name.ends_with("_End"):
			continue
		var stick := MeshInstance3D.new()
		var box := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.2, 0.2) if name.contains("Left") and (name.contains("Arm") or name.contains("Hand") or name.contains("Shoulder")) \
				else Color(0.2, 0.35, 0.9) if name.contains("Right") and (name.contains("Arm") or name.contains("Hand") or name.contains("Shoulder")) \
				else Color(0.25, 0.25, 0.25) if name.contains("Leg") or name.contains("Foot") or name.contains("Toe") else Color(0.75, 0.75, 0.75)
		box.material = material
		stick.mesh = box
		world.add_child(stick)
		sticks.append([stick, parent, bone])
	var fronts: Array[Image] = []
	var sides: Array[Image] = []
	for mark: float in [0.0, 0.25, 0.5, 0.75]:
		player.seek(mark * length, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var top := 0.0
		for entry: Array in sticks:
			var a := skeleton.global_transform * skeleton.get_bone_global_pose(entry[1]).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_pose(entry[2]).origin
			var stick := entry[0] as MeshInstance3D
			var length_ab := a.distance_to(b)
			var width := 0.07
			(stick.mesh as BoxMesh).size = Vector3(width, maxf(length_ab, 0.01), width)
			var y := (b - a).normalized() if length_ab > 0.0001 else Vector3.UP
			var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
			stick.global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
			top = maxf(top, b.y)
		var hips := skeleton.global_transform * skeleton.get_bone_global_pose(0).origin
		var chest := Vector3(hips.x, top * 0.55, hips.z)
		if mark == 0.0:
			print("source clip figure: top %.2f m, hips %s, skeleton scale %s" % [top, hips, skeleton.global_transform.basis.get_scale()])
		for view in ["front", "side"]:
			# The Mixamo model faces +Z, its left side at +X; the side view looks at its right side.
			camera.look_at_from_position(chest + (Vector3.BACK if view == "front" else Vector3.LEFT) * top * 4.0, chest)
			await _frames(1)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png("%s/%s_p%02d.png" % [out, view, int(mark * 100.0)])
			(fronts if view == "front" else sides).append(image)
	_save_strip(fronts, out + "/strip_front.png")
	_save_strip(sides, out + "/strip_side.png")
	print("source clip %s: %.2f s" % [clip, length])
