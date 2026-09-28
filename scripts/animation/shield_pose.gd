class_name ShieldPose
extends Node
## Moves the left arm with the shield. Follows MechShield.amount: the left hand IK target goes
## between a rest marker (arm at the side) and a raised marker (shield up in front of the chest),
## and the elbow direction blends with it.

@export var shield: MechShield
@export var arm_ik: TwoBoneIK
## The left hand IK target. Same parent as the two markers.
@export var hand_target: Node3D
@export var rest: Node3D
@export var raised: Node3D
## Elbow direction with the arm at the side.
@export var pole_rest: Vector3 = Vector3(-1.0, -0.2, 0.3)
## Elbow direction with the shield up.
@export var pole_raised: Vector3 = Vector3(-0.3, -1.0, -0.2)


func _ready() -> void:
	# Before the arm IK (10).
	process_physics_priority = 5


func _physics_process(_delta: float) -> void:
	var t := smoothstep(0.0, 1.0, shield.amount)
	hand_target.position = rest.position.lerp(raised.position, t)
	arm_ik.pole_direction = pole_rest.lerp(pole_raised, t)
