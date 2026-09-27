class_name MechInput
extends Node
## Turns keyboard and mouse into movement intent for a Mech (MechWarrior 5: Clans style).
## The mouse aims. The legs turn toward the aim at a steady speed. W / S walk forward and back,
## A / D strafe (the lower legs twist toward the strafe direction).
## An AI script can replace this node later and fill the same values.

@export var camera_rig: MechCameraRig
## The mech.
@export var mech: Node3D

## World-space direction the pilot wants to move, relative to the aim. Length 0 to 1.
var move_direction: Vector3 = Vector3.ZERO
## World yaw (radians) the mech body should face (camera yaw after the aim spring).
var aim_yaw: float = 0.0
var boost_held: bool = false
## True while the jump key is held. MechJumpCharge uses it to charge the jump jets.
var jump_held: bool = false
## True while the aim key (RMB) is held.
var aim_held: bool = false
## True on the frame the crouch key (Ctrl) is pressed. MechKneel toggles on it.
var crouch_pressed: bool = false


func _ready() -> void:
	# Run before the Mech so it reads this frame's input.
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	aim_yaw = camera_rig.yaw
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_direction = Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, aim_yaw)
	boost_held = Input.is_action_pressed("boost")
	jump_held = Input.is_action_pressed("jump")
	aim_held = Input.is_action_pressed("aim")
	crouch_pressed = Input.is_action_just_pressed("crouch")

