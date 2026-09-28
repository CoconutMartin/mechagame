class_name MechInput
extends Node
## Turns keyboard and mouse into movement intent for a Mech (MechWarrior style).
## W / S walk forward and back along the legs. A / D turn the legs. The mouse aims the camera and torso.
## An AI script can replace this node later and fill the same values.

@export var camera_rig: MechCameraRig
## The mech.
@export var mech: Node3D

## World-space direction the pilot wants to move (along the legs). Length 0 to 1.
var move_direction: Vector3 = Vector3.ZERO
## Leg turn input: +1 = turn left (A), -1 = turn right (D).
var turn_input: float = 0.0
## World yaw (radians) the mech body should face (camera yaw after the aim spring).
var aim_yaw: float = 0.0
var boost_held: bool = false
## True while the jump key is held. MechJumpCharge uses it to charge the jump jets.
var jump_held: bool = false
## True on the frame the jump key is pressed. MechDodge uses it for the double tap.
var jump_pressed: bool = false
## True while the aim key (RMB) is held.
var aim_held: bool = false
## True while the right arm weapon key (RMB) is held. The right arm weapon fires.
var fire_held: bool = false
## True while the left arm weapon key (LMB) is held. A shield on the left arm lifts.
var shield_held: bool = false
## True while the walk forward key (W) is held. MechKneel stands up on it.
var forward_held: bool = false
## True on the frame the crouch key (Ctrl) is pressed. MechKneel toggles on it.
var crouch_pressed: bool = false


func _ready() -> void:
	# Run before the Mech so it reads this frame's input.
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	aim_yaw = camera_rig.yaw
	var throttle := Input.get_axis("move_back", "move_forward")
	move_direction = Vector3(0.0, 0.0, -throttle).rotated(Vector3.UP, mech.rotation.y)
	turn_input = Input.get_axis("move_right", "move_left")
	boost_held = Input.is_action_pressed("boost")
	# Pressed = held now but not in the last frame, so the two values always agree.
	var was_held := jump_held
	jump_held = Input.is_action_pressed("jump")
	jump_pressed = jump_held and not was_held
	aim_held = Input.is_action_pressed("aim")
	fire_held = Input.is_action_pressed("use_right_arm")
	shield_held = Input.is_action_pressed("use_left_arm")
	crouch_pressed = Input.is_action_just_pressed("crouch")
	forward_held = Input.is_action_pressed("move_forward")

