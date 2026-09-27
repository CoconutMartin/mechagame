class_name SkidBodyTurn
extends Node
## During a boost skid the whole body turns at an angle to the skid side (like a drift),
## then turns back to center during the recovery. Visual only: the aim and the camera do not turn.

@export var mech: Mech
## The whole mech visual (legs and torso).
@export var body: Node3D
## Random turn angle range, in degrees.
@export var turn_min_deg: float = 15.0
@export var turn_max_deg: float = 30.0
## Spring speed (swings per second). Lower = slower turn and return.
@export var frequency: float = 0.8
## Spring damping. 1.0 = smooth return with no swing past center.
@export_range(0.05, 1.0) var damping: float = 0.7

var _turn := AimSpring.new(0.0)
var _target: float = 0.0
var _was_skidding: bool = false


func _ready() -> void:
	# After the Mech moves, before the torso and arm poses.
	process_physics_priority = 2


func _physics_process(delta: float) -> void:
	if mech.is_skidding and not _was_skidding:
		_target = mech.skid_side * randf_range(turn_min_deg, turn_max_deg)
	_was_skidding = mech.is_skidding
	_turn.update(_target if mech.is_skidding else 0.0, frequency, damping, 90.0, delta)
	body.rotation.y = deg_to_rad(_turn.value)
