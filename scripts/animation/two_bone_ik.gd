class_name TwoBoneIK
extends Node
## Bends a two-part limb (for example shoulder > elbow > hand) so the hand reaches a target.
## Each bone must point down its own -Y axis, with the child joint at (0, -length, 0).

## First joint (shoulder). Stays in place and rotates.
@export var root_joint: Node3D
## Second joint (elbow). Must be a child of root_joint.
@export var mid_joint: Node3D
## The hand goes to this node (for example a grip marker on a weapon).
@export var target: Node3D
## Length from root joint to mid joint, in meters.
@export var upper_length: float = 2.6
## Length from mid joint to the hand center, in meters.
@export var lower_length: float = 2.9
## Direction the elbow points to, in the space of root_joint's parent.
@export var pole_direction: Vector3 = Vector3(1.0, -1.0, 0.5)


func _ready() -> void:
	# Run after movement and walk animation, so the hand stays on the target.
	process_physics_priority = 10


func _physics_process(_delta: float) -> void:
	solve()


func solve() -> void:
	var parent_basis := root_joint.get_parent_node_3d().global_basis
	var shoulder := root_joint.global_position
	var to_target := target.global_position - shoulder
	var reach := upper_length + lower_length
	var distance := clampf(to_target.length(), 0.01, reach - 0.001)
	var direction := to_target.normalized()

	# Law of cosines: angle at the shoulder between the target line and the upper bone.
	var cos_angle := (upper_length * upper_length + distance * distance - lower_length * lower_length) / (2.0 * upper_length * distance)
	var angle := acos(clampf(cos_angle, -1.0, 1.0))

	var pole := (parent_basis * pole_direction).normalized()
	var bend := (pole - direction * pole.dot(direction)).normalized()
	if bend.is_zero_approx():
		bend = parent_basis.x
	var elbow := shoulder + (direction * cos(angle) + bend * sin(angle)) * upper_length
	var hand := shoulder + direction * distance
	var side := direction.cross(bend).normalized()

	root_joint.global_basis = _bone_basis(shoulder, elbow, side)
	mid_joint.global_basis = _bone_basis(elbow, hand, side)


## Basis whose -Y points from start to end.
func _bone_basis(start: Vector3, end: Vector3, side: Vector3) -> Basis:
	var y := (start - end).normalized()
	var x := (side - y * side.dot(y)).normalized()
	return Basis(x, y, x.cross(y))
