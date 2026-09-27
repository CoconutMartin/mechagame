class_name MechInput
extends Node
## Turns keyboard and mouse into movement intent for a Mech.
## An AI script can replace this node later and fill the same values.

@export var camera_rig: MechCameraRig

## World-space direction the pilot wants to move. Length 0 to 1.
var move_direction: Vector3 = Vector3.ZERO
## World yaw (radians) the mech body should face (camera yaw after the aim spring).
var aim_yaw: float = 0.0
var boost_held: bool = false
## True while the jump key is held. MechJumpCharge uses it to charge the jump jets.
var jump_held: bool = false
## True while the aim key (RMB) is held.
var aim_held: bool = false
## True while the crouch key (Ctrl) is held.
var crouch_held: bool = false


func _ready() -> void:
	# Run before the Mech so it reads this frame's input.
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	aim_yaw = camera_rig.yaw
	move_direction = Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, aim_yaw)
	boost_held = Input.is_action_pressed("boost")
	jump_held = Input.is_action_pressed("jump")
	aim_held = Input.is_action_pressed("aim")
	crouch_held = Input.is_action_pressed("crouch")

