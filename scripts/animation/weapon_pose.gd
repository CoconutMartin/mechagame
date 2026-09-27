class_name WeaponPose
extends Node
## Moves the weapon between the rest pose and the aim pose.
## Rest pose: held across the chest, muzzle up, left hand high near the muzzle, right hand low on the grip.
## Aim pose: stock at the shoulder, weapon points at MechAim.aim_point, left hand moves back on the handguard.
## The arms follow the weapon grips with TwoBoneIK. This script also moves the left grip and the elbow directions.

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

@export_group("Hands")
## The left hand IK target. This script moves it between the two grip markers.
@export var left_grip_target: Node3D
## Left hand place in the rest pose (on the weapon).
@export var left_grip_rest: Node3D
## Left hand place in the aim pose (on the weapon).
@export var left_grip_aim: Node3D
@export var arm_ik_left: TwoBoneIK
@export var arm_ik_right: TwoBoneIK
## Elbow directions in the rest pose: left elbow out and high, right elbow down.
@export var left_pole_rest: Vector3 = Vector3(-1.0, 0.3, 0.4)
@export var right_pole_rest: Vector3 = Vector3(1.0, -1.0, 0.3)
## Elbow directions in the aim pose: both elbows down and out.
@export var left_pole_aim: Vector3 = Vector3(-0.6, -1.0, 0.2)
@export var right_pole_aim: Vector3 = Vector3(1.0, -0.8, 0.3)

## 0 = rest pose, 1 = aim pose.
var aim_amount: float = 0.0


func _ready() -> void:
	# After MechAim and before the arm IK.
	process_physics_priority = 5


func _physics_process(delta: float) -> void:
	var speed := raise_speed if input.aim_held else lower_speed
	aim_amount = move_toward(aim_amount, 1.0 if input.aim_held else 0.0, speed * delta)
	var t := smoothstep(0.0, 1.0, aim_amount)

	var parent := weapon.get_parent_node_3d()
	var origin := aim_anchor.transform.origin
	var target := parent.global_transform.affine_inverse() * mech_aim.aim_point
	var aim_pose := Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)
	weapon.transform = rest_pose.transform.interpolate_with(aim_pose, t)

	left_grip_target.position = left_grip_rest.position.lerp(left_grip_aim.position, t)
	arm_ik_left.pole_direction = left_pole_rest.lerp(left_pole_aim, t)
	arm_ik_right.pole_direction = right_pole_rest.lerp(right_pole_aim, t)
