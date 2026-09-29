class_name PowerDownPose
extends Node
## The "power down" pose of a dead mech: both arms hang straight down, both legs crouch, the torso
## sags forward. start() blends to it from the pose the mech has now. The normal animation nodes
## must be off (MechDeath turns them off). Missing parts (fallen arms) are skipped.

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
## Seconds to reach the pose.
@export var blend_time: float = 1.0

var active: bool = false

var _time: float = 0.0
var _start := {}
var _target := {}
var _upper_start_y: float = 0.0
var _upper_target_y: float = 0.0


func _ready() -> void:
	# After the other pose nodes, if some still run.
	process_physics_priority = 12


## Starts the blend to the power down pose.
func start() -> void:
	if active:
		return
	active = true
	_time = 0.0
	var hip := deg_to_rad(hip_deg)
	var knee := deg_to_rad(knee_deg)
	var targets := {
		shoulder_left: Basis.IDENTITY, shoulder_right: Basis.IDENTITY,
		elbow_left: Basis.IDENTITY, elbow_right: Basis.IDENTITY,
		hip_left: Basis(Vector3.RIGHT, hip), hip_right: Basis(Vector3.RIGHT, hip),
		knee_left: Basis(Vector3.RIGHT, -knee), knee_right: Basis(Vector3.RIGHT, -knee),
		torso: Basis(Vector3.RIGHT, -deg_to_rad(torso_sag_deg)),
	}
	for joint: Node3D in targets:
		if joint != null:
			_start[joint] = joint.basis.orthonormalized().get_rotation_quaternion()
			_target[joint] = targets[joint].get_rotation_quaternion()
	# Feet stay on the ground: the hips drop by how much shorter the bent legs are.
	var shin_angle := hip - knee
	var height := thigh_length * cos(hip) + shin_length * cos(shin_angle)
	_upper_start_y = upper_body.position.y
	_upper_target_y = -(thigh_length + shin_length - height)


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
