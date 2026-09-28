class_name ShieldPose
extends Node
## Lifts the shield on the left arm while the left arm key (LMB) is held.
## Moves the left hand IK target between a rest marker (arm at the side) and a raised marker
## (shield up in front of the chest), and blends the elbow direction.

@export var input: MechInput
@export var arm_ik: TwoBoneIK
## The left hand IK target. Same parent as the two markers.
@export var hand_target: Node3D
@export var rest: Node3D
@export var raised: Node3D
## Elbow direction with the arm at the side.
@export var pole_rest: Vector3 = Vector3(-1.0, -0.2, 0.3)
## Elbow direction with the shield up.
@export var pole_raised: Vector3 = Vector3(-0.3, -1.0, -0.2)
## How fast the shield comes up (1 / seconds).
@export var raise_speed: float = 5.0
## How fast the shield goes down (1 / seconds).
@export var lower_speed: float = 3.0

## 0 = shield down, 1 = shield up.
var amount: float = 0.0


func _ready() -> void:
	# Before the arm IK (10).
	process_physics_priority = 5


func _physics_process(delta: float) -> void:
	var speed := raise_speed if input.shield_held else lower_speed
	amount = move_toward(amount, 1.0 if input.shield_held else 0.0, speed * delta)
	var t := smoothstep(0.0, 1.0, amount)
	hand_target.position = rest.position.lerp(raised.position, t)
	arm_ik.pole_direction = pole_rest.lerp(pole_raised, t)
