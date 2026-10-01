class_name MechFrame
extends Resource
## Joint layout of a mech: where the frame joints sit, in meters (feet at 0). Part models are made
## for one layout. The legs bring the leg values, the core the torso and shoulder values, each arm
## its arm lengths (PartData.frame). A part with no frame uses these default values (the OG mech).
## MechFrameApplier moves the joints and sets the lengths in the animation nodes.
## The Blender kit (tools/blender/frame_io.py) reads the same file for the socket places.

@export_group("Legs")
## Hip joint height above the ground.
@export var hip_height: float = 5.2
## Hip joint distance from the center line.
@export var hip_width: float = 1.5
## Hip joint to knee joint.
@export var thigh_length: float = 2.6
## Knee joint to ankle joint. The ankle height is what is left: hip height - thigh - shin.
@export var shin_length: float = 2.05

@export_group("Body")
## Waist joint (torso turn) height above the hip joints.
@export var torso_above_hip: float = 0.2
## Shoulder joint distance from the center line.
@export var shoulder_width: float = 2.465
## Shoulder joint height above the waist joint.
@export var shoulder_height: float = 2.465

@export_group("Arms")
## Shoulder joint to elbow joint.
@export var upper_arm_length: float = 2.295
## Elbow joint to the hand center (the grip point).
@export var forearm_length: float = 2.55


## Ankle joint height above the ground (sole to ankle).
func get_ankle_height() -> float:
	return hip_height - thigh_length - shin_length
