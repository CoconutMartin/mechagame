class_name FallPose
extends Node
## Arm and leg pose while a living mech falls over and gets up (MechFall tilts the body).
## The hands go to points in the world (two-bone IK), so they meet the ground like real hands:
##   Fall: the knees buckle. As the body passes about 15°, the arms reach for the ground ahead of the
##         fall, a little wider than the shoulders. Side fall: the arm on that side reaches out and
##         the other arm comes in to the chest. Back fall: both hands reach back for the ground.
##   Impact: the hands stay where they touched the ground and the elbows bend as the chest comes down.
##   Roll: the hands fold in front of the chest.
##   Lying face down: the hands are flat on the ground beside the chest, elbows back (push-up).
##   Get up: the hands stay on the ground and the arms push the body up; one knee comes under the
##         body; then the hands leave the ground and go back to the sides as the mech stands.
## A dead mech uses PowerDownPose instead.

@export var mech: Mech
@export var mech_fall: MechFall
@export var shoulder_left: Node3D
@export var shoulder_right: Node3D
@export var elbow_left: Node3D
@export var elbow_right: Node3D
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
@export var torso: Node3D
## Holds the torso and the legs. It drops when the legs bend.
@export var upper_body: Node3D

@export_group("Arms")
## Upper and lower arm length (shoulder to elbow, elbow to hand), in meters.
@export var upper_arm: float = 2.7
@export var lower_arm: float = 3.0
## How fast the hands move to their targets (1 / seconds), and while they come under the shoulders
## before the get-up.
@export var hand_speed: float = 9.0
@export var reposition_hand_speed: float = 4.5
## Fall: how far ahead of the shoulders the hands reach for the ground, and how wide, in meters.
@export var reach_ahead: float = 3.2
@export var reach_wide: float = 0.9
## Hand height above the ground (the palm), in meters.
@export var palm_height: float = 0.35
## Lying: hands beside the chest (out from the shoulder, and toward the head), in meters.
@export var push_wide: float = 1.0
@export var push_forward: float = 0.4
## Standby (arms at the sides) and folded (in front of the chest) hand places in torso space,
## for the right hand (the left hand is mirrored).
@export var standby_hand := Vector3(2.9, -1.4, -1.3)
@export var folded_hand := Vector3(0.7, 1.4, -2.3)

@export_group("Legs")
## How fast the leg joints follow their targets (1 / seconds).
@export var leg_speed: float = 7.0
## Knee buckle at the start of the fall, in degrees (hip, knee).
@export var buckle_hip_deg: float = 15.0
@export var buckle_knee_deg: float = 30.0
## Get up: kneel pose (front leg hip and knee, back leg hip and knee) in degrees.
@export var kneel_front_hip_deg: float = 80.0
@export var kneel_front_knee_deg: float = 95.0
@export var kneel_back_hip_deg: float = 20.0
@export var kneel_back_knee_deg: float = 110.0
@export var thigh_length: float = 2.6
@export var shin_length: float = 2.6

var _active: bool = false
## Hand positions now (world) and planted hand positions (world), by side (-1 left, +1 right).
var _hands := {}
var _planted := {}
var _last_state: int = -1


func _ready() -> void:
	# After MechFall (-1) and the other poses.
	process_physics_priority = 12
	# Custom skeletons: leg lengths from the frame, arm reach scaled with the upper arm.
	thigh_length = FrameMeasure.thigh(knee_left, thigh_length)
	shin_length = FrameMeasure.height(knee_left, mech, shin_length)
	var arm_scale: float = FrameMeasure.scale(elbow_left)
	upper_arm *= arm_scale
	lower_arm *= arm_scale


func _physics_process(delta: float) -> void:
	var down := mech_fall.is_down() and not mech.is_wrecked
	if not down:
		_active = false
		_hands.clear()
		_planted.clear()
		_last_state = -1
		return
	if not _active:
		_active = true
		for side in [-1.0, 1.0]:
			_hands[side] = _hand_now(side)
	var state := mech_fall.state
	if state != _last_state:
		_on_state_changed(state)
		_last_state = state
	# Slower, careful hand moves while the mech gets ready to push up.
	var speed := reposition_hand_speed if state == MechFall.State.REPOSITION else hand_speed
	var weight := 1.0 - exp(-speed * delta)
	for side: float in [-1.0, 1.0]:
		var target := _hand_target(side)
		_hands[side] = (_hands[side] as Vector3).lerp(target, weight)
		_solve_arm(side, _hands[side])
	_update_legs(delta)


func _on_state_changed(state: int) -> void:
	match state:
		MechFall.State.IMPACT:
			# The hands stay where they touch the ground.
			for side: float in [-1.0, 1.0]:
				_planted[side] = _on_ground(_hands[side])
		MechFall.State.ROLL, MechFall.State.REPOSITION, MechFall.State.LIE:
			_planted.clear()
		MechFall.State.GET_UP:
			# The hands press down where they are now.
			for side: float in [-1.0, 1.0]:
				_planted[side] = _on_ground(_hands[side])


## Where one hand goes now (world).
func _hand_target(side: float) -> Vector3:
	var state := mech_fall.state
	var t := mech_fall.state_time
	match state:
		MechFall.State.STEPS:
			return _torso_point(standby_hand, side)
		MechFall.State.FALL:
			var reach := smoothstep(0.25, 0.65, t / mech_fall.fall_time)
			return _torso_point(standby_hand, side).lerp(_reach_point(side), reach)
		MechFall.State.IMPACT, MechFall.State.SETTLE:
			return _planted.get(side, _reach_point(side))
		MechFall.State.ROLL:
			return _torso_point(folded_hand, side)
		MechFall.State.REPOSITION, MechFall.State.LIE:
			return _push_point(side)
		MechFall.State.GET_UP:
			var p := t / mech_fall.get_up_time
			var lift := smoothstep(0.55, 0.9, p)
			var planted: Vector3 = _planted.get(side, _push_point(side))
			return planted.lerp(_torso_point(standby_hand, side), lift)
	return _torso_point(standby_hand, side)


## Fall: the point on the ground this hand reaches for.
func _reach_point(side: float) -> Vector3:
	var shoulder := _shoulder(side).global_position
	var fall := mech_fall.get_world_direction()
	var out := torso.global_basis.x.normalized() * side
	out.y = 0.0
	out = out.normalized()
	var sideways := fall.dot(out)
	var point: Vector3
	if sideways > 0.6:
		# Side fall toward this arm: it reaches out to that side.
		point = shoulder + fall * reach_ahead * 1.1
	elif sideways < -0.6:
		# Side fall away from this arm: it comes in to the chest.
		return _torso_point(folded_hand, side)
	else:
		point = shoulder + fall * reach_ahead + out * reach_wide
	return _on_ground(point)


## Lying face down: a hand flat on the ground beside the chest.
func _push_point(side: float) -> Vector3:
	var shoulder := _shoulder(side).global_position
	var out := torso.global_basis.x.normalized() * side
	out.y = 0.0
	var head := torso.global_basis.y
	head.y = 0.0
	return _on_ground(shoulder + out.normalized() * push_wide + head.normalized() * push_forward)


func _solve_arm(side: float, hand: Vector3) -> void:
	var shoulder := _shoulder(side)
	var elbow := elbow_right if side > 0.0 else elbow_left
	if shoulder == null or elbow == null:
		return
	# Elbows point back along the body and out to the side.
	var body_down := -torso.global_basis.y
	var out := torso.global_basis.x * side
	var pole := (body_down * 0.7 + out * 0.6 + torso.global_basis.z * 0.4).normalized()
	TwoBoneIK.solve_to(shoulder, elbow, hand, pole, upper_arm, lower_arm)


func _hand_now(side: float) -> Vector3:
	var elbow := elbow_right if side > 0.0 else elbow_left
	return elbow.global_transform * Vector3(0.0, -lower_arm, 0.0)


func _shoulder(side: float) -> Node3D:
	return shoulder_right if side > 0.0 else shoulder_left


## A point in torso space for the right hand, mirrored for the left hand (world).
func _torso_point(right_point: Vector3, side: float) -> Vector3:
	return torso.global_transform * Vector3(right_point.x * side, right_point.y, right_point.z)


## The same point at palm height on the ground.
func _on_ground(point: Vector3) -> Vector3:
	return Vector3(point.x, mech.global_position.y + palm_height, point.z)


func _update_legs(delta: float) -> void:
	var weight := 1.0 - exp(-leg_speed * delta)
	var targets := _leg_targets()
	for joint: Node3D in targets:
		var target: Quaternion = (targets[joint] as Basis).get_rotation_quaternion()
		var now := joint.basis.orthonormalized().get_rotation_quaternion()
		joint.basis = Basis(now.slerp(target, weight))
	torso.basis = Basis(torso.basis.orthonormalized().get_rotation_quaternion().slerp(Quaternion.IDENTITY, weight))
	upper_body.position.y = lerpf(upper_body.position.y, -_leg_drop(targets), weight)


## Hip and knee targets by MechFall state.
func _leg_targets() -> Dictionary:
	var result := {}
	match mech_fall.state:
		MechFall.State.STEPS, MechFall.State.FALL:
			_set_legs(result, buckle_hip_deg, buckle_knee_deg, buckle_hip_deg, buckle_knee_deg)
		MechFall.State.IMPACT, MechFall.State.SETTLE, MechFall.State.LIE:
			_set_legs(result, 0.0, 5.0, 0.0, 5.0)
		MechFall.State.ROLL:
			_set_legs(result, 0.0, 0.0, 0.0, 0.0)
		MechFall.State.REPOSITION:
			# The knees start to bend, ready to come under the body.
			_set_legs(result, 5.0, 15.0, 0.0, 10.0)
		MechFall.State.GET_UP:
			var p := mech_fall.state_time / mech_fall.get_up_time
			# The front knee comes under the body while the arms push, then the legs straighten.
			var kneel := smoothstep(0.2, 0.5, p) * (1.0 - smoothstep(0.5, 1.0, p))
			var early := 1.0 - smoothstep(0.0, 0.3, p)
			_set_legs(result, lerpf(5.0 * early, kneel_front_hip_deg, kneel), lerpf(15.0 * early, kneel_front_knee_deg, kneel),
					lerpf(0.0, kneel_back_hip_deg, kneel), lerpf(10.0 * early, kneel_back_knee_deg, kneel))
	return result


## Hip and knee bends in degrees. The left leg is the front leg when kneeling.
func _set_legs(result: Dictionary, left_hip: float, left_knee: float, right_hip: float, right_knee: float) -> void:
	result[hip_left] = Basis(Vector3.RIGHT, deg_to_rad(left_hip))
	result[knee_left] = Basis(Vector3.RIGHT, -deg_to_rad(left_knee))
	result[hip_right] = Basis(Vector3.RIGHT, deg_to_rad(right_hip))
	result[knee_right] = Basis(Vector3.RIGHT, -deg_to_rad(right_knee))


## Body drop so the feet stay on the ground with the legs bent (the lower foot counts).
func _leg_drop(targets: Dictionary) -> float:
	var drops: Array[float] = []
	for pair in [[hip_left, knee_left], [hip_right, knee_right]]:
		var hip: float = (targets.get(pair[0], Basis.IDENTITY) as Basis).get_euler().x
		var knee: float = (targets.get(pair[1], Basis.IDENTITY) as Basis).get_euler().x
		var height := thigh_length * cos(hip) + shin_length * cos(hip + knee)
		drops.append(thigh_length + shin_length - height)
	return minf(drops[0], drops[1])
