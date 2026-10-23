extends SceneTree
## Thumb wrap test (user request 2026-10-22: the thumb grips over the weapon handle). For each case (right
## weapon / left weapon, file names, "-" = none) it builds the loadout in the game, holds the actions, and
## inside skeleton_updated (where the modifier poses exist) checks every gripping hand:
##   - the thumb turns at least 60 deg around the grip (MechHand._wrap_angle),
##   - no thumb point (center, thumb radius) is inside the grip cylinder, and no thumb point touches a
##     finger (0.01 m of play),
##   - the fingers stay outside the grip cylinder the same way,
##   - the thumb search runs a few times only (at most about every 0.3 s, not every frame), also while the
##     grip moves (aim),
##   - one-hand guns: the thumb (joint 2 on) is at most 0.04 m into the gun's mesh (ThumbProbe); the
##     two-hand rifles and the Auto Cannon print it only.
## Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_thumb_wrap.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const ThumbProbe := preload("res://tools/godot/render_thumb_probe.gd")
## Cases: right weapon, left weapon, actions held after the build, mesh limit for the thumb (meters; -1 = print only).
const CASES := [
	["smg", "-", "", 0.04],
	["shotgun", "-", "", 0.04],
	["heavy_rifle", "-", "", 0.04],
	["auto_cannon", "-", "", -1.0],
	["beam_rifle", "-", "aim", -1.0],
	["beam_sniper", "-", "aim", -1.0],
	["-", "smg", "", 0.04],
	["smg", "smg", "", 0.04],
]
const MIN_WRAP_DEG := 60.0
## Points inside the cylinder or a finger by more than this fail (meters).
const PLAY := 0.01

var _failures: int = 0
var _switcher: LoadoutSwitcher


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


func _weapon(name: String) -> WeaponData:
	return null if name == "-" else load("res://data/weapons/%s.tres" % name) as WeaponData


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var level := current_scene
	for node in level.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	_switcher = level.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for case in CASES:
		await _case(case)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _case(case: Array) -> void:
	var label := "%s / %s" % [case[0], case[1]]
	var loadout := _switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = _weapon(case[0])
	loadout.weapon_left = _weapon(case[1])
	_switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(90)
	var player := _switcher.mech
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var control := player.find_child("MechHandControl", true, false) as MechHandControl
	var actions := String(case[2]).split(",", false)
	for action in actions:
		Input.action_press(action)
	var before := {}
	for hand: MechHand in [control.hand_right, control.hand_left]:
		before[hand] = hand.wrap_searches
	await _frames(150)
	var rows: Array = []
	var sample := func() -> void:
		if rows.is_empty():
			rows.append_array(_sample(control, float(case[3])))
	skeleton.skeleton_updated.connect(sample)
	await _frames(3)
	skeleton.skeleton_updated.disconnect(sample)
	for action in actions:
		Input.action_release(action)
	_check(not rows.is_empty(), "%s: a hand holds a grip" % label)
	for row in rows:
		var hand: MechHand = row.hand
		var text := "%s %s hand" % [label, row.side]
		_check(row.angle >= MIN_WRAP_DEG, "%s: the thumb turns %.0f deg around the grip (at least %.0f)" % [text, row.angle, MIN_WRAP_DEG])
		_check(row.thumb_grip >= -PLAY, "%s: the thumb stays out of the grip (worst %.3f m in)" % [text, maxf(0.0, -row.thumb_grip)])
		_check(row.thumb_finger >= -PLAY, "%s: the thumb stays off the fingers (worst %.3f m in)" % [text, maxf(0.0, -row.thumb_finger)])
		_check(row.finger_grip >= -PLAY, "%s: the fingers stay out of the grip (worst %.3f m in)" % [text, maxf(0.0, -row.finger_grip)])
		_check(hand.wrap_searches - int(before[hand]) <= 10, "%s: %d thumb searches in 150 frames (at most 10)" % [text, hand.wrap_searches - int(before[hand])])
		if row.mesh >= 0.0:
			if float(case[3]) >= 0.0:
				_check(row.mesh <= float(case[3]), "%s: the thumb is %.3f m into the gun mesh (at most %.2f)" % [text, row.mesh, float(case[3])])
			else:
				print("info %s: the thumb is %.3f m into the gun mesh (not limited for this gun)" % [text, row.mesh])


## One row per gripping hand: the wrap angle, the smallest clearance of thumb points to the grip cylinder
## and to the finger lines, of finger points to the cylinder (meters, negative = inside), and the thumb
## depth in the gun mesh (-1 when not measured).
func _sample(control: MechHandControl, mesh_limit: float) -> Array:
	var rows: Array = []
	for side in ["R", "L"]:
		var hand: MechHand = control.hand_right if side == "R" else control.hand_left
		if hand == null or not is_instance_valid(hand) or hand.mode != MechHand.Mode.GRIP:
			continue
		var to_hand := hand.global_transform.affine_inverse()
		var center := to_hand * hand.grip_center
		var axis := (to_hand.basis * hand.grip_axis).normalized()
		var lines := {}
		for name: String in hand._joints:
			lines[name] = _points(hand, name, to_hand)
		var thumb_grip := INF
		var finger_grip := INF
		var thumb_finger := INF
		for name: String in lines:
			var radius := hand.thumb_radius if name == "Thumb" else hand.finger_radius
			var points: PackedVector3Array = lines[name]
			for p in points:
				var off := p - center
				var clear := (off - axis * off.dot(axis)).length() - hand.grip_radius - radius
				if name == "Thumb":
					thumb_grip = minf(thumb_grip, clear)
				else:
					finger_grip = minf(finger_grip, clear)
		for p in lines["Thumb"]:
			for name: String in lines:
				if name == "Thumb":
					continue
				var finger: PackedVector3Array = lines[name]
				for k in range(3):
					var d := _segment_distance(p, finger[k], finger[k + 1]) - hand.thumb_radius - hand.finger_radius
					thumb_finger = minf(thumb_finger, d)
		var gun: Node3D = control.weapons.right_weapon if side == "R" or control.weapons.two_handed_left_grip() else control.weapons.left_weapon
		var mesh := -1.0
		if gun != null and is_instance_valid(gun):
			mesh = float(ThumbProbe.depths(hand, gun, Vector3.ZERO, 1)["Thumb"][0])
		rows.append({"hand": hand, "side": side, "angle": hand._wrap_angle, "thumb_grip": thumb_grip,
				"finger_grip": finger_grip, "thumb_finger": thumb_finger, "mesh": mesh})
	return rows


## Sample points along a finger (hand space): from the middle of the first segment on (the knuckle and
## the thumb mount are part of the hand), as a polyline of joint places for the finger distance and
## as extra points for the cylinder check. Returns the joint polyline with the tip: [j1, j2, j3, tip].
func _points(hand: MechHand, name: String, to_hand: Transform3D) -> PackedVector3Array:
	var joints: Array = hand._joints[name]
	var out := PackedVector3Array()
	for i in 3:
		out.append(to_hand * (joints[i] as Node3D).global_position)
	var tip: Vector3 = (joints[2] as Node3D).global_transform * Vector3(0.0, hand._tip[name], 0.0)
	out.append(to_hand * tip)
	# Cylinder and finger checks use the joint places beyond the first one and the segment middles.
	var dense := PackedVector3Array()
	for i in range(1, 4):
		dense.append(out[i])
		if i < 3:
			dense.append((out[i] + out[i + 1]) * 0.5)
	dense.append((out[0] + out[1]) * 0.5)
	# The polyline keeps four points for the segment distances; the dense set is for the cylinder.
	return _merge(out, dense)


## The joint polyline first (4 points), then the extra points (the finger checks read only the first 4).
func _merge(line: PackedVector3Array, extra: PackedVector3Array) -> PackedVector3Array:
	var out := line.duplicate()
	out.append_array(extra)
	return out


func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
