class_name PauldronFollow
extends Node
## Turns the shoulder armor (pauldrons) with the upper arms, so a raised arm (for example the
## blade overhead) lifts its pauldron. The pauldron pivots come from the arm part models
## (groups pauldron_l and pauldron_r). Runs after the arm IK.

@export var mech: Mech
@export var shoulder_left: Node3D
@export var shoulder_right: Node3D
## Arm angle from hanging straight down where the pauldron starts to follow, in degrees.
@export var start_deg: float = 35.0
## Pauldron turn = arm angle past start_deg x this value.
@export_range(0.0, 1.0) var follow: float = 0.55
## Largest pauldron turn, in degrees.
@export var max_deg: float = 65.0

var _pivots := {}


func _ready() -> void:
	# After the arm IK (10).
	process_physics_priority = 11


func _physics_process(_delta: float) -> void:
	if _pivots.is_empty():
		_find_pivots()
	for shoulder: Node3D in _pivots:
		var pivot: Node3D = _pivots[shoulder]
		if is_instance_valid(pivot):
			pivot.basis = _get_turn(shoulder, pivot.get_parent_node_3d())


func _find_pivots() -> void:
	for pair in [[shoulder_left, &"pauldron_l"], [shoulder_right, &"pauldron_r"]]:
		var found := GroupNodes.find(mech, pair[1])
		if pair[0] != null and not found.is_empty():
			_pivots[pair[0]] = found[0]


## Pauldron turn in its parent (torso) space: part of the upper arm turn away from hanging down.
func _get_turn(shoulder: Node3D, torso: Node3D) -> Basis:
	var arm := (torso.global_basis.inverse() * -shoulder.global_basis.y).normalized()
	var angle := Vector3.DOWN.angle_to(arm)
	var turn := minf(maxf(angle - deg_to_rad(start_deg), 0.0) * follow, deg_to_rad(max_deg))
	var axis := Vector3.DOWN.cross(arm)
	if turn <= 0.0 or axis.length_squared() < 0.0001:
		return Basis.IDENTITY
	return Basis(axis.normalized(), turn)
