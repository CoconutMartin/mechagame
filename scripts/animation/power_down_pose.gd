class_name PowerDownPose
extends Node
## The "power down" pose of a dead mech: the legs crouch, the torso sags forward, and the arms go
## limp. Limp arms hang toward the ground with gravity (the hands on a soft spring, so they swing
## a little when the body moves or falls), with the elbows a little bent. A hand that would go into
## the ground rests on it and the elbow bends (two-bone IK). start() blends from the pose the mech
## has now. The normal animation nodes must be off (MechDeath turns them off).

@export var mech: Mech
@export var shoulder_left: Node3D
@export var shoulder_right: Node3D
@export var elbow_left: Node3D
@export var elbow_right: Node3D
@export var hip_left: Node3D
@export var hip_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
@export var torso: Node3D
## Holds the torso and the legs. The crouch lowers it so the feet stay on the ground.
@export var upper_body: Node3D

## Leg crouch: hip bend forward and knee bend, in degrees.
@export var hip_deg: float = 35.0
@export var knee_deg: float = 70.0
## Thigh and shin length in meters (for the crouch drop).
@export var thigh_length: float = 2.6
@export var shin_length: float = 2.6
## Torso sag forward, in degrees.
@export var torso_sag_deg: float = 10.0
## Seconds to reach the leg and torso pose.
@export var blend_time: float = 1.0

@export_group("Limp arms")
## Upper and lower arm length, in meters.
@export var upper_arm: float = 2.7
@export var lower_arm: float = 3.0
## Hanging hand distance from the shoulder, as a part of the full arm length (less = more elbow bend).
@export_range(0.5, 1.0) var hang_reach: float = 0.93
## Hand swing spring: oscillations per second and damping (low damping = more swing).
@export var swing_frequency: float = 1.1
@export_range(0.05, 1.0) var swing_damping: float = 0.35
## Hand height above the ground when it rests on it, in meters.
@export var palm_height: float = 0.35

var active: bool = false

var _time: float = 0.0
var _start := {}
var _target := {}
var _upper_start_y: float = 0.0
var _upper_target_y: float = 0.0
var _hands := {}
var _hand_speeds := {}


func _ready() -> void:
	# After MechFall moves the body, and after the other pose nodes.
	process_physics_priority = 13


## Starts the blend to the power down pose.
func start() -> void:
	if active:
		return
	active = true
	_time = 0.0
	var hip := deg_to_rad(hip_deg)
	var knee := deg_to_rad(knee_deg)
	var targets := {
		hip_left: Basis(Vector3.RIGHT, hip), hip_right: Basis(Vector3.RIGHT, hip),
		knee_left: Basis(Vector3.RIGHT, -knee), knee_right: Basis(Vector3.RIGHT, -knee),
		torso: Basis(Vector3.RIGHT, -deg_to_rad(torso_sag_deg)),
	}
	for joint: Node3D in targets:
		if joint != null:
			_start[joint] = joint.basis.orthonormalized().get_rotation_quaternion()
			_target[joint] = targets[joint].get_rotation_quaternion()
	# Feet stay on the ground: the hips drop by how much shorter the bent legs are.
	var height := thigh_length * cos(hip) + shin_length * cos(hip - knee)
	_upper_start_y = upper_body.position.y
	_upper_target_y = -(thigh_length + shin_length - height)
	# The hands start where they are and have no speed.
	for side: float in [-1.0, 1.0]:
		var elbow := elbow_right if side > 0.0 else elbow_left
		if elbow != null:
			_hands[side] = elbow.global_transform * Vector3(0.0, -lower_arm, 0.0)
			_hand_speeds[side] = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not active:
		return
	_time += delta
	var t := smoothstep(0.0, 1.0, clampf(_time / blend_time, 0.0, 1.0))
	for joint: Node3D in _start:
		if is_instance_valid(joint):
			var rotation: Quaternion = (_start[joint] as Quaternion).slerp(_target[joint], t)
			joint.basis = Basis(rotation)
	upper_body.position.y = lerpf(_upper_start_y, _upper_target_y, t)
	_limp_arms(delta)


## Each hand swings on a spring toward the hanging point below its shoulder (never into the ground).
func _limp_arms(delta: float) -> void:
	var stiffness := pow(TAU * swing_frequency, 2.0)
	var damping := 2.0 * swing_damping * TAU * swing_frequency
	var ground := mech.global_position.y + palm_height
	for side: float in _hands:
		var shoulder := shoulder_right if side > 0.0 else shoulder_left
		var elbow := elbow_right if side > 0.0 else elbow_left
		if not is_instance_valid(shoulder) or not is_instance_valid(elbow):
			continue
		var target := shoulder.global_position + Vector3.DOWN * (upper_arm + lower_arm) * hang_reach
		target.y = maxf(target.y, ground)
		var hand: Vector3 = _hands[side]
		var speed: Vector3 = _hand_speeds[side]
		speed += ((target - hand) * stiffness - speed * damping) * delta
		hand += speed * delta
		hand.y = maxf(hand.y, ground)
		_hands[side] = hand
		_hand_speeds[side] = speed
		# The elbow points back, the natural way a hanging arm bends.
		var pole := (torso.global_basis.z + torso.global_basis.x * side * 0.3).normalized()
		TwoBoneIK.solve_to(shoulder, elbow, hand, pole, upper_arm, lower_arm)
