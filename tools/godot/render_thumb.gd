extends SceneTree
## Thumb grip render and log (user request 2026-10-22: the thumb grips over the weapon handle). Gives the
## player THUMB_RIGHT / THUMB_LEFT (weapon file names, "" = none; defaults smg / ""), holds THUMB_ACTIONS
## (input actions, default none), waits 90 frames, then per hand logs (in the hand frame: origin at the wrist,
## +Y to the fingers, +Z to the back of the hand) the grip cylinder, the finger and thumb bends, the thumb
## joint places and the worst depth of finger and thumb points inside the grip. It saves close pictures
## from the hand's own sides (thumb_<side>_<view>.png in THUMB_OUT; views: thumb, palm, tip, over, pinky).
##   THUMB_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_thumb.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const ThumbProbe := preload("res://tools/godot/render_thumb_probe.gd")
## Camera distance from the hand (meters) and the point the camera looks at (hand frame).
const DISTANCE := 3.6
const LOOK_AT := Vector3(0.0, 0.7, 0.0)


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _run() -> void:
	var out := _env("THUMB_OUT", ProjectSettings.globalize_path("user://thumb_renders"))
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var right := _env("THUMB_RIGHT", "smg")
	var left := _env("THUMB_LEFT", "")
	loadout.weapon_right = load("res://data/weapons/%s.tres" % right) as WeaponData if right != "" else null
	loadout.weapon_left = load("res://data/weapons/%s.tres" % left) as WeaponData if left != "" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(30)
	# THUMB_GAP: the fingers' stop distance from the grip surface (MechHand.grip_gap), to compare.
	if _env("THUMB_GAP", "") != "":
		var control_now := switcher.mech.find_child("MechHandControl", true, false) as MechHandControl
		control_now.hand_right.grip_gap = float(_env("THUMB_GAP", "0.005"))
		control_now.hand_left.grip_gap = float(_env("THUMB_GAP", "0.005"))
	var actions := _env("THUMB_ACTIONS", "").split(",", false)
	for action in actions:
		Input.action_press(action)
	await _frames(int(_env("THUMB_FRAMES", "90")))
	var player := switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	var lines: Array = []
	var measure := func() -> void:
		if lines.is_empty():
			lines.append_array(_measure(control))
	skeleton.skeleton_updated.connect(measure)
	await _frames(3)
	skeleton.skeleton_updated.disconnect(measure)
	for line in lines:
		print(line)
	for action in actions:
		Input.action_release(action)
	# THUMB_BARE=1: the guns are hidden and a pale cylinder shows each grip (radius from the socket), to
	# see the hand alone.
	if _env("THUMB_BARE", "") == "1":
		_show_grips(map, control)
	# THUMB_SLICES=1: the gun's shape along its grip socket (slices every 0.1 m up the grip).
	if _env("THUMB_SLICES", "") == "1":
		print(_slices(control))
	# The thumb in orange, to see it against the dark hand and guns (THUMB_PAINT: sides, default "R").
	for side in _env("THUMB_PAINT", "R"):
		var painted: MechHand = control.hand_right if side == "R" else control.hand_left
		if painted != null and is_instance_valid(painted):
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color(1.0, 0.55, 0.1)
			for part in painted.find_children("Thumb*", "MeshInstance3D", true, false):
				(part as MeshInstance3D).material_override = paint
	var camera := Camera3D.new()
	camera.fov = 30.0
	map.add_child(camera)
	camera.current = true
	for side in ["R", "L"]:
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand == null or not is_instance_valid(hand):
			continue
		var tx := -1.0 if side == "R" else 1.0
		var views := {"thumb": Vector3(tx, 0.0, 0.0), "palm": Vector3(0.0, 0.0, -1.0), "tip": Vector3(0.0, 1.0, 0.0),
				"over": Vector3(tx * 0.6, 0.5, -0.8), "pinky": Vector3(-tx, 0.0, 0.0)}
		for view: String in views:
			var from := hand.global_transform * (LOOK_AT + (views[view] as Vector3).normalized() * DISTANCE)
			camera.look_at_from_position(from, hand.global_transform * LOOK_AT, Vector3.UP)
			await _frames(2)
			map.get_viewport().get_texture().get_image().save_png("%s/thumb_%s_%s.png" % [out, side, view])
	quit()


## Per hand: the grip in the hand frame, the bends, the thumb joints, and how deep finger and thumb
## points are inside the grip cylinder (meters; 0 = none).
func _measure(control: MechHandControl) -> PackedStringArray:
	var lines: PackedStringArray = []
	for side in ["R", "L"]:
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand == null or not is_instance_valid(hand) or hand.mode != MechHand.Mode.GRIP:
			continue
		var to_hand := hand.global_transform.affine_inverse()
		var center := to_hand * hand.grip_center
		var axis := (to_hand.basis * hand.grip_axis).normalized()
		var text := "%s hand: grip center %s axis %s radius %.3f" % [side, _v(center), _v(axis), hand.grip_radius]
		var curls := ""
		for name: String in hand._curl:
			curls += " %s %.2f" % [name, hand._curl[name]]
		curls += " Thumb deg (%.0f, %.0f, %.0f)" % [rad_to_deg(-hand._thumb_bend.x), rad_to_deg(-hand._thumb_bend.y), rad_to_deg(-hand._thumb_bend.z)]
		text += "\n    bends:" + curls
		var fitted := {}
		for name: String in hand._curl:
			if name != "Thumb":
				fitted[name] = hand._curl[name]
		var started := Time.get_ticks_usec()
		hand._wrap_key = PackedFloat32Array()
		hand._wrap_thumb(center, axis, fitted)
		text += "\n    thumb search: %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0)
		text += "\n    thumb wrap: tip %s, %.0f deg around the grip from its root" % [_v(hand._wrap_tip), hand._wrap_angle]
		for name: String in ["Thumb", "Index", "Middle", "Pinky"]:
			var joints: Array = hand._joints[name]
			var places := ""
			for joint: Node3D in joints:
				places += " %s" % _v(to_hand * joint.global_position)
			var tip: Vector3 = to_hand * (joints[2] as Node3D).global_transform * Vector3(0.0, hand._tip[name], 0.0)
			text += "\n    %s joints%s tip %s" % [name, places, _v(tip)]
		var gun: Node3D = control.weapons.right_weapon if side == "R" or control.weapons.two_handed_left_grip() else control.weapons.left_weapon
		if gun != null and is_instance_valid(gun):
			text += "\n    gun to arm bone lines: " + _arm_clearance(control, hand, gun, side)
		if gun != null and is_instance_valid(gun):
			text += "\n    deepest point in the gun mesh (m):" + _depths(hand, gun)
			text += "\n    deepest point in the handle only (m):" + _depths(hand, gun, true)
			# The hand moved down the grip by 0.1 .. 0.4 m: thumb joints 2 and 3 and the finger worst.
			for drop in [0.1, 0.2, 0.3, 0.4]:
				var moved := ThumbProbe.depths(hand, gun, -hand.grip_axis.normalized() * drop, 1)
				var fingers := 0.0
				for name: String in moved:
					if name != "Thumb":
						fingers = maxf(fingers, float(moved[name][0]))
				text += "\n      hand %.1f m lower: thumb (joints 2, 3) %.3f, fingers %.3f" % [drop, moved["Thumb"][0], fingers]
		lines.append(text)
	return lines


## Finger and thumb depths in the gun's mesh as text (see ThumbProbe.depths).
func _depths(hand: MechHand, gun: Node3D, handle_only: bool = false) -> String:
	var text := ""
	var depths := ThumbProbe.depths(hand, gun, Vector3.ZERO, 0, handle_only)
	for name: String in depths:
		var item: Array = depths[name]
		text += " %s %.3f%s" % [name, item[0], " at " + _v(item[1]) if float(item[0]) > 0.0 else ""]
	return text


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


## Hides the guns and puts a pale cylinder (the hand's grip: center, axis, radius) in each gripping hand.
func _show_grips(map: Node, control: MechHandControl) -> void:
	var weapons := control.weapons
	for gun: Node3D in [weapons.right_weapon, weapons.left_weapon]:
		if gun != null and is_instance_valid(gun):
			gun.visible = false
	for hand: MechHand in [control.hand_right, control.hand_left]:
		if hand == null or not is_instance_valid(hand) or hand.mode != MechHand.Mode.GRIP:
			continue
		var mesh := CylinderMesh.new()
		mesh.top_radius = hand.grip_radius
		mesh.bottom_radius = hand.grip_radius
		mesh.height = 1.6
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.9, 0.4, 0.2, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		map.add_child(node)
		var up := hand.grip_axis.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
		node.global_transform = Transform3D(Basis(side.cross(up), up, side), hand.grip_center)


## The right gun's vertices in the grip socket frame (+Y up the grip, +Z toward the butt, +X right), in
## slices of 0.1 m along Y: the box (x, z) of the points of each slice. Shows where the grip ends and the
## gun body starts.
func _slices(control: MechHandControl) -> String:
	var gun := control.weapons.right_weapon as Node3D
	var socket := gun.get_node_or_null("GripSocketRight") as Node3D
	if socket == null:
		return "no socket"
	var to_socket := socket.global_transform.orthonormalized().affine_inverse()
	var boxes := {}
	for v in ThumbProbe.gun_triangles(gun):
		var p := to_socket * v
		var key := int(floor(p.y / 0.1))
		var box: Array = boxes.get(key, [INF, -INF, INF, -INF])
		box = [minf(box[0], p.x), maxf(box[1], p.x), minf(box[2], p.z), maxf(box[3], p.z)]
		boxes[key] = box
	var keys := boxes.keys()
	keys.sort()
	var text := "grip slices (socket frame y: x min/max, z min/max):"
	for key: int in keys:
		if key < -8 or key > 10:
			continue
		var box: Array = boxes[key]
		text += "\n    y %+.1f: x %+.2f..%+.2f  z %+.2f..%+.2f" % [key * 0.1, box[0], box[1], box[2], box[3]]
	return text


## Nearest distance from the gun's mesh vertices to this arm's bone lines (upper arm to elbow, elbow to
## wrist), in meters; the armor is about 0.3 to 0.5 m thick around them, so only a change between two
## runs means something.
func _arm_clearance(control: MechHandControl, hand: MechHand, gun: Node3D, side: String) -> String:
	var skeleton := control.skeleton
	var points: Array[Vector3] = []
	for name in ["upper_arm_", "forearm_", "hand_"]:
		points.append((skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name + side))).origin)
	var triangles := ThumbProbe.gun_triangles(gun)
	var upper := INF
	var lower := INF
	for v in range(0, triangles.size(), 7):
		upper = minf(upper, _segment_distance(triangles[v], points[0], points[1]))
		lower = minf(lower, _segment_distance(triangles[v], points[1], points[2]))
	return "upper arm %.2f m, forearm %.2f m" % [upper, lower]


func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
