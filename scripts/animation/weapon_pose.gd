class_name WeaponPose
extends Node
## Moves the weapon between the rest pose (high ready) and the aim pose.
## In the aim pose the weapon is at the shoulder and points at MechAim.aim_point.
## The arms follow the weapon grips with TwoBoneIK.

@export var weapon: Node3D
## Rest pose of the weapon. Same parent as the weapon.
@export var rest_pose: Node3D
## Stock position in the aim pose. Same parent as the weapon.
@export var aim_anchor: Node3D
@export var mech_aim: MechAim
@export var input: MechInput
## How fast the weapon comes up to aim (1 / seconds).
@export var raise_speed: float = 4.0
## How fast the weapon goes down to rest (1 / seconds).
@export var lower_speed: float = 3.0

## 0 = rest pose, 1 = aim pose.
var aim_amount: float = 0.0


func _ready() -> void:
	# After MechAim and before the arm IK.
	process_physics_priority = 5


func _physics_process(delta: float) -> void:
	var speed := raise_speed if input.aim_held else lower_speed
	aim_amount = move_toward(aim_amount, 1.0 if input.aim_held else 0.0, speed * delta)

	var parent := weapon.get_parent_node_3d()
	var origin := aim_anchor.transform.origin
	var target := parent.global_transform.affine_inverse() * mech_aim.aim_point
	var aim_pose := Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)
	weapon.transform = rest_pose.transform.interpolate_with(aim_pose, smoothstep(0.0, 1.0, aim_amount))
