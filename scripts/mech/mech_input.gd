class_name MechInput
extends Node
## Turns keyboard and mouse into movement intent for a Mech.
## An AI script can replace this node later and fill the same values.

@export var camera_rig: MechCameraRig
## A jump press is remembered this long (seconds), so a press just before landing still works.
@export var jump_buffer_time: float = 0.15

## World-space direction the pilot wants to move. Length 0 to 1.
var move_direction: Vector3 = Vector3.ZERO
## World yaw (radians) the mech body should face.
var aim_yaw: float = 0.0
var boost_held: bool = false

var _jump_buffer_left: float = 0.0


func _ready() -> void:
	# Run before the Mech so it reads this frame's input.
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	aim_yaw = camera_rig.yaw
	move_direction = Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, aim_yaw)
	boost_held = Input.is_action_pressed("boost")

	_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time


## Returns true once if a jump was pressed recently.
func consume_jump() -> bool:
	if _jump_buffer_left > 0.0:
		_jump_buffer_left = 0.0
		return true
	return false
