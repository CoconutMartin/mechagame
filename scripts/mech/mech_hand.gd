class_name MechHand
extends Node3D
## A jointed mech hand (user drawings 2026-10-13; model: tools/blender/mech_hand_build.py). Four fingers
## and a thumb, three joints each (empties Index1..3, Middle1..3, Ring1..3, Pinky1..3, Thumb1..3 in the
## model); each joint bends about its own X axis (negative = toward the palm).
## Modes: OPEN, RELAXED (a little bent), FIST, GRIP. GRIP fits the fingers to a grip: each finger closes
## until it touches a cylinder (center, axis, radius from MechHandControl), so one hand holds thin and
## thick grips. The fingers move toward their pose at close_speed, never in one jump.
## The thumb wraps the grip (user request 2026-10-22: the thumb grips over the weapon handle): it turns
## to the heading (from a small set) whose closed pose goes farthest around the grip, then its joints close
## one after the other, each until its segment touches the grip or a finger. So the thumb lies across the
## front of the grip and meets the fingertips, like a human thumb.
## This node is the hand frame: origin at the wrist, +Y to the fingers, +Z to the back of the hand.

enum Mode { OPEN, RELAXED, FIST, GRIP }

const FINGERS := ["Index", "Middle", "Ring", "Pinky", "Thumb"]

## Largest bend of joints 1, 2, 3 of a finger, and of the thumb (degrees).
@export var finger_max_deg: Vector3 = Vector3(85.0, 100.0, 75.0)
@export var thumb_max_deg: Vector3 = Vector3(50.0, 55.0, 60.0)
## Bend (0 = straight, 1 = full) for OPEN, RELAXED and FIST.
@export var open_curl: float = 0.04
@export var relaxed_curl: float = 0.3
@export var fist_curl: float = 1.0
## Thumb bend when OPEN (below 0 = swung out from the palm, like the open drawing).
@export var open_thumb_curl: float = -0.5
## GRIP: bend of a finger that touches the grip already when open (the grip runs through it).
@export var wrapped_curl: float = 0.8
## Sideways spread of each finger when open (degrees, + = away from the middle; scaled down as it bends).
@export var open_spread_deg: Dictionary = {"Index": 7.0, "Middle": 2.0, "Ring": 3.0, "Pinky": 8.0}
## How fast a finger bends (part of the full bend per second).
@export var close_speed: float = 4.0
## Finger and thumb thickness (radius, meters) for the grip fit.
@export var finger_radius: float = 0.075
@export var thumb_radius: float = 0.08
## GRIP: the thumb is rated by how far its tip goes around the grip (degrees of turn about the grip axis from
## its root toward the palm front). The tip should stay within this far of the grip surface (meters, the
## thumb's own radius not counted) and within this far along the grip from the fingers' middle.
@export var thumb_reach_out: float = 0.2
@export var thumb_reach_along: float = 0.12
## GRIP: the thumb may bend back by this part of its open swing when the grip is in its way.
@export_range(0.0, 1.0) var thumb_back_off: float = 0.5
## GRIP: angle step of the thumb search (degrees), and how often the search halves the last step.
@export var thumb_step_deg: float = 6.0
@export var thumb_refine: int = 3
## GRIP: the thumb search runs again only when the grip moved this much (meters) and at most this often (seconds).
@export var thumb_resolve_move: float = 0.01
@export var thumb_resolve_s: float = 0.3
## GRIP: headings the thumb may take (right hand frame, the left mirrors them): the direction turns
## about the hand's Z by these azimuths from +X, tips down toward the palm side by these angles
## (degrees), and the thumb's bend axis rolls by these angles about its direction.
@export var thumb_azimuths: PackedFloat32Array = [0.0, 30.0, 60.0, 90.0, 120.0]
@export var thumb_elevations: PackedFloat32Array = [-30.0, -60.0, -80.0]
@export var thumb_rolls: PackedFloat32Array = [30.0, 90.0, 150.0, 210.0]
## A finger stops this much short of the grip surface (meters).
@export var grip_gap: float = 0.005

var mode: Mode = Mode.RELAXED
## Grip cylinder in world space (set with set_grip).
var grip_center: Vector3 = Vector3.ZERO
var grip_axis: Vector3 = Vector3.UP
var grip_radius: float = 0.12

## name -> [joint1, joint2, joint3]
var _joints := {}
## joint -> rest transform (parent space)
var _rest := {}
## name -> distal segment length (joint 3 to the tip)
var _tip := {}
## name -> bend now (0..1); the thumb has its own state below
var _curl := {}
## Thumb now: a turn of its curl plane (in joint 1's own frame) and the bend of its three joints (radians).
var _thumb_turn := Quaternion.IDENTITY
var _thumb_bend := Vector3.ZERO
## Thumb wrap found for the last grip and finger poses (turn and bends), and what it was found for
## (_wrap_key, to skip the search). _wrap_tip is its tip place (hand space) and _wrap_angle its turn about
## the grip axis (degrees).
var _wrap_turn := Quaternion.IDENTITY
var _wrap_bend := Vector3.ZERO
var _wrap_key := PackedFloat32Array()
var _wrap_tip := Vector3.ZERO
var _wrap_angle := 0.0
## Seconds since the last thumb search, and how many searches ran (for tests).
var _wrap_age := 0.0
var wrap_searches: int = 0


func _ready() -> void:
	for name: String in FINGERS:
		var list: Array[Node3D] = []
		for i in 3:
			var joint := find_child("%s%d" % [name, i + 1], true, false) as Node3D
			if joint == null:
				break
			list.append(joint)
			_rest[joint] = joint.transform
		if list.size() == 3:
			_joints[name] = list
			_curl[name] = relaxed_curl
			_tip[name] = _distal_length(name, list[2])


## Holds a grip: the fingers close around the cylinder (world space).
func set_grip(center: Vector3, axis: Vector3, radius: float) -> void:
	mode = Mode.GRIP
	grip_center = center
	grip_axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.UP
	grip_radius = radius


func _process(delta: float) -> void:
	var to_local := global_transform.affine_inverse()
	var center := to_local * grip_center
	var axis := (to_local.basis * grip_axis).normalized()
	var fitted := {}
	for name: String in _joints:
		if name == "Thumb":
			continue
		var target := relaxed_curl
		match mode:
			Mode.OPEN:
				target = open_curl
			Mode.FIST:
				target = fist_curl
			Mode.GRIP:
				target = _fit(name, center, axis)
		fitted[name] = target
		_curl[name] = move_toward(_curl[name], target, close_speed * delta)
		_apply(name, _curl[name])
	if _joints.has("Thumb"):
		_wrap_age += delta
		_move_thumb(delta, center, axis, fitted)


## Bend of each joint at curl c (radians, negative = toward the palm).
func _angles(name: String, c: float) -> Vector3:
	var top := thumb_max_deg if name == "Thumb" else finger_max_deg
	return -Vector3(deg_to_rad(top.x), deg_to_rad(top.y), deg_to_rad(top.z)) * c


func _apply(name: String, c: float) -> void:
	var a := _angles(name, c)
	var list: Array = _joints[name]
	for i in 3:
		var joint: Node3D = list[i]
		var rest: Transform3D = _rest[joint]
		var turn := Basis(Vector3.RIGHT, a[i])
		if i == 0 and open_spread_deg.has(name):
			# Spread about the joint's Z (sideways); the sign puts it away from the middle finger.
			var side := signf(rest.origin.x - (_rest[_joints["Middle"][0]] as Transform3D).origin.x) if name != "Middle" else -1.0
			var amount := deg_to_rad(float(open_spread_deg[name])) * clampf(1.0 - c / maxf(relaxed_curl, 0.01), 0.0, 1.0)
			turn = Basis(Vector3.BACK, -side * amount) * turn
		joint.transform = rest * Transform3D(turn, Vector3.ZERO)


## Moves the thumb toward its pose: the wrap around a grip, or the curl of the mode.
func _move_thumb(delta: float, center: Vector3, axis: Vector3, fitted: Dictionary) -> void:
	var target_turn := Quaternion.IDENTITY
	var target_bend := Vector3.ZERO
	match mode:
		Mode.OPEN:
			target_bend = _angles("Thumb", open_thumb_curl)
		Mode.RELAXED:
			target_bend = _angles("Thumb", relaxed_curl)
		Mode.FIST:
			target_bend = _angles("Thumb", fist_curl)
		Mode.GRIP:
			_wrap_thumb(center, axis, fitted)
			target_turn = _wrap_turn
			target_bend = _wrap_bend
	# The plane turns and the joints close at close_speed (a full bend per 1 / close_speed seconds).
	var top := thumb_max_deg
	var rate := close_speed * delta
	var turn_angle := _thumb_turn.angle_to(target_turn)
	if turn_angle > 0.0:
		_thumb_turn = _thumb_turn.slerp(target_turn, minf(1.0, rate * PI * 0.5 / turn_angle))
	for i in 3:
		_thumb_bend[i] = move_toward(_thumb_bend[i], target_bend[i], rate * deg_to_rad(top[i]))
	_apply_thumb()


func _apply_thumb() -> void:
	var list: Array = _joints["Thumb"]
	for i in 3:
		var joint: Node3D = list[i]
		var turn := Basis(Vector3.RIGHT, _thumb_bend[i])
		if i == 0:
			turn = Basis(_thumb_turn) * turn
		joint.transform = (_rest[joint] as Transform3D) * Transform3D(turn, Vector3.ZERO)


## Finds the thumb wrap for a grip (hand space) and the fingers' poses; sets _wrap_turn and _wrap_bend.
## Per heading: joint 1 closes until its segment, or anything beyond it, touches the grip or a finger;
## then joint 2, then joint 3 (a joint blocked when straight bends back a little instead). The heading
## whose tip goes farthest around the grip (thumb_reach_out and thumb_reach_along limit it) wins; a coarse
## step ranks them, the winner is refined.
func _wrap_thumb(center: Vector3, axis: Vector3, fitted: Dictionary) -> void:
	var key := PackedFloat32Array([center.x, center.y, center.z, axis.x, axis.y, axis.z, grip_radius])
	var lines: Array[PackedVector3Array] = []
	for name: String in fitted:
		key.append(float(fitted[name]))
		lines.append(_finger_line(name, float(fitted[name])))
	if _same_key(key, _wrap_key):
		return
	# A grip that keeps moving a little does not start a new search each frame.
	if _wrap_key.size() > 0 and _wrap_age < thumb_resolve_s:
		return
	_wrap_key = key
	_wrap_age = 0.0
	wrap_searches += 1
	var list: Array = _joints["Thumb"]
	var base := _chain_base(list[0])
	base.basis = base.basis.orthonormalized()
	var mirror := signf(base.origin.x) > 0.0
	# Turn about the grip axis: 0 at the thumb root, positive toward the palm front (hand -Z).
	var root := base.origin - center
	var e1 := root - axis * root.dot(axis)
	e1 = e1.normalized() if e1.length_squared() > 0.0001 else Vector3.UP
	var front := Vector3.FORWARD - axis * Vector3.FORWARD.dot(axis)
	var e2 := (front - e1 * front.dot(e1)).normalized()
	var along_mid := 0.0
	for name: String in ["Index", "Middle"]:
		if fitted.has(name):
			along_mid += (_finger_line(name, float(fitted[name]))[3] - center).dot(axis) * 0.5
	var best_cost := INF
	var best := Quaternion.IDENTITY
	var best_bend := Vector3.ZERO
	for az in thumb_azimuths:
		for el in thumb_elevations:
			var heading := Vector3(cos(deg_to_rad(el)) * cos(deg_to_rad(az)), cos(deg_to_rad(el)) * sin(deg_to_rad(az)),
					sin(deg_to_rad(el)))
			var side := heading.cross(Vector3.BACK).normalized()
			for roll in thumb_rolls:
				var hinge := Basis(heading, deg_to_rad(roll)) * side
				var turn := _thumb_turn_for(base, heading, hinge, mirror)
				var bend := _close_thumb(base, turn, center, axis, lines, deg_to_rad(thumb_step_deg * 2.0), 0)
				if bend.x > 100.0:
					continue
				var tip: Vector3 = _thumb_points(base, bend, turn)[3] - center
				var angle := rad_to_deg(atan2(tip.dot(e2), tip.dot(e1)))
				var out := (tip - axis * tip.dot(axis)).length() - grip_radius - thumb_radius
				var cost := -angle + 300.0 * maxf(0.0, out - thumb_reach_out) \
						+ 300.0 * maxf(0.0, absf(tip.dot(axis) - along_mid) - thumb_reach_along)
				if cost < best_cost:
					best_cost = cost
					best = turn
					best_bend = bend
	_wrap_turn = best
	_wrap_bend = Vector3.ZERO
	if best_cost < INF:
		# Finer step for the winner (the coarse bends stand if the fine search cannot place the thumb).
		_wrap_bend = _close_thumb(base, best, center, axis, lines, deg_to_rad(thumb_step_deg), thumb_refine)
		if _wrap_bend.x > 100.0:
			_wrap_bend = best_bend
		_wrap_tip = _thumb_points(base, _wrap_bend, best)[3]
		var tip := _wrap_tip - center
		_wrap_angle = rad_to_deg(atan2(tip.dot(e2), tip.dot(e1)))
	else:
		_wrap_bend = _angles("Thumb", open_thumb_curl)
		_wrap_tip = _thumb_points(base, _wrap_bend, Quaternion.IDENTITY)[3]


## The turn (joint 1's frame) that gives the thumb a heading and a bend axis in hand space. The left
## hand mirrors them: heading mirrored in x, hinge mirrored and reversed (a mirror reverses turns).
func _thumb_turn_for(base: Transform3D, heading: Vector3, hinge: Vector3, mirror: bool) -> Quaternion:
	if mirror:
		heading.x = -heading.x
		hinge = Vector3(hinge.x, -hinge.y, -hinge.z)
	hinge = (hinge - heading * hinge.dot(heading)).normalized()
	var wanted := Basis(hinge, heading, hinge.cross(heading))
	return (base.basis.inverse() * wanted).orthonormalized().get_rotation_quaternion()


## The thumb's bends for a turn: each joint closes until it is blocked (step in radians, then refined).
## x = 1000 when a joint stays blocked even bent back.
func _close_thumb(base: Transform3D, turn: Quaternion, center: Vector3, axis: Vector3,
		lines: Array[PackedVector3Array], step: float, refine: int) -> Vector3:
	var bend := Vector3.ZERO
	for i in 3:
		var back := deg_to_rad(thumb_max_deg[i]) * open_thumb_curl * thumb_back_off
		if _thumb_blocked(base, turn, bend, i, 0.0, center, axis, lines):
			# Blocked when straight: back off a little (the grip is in the way of the thumb).
			var b := 0.0
			while b > back and _thumb_blocked(base, turn, bend, i, b, center, axis, lines):
				b -= step
			if _thumb_blocked(base, turn, bend, i, b, center, axis, lines):
				return Vector3(1000.0, 0.0, 0.0)
			bend[i] = -b
			continue
		var a := 0.0
		var high := deg_to_rad(thumb_max_deg[i])
		while a < high and not _thumb_blocked(base, turn, bend, i, a + step, center, axis, lines):
			a += step
		var low := a
		high = minf(a + step, high)
		for k in refine:
			var mid := (low + high) * 0.5
			if _thumb_blocked(base, turn, bend, i, mid, center, axis, lines):
				high = mid
			else:
				low = mid
		bend[i] = -low
	return bend


## True when the thumb, with joint i bent by -a (the earlier joints as in bend), has a segment from i on
## inside the grip cylinder or a finger.
func _thumb_blocked(base: Transform3D, turn: Quaternion, bend: Vector3, i: int, a: float, center: Vector3,
		axis: Vector3, lines: Array[PackedVector3Array]) -> bool:
	var angles := bend
	angles[i] = -a
	var points := _thumb_points(base, angles, turn)
	var grip_limit := grip_radius + thumb_radius + grip_gap
	var finger_limit := finger_radius + thumb_radius + grip_gap
	for s in range(i, 3):
		for k in range(1, 5):
			var p := points[s].lerp(points[s + 1], k / 4.0)
			var off := p - center
			if (off - axis * off.dot(axis)).length() < grip_limit:
				return true
			for line in lines:
				for j in 3:
					if _segment_distance(p, line[j], line[j + 1]) < finger_limit:
						return true
	return false


## Thumb joint places and the tip in hand space (joint 1, 2, 3, tip) for the wrap turn and a bend.
func _thumb_points(base: Transform3D, angles: Vector3, turn_start: Quaternion) -> PackedVector3Array:
	var list: Array = _joints["Thumb"]
	var points := PackedVector3Array([base.origin])
	var frame := base
	for i in 3:
		if i > 0:
			frame = frame * (_rest[list[i]] as Transform3D)
		var turn := Basis(Vector3.RIGHT, angles[i])
		if i == 0:
			turn = Basis(turn_start) * turn
		frame = frame * Transform3D(turn, Vector3.ZERO)
		var length: float = (_rest[list[i + 1]] as Transform3D).origin.length() if i < 2 else _tip["Thumb"]
		points.append(frame * Vector3(0.0, length, 0.0))
	return points


## A finger's joint places and tip in hand space at curl c.
func _finger_line(name: String, c: float) -> PackedVector3Array:
	var list: Array = _joints[name]
	var a := _angles(name, c)
	var frame := _chain_base(list[0])
	var points := PackedVector3Array([frame.origin])
	for i in 3:
		if i > 0:
			frame = frame * (_rest[list[i]] as Transform3D)
		frame = frame * Transform3D(Basis(Vector3.RIGHT, a[i]), Vector3.ZERO)
		var length: float = (_rest[list[i + 1]] as Transform3D).origin.length() if i < 2 else _tip[name]
		points.append(frame * Vector3(0.0, length, 0.0))
	return points


func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## True when two search keys match within thumb_resolve_move (so a steady grip is solved once).
func _same_key(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > thumb_resolve_move:
			return false
	return true


## The smallest bend at which the finger touches the grip cylinder (hand space); a full fist if it
## never does.
func _fit(name: String, center: Vector3, axis: Vector3) -> float:
	var step := 0.05
	var c := 0.0
	var start := c
	while c <= 1.0:
		if _touches(name, c, center, axis):
			break
		c += step
	if c > 1.0:
		return fist_curl
	# Touching already when open: the grip runs through the finger (a hand placed by an old pose);
	# a closed finger looks like holding it, a straight one does not.
	if c <= start:
		return wrapped_curl
	# Finer: back to just before the contact.
	var low := maxf(c - step, start)
	var high := c
	for i in 5:
		var mid := (low + high) * 0.5
		if _touches(name, mid, center, axis):
			high = mid
		else:
			low = mid
	return low


## True when the finger bent by c reaches the grip surface (points along its three segments).
func _touches(name: String, c: float, center: Vector3, axis: Vector3) -> bool:
	var list: Array = _joints[name]
	var a := _angles(name, c)
	var frame := _chain_base(list[0])
	var limit := grip_radius + finger_radius + grip_gap
	for i in 3:
		if i > 0:
			frame = frame * (_rest[list[i]] as Transform3D)
		frame = frame * Transform3D(Basis(Vector3.RIGHT, a[i]), Vector3.ZERO)
		var length: float = (_rest[list[i + 1]] as Transform3D).origin.length() if i < 2 else _tip[name]
		for k in range(1, 5):
			var p := frame * Vector3(0.0, length * k / 4.0, 0.0)
			var off := p - center
			if (off - axis * off.dot(axis)).length() < limit:
				return true
	return false


## Joint 1's rest transform in this hand's space.
func _chain_base(first: Node3D) -> Transform3D:
	var t: Transform3D = _rest[first]
	var node := first.get_parent_node_3d()
	while node != null and node != self:
		t = node.transform * t
		node = node.get_parent_node_3d()
	return t


func _distal_length(name: String, last: Node3D) -> float:
	var segment := last.find_child("%s3Segment*" % name, true, false) as MeshInstance3D
	if segment == null or segment.mesh == null:
		return 0.16
	var box := segment.transform * segment.get_aabb()
	return box.end.y
