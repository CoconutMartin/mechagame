class_name MechHand
extends Node3D
## A jointed mech hand (user drawings 2026-10-13; model: tools/blender/mech_hand_build.py). Four fingers
## and a thumb, three joints each (empties Index1..3, Middle1..3, Ring1..3, Pinky1..3, Thumb1..3 in the
## model); each joint bends about its own X axis (negative = toward the palm).
## Modes: OPEN, RELAXED (a little bent), FIST, GRIP. GRIP fits the fingers to a grip: each finger closes
## until it touches a cylinder (center, axis, radius from MechHandControl), so one hand holds thin and
## thick grips. The fingers move toward their pose at close_speed, never in one jump.
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
## name -> bend now (0..1)
var _curl := {}


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
	for name: String in _joints:
		var target := relaxed_curl
		match mode:
			Mode.OPEN:
				target = open_thumb_curl if name == "Thumb" else open_curl
			Mode.FIST:
				target = fist_curl
			Mode.GRIP:
				target = _fit(name, center, axis)
		_curl[name] = move_toward(_curl[name], target, close_speed * delta)
		_apply(name, _curl[name])


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


## The smallest bend at which the finger touches the grip cylinder (hand space); a full fist if it
## never does.
func _fit(name: String, center: Vector3, axis: Vector3) -> float:
	var step := 0.05
	# The thumb starts swung out (it lies on the other side of the grip).
	var c := open_thumb_curl if name == "Thumb" else 0.0
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
