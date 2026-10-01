class_name FrameMeasure
extends RefCounted
## Bone lengths of the mech frame, measured when the animation scripts start (after MechAssembler
## moved the sockets with FrameLayout). With the mech scene's own places, every value is the same
## as before custom skeletons. Each function returns the fallback when its node is missing.

## Meta on a joint socket: its distance from its parent socket in the mech scene (before FrameLayout).
const SCENE_LENGTH := &"scene_length"


## Stores the scene length of a joint socket (FrameLayout calls this before it moves the socket).
static func remember(joint: Node3D) -> void:
	if not joint.has_meta(SCENE_LENGTH):
		joint.set_meta(SCENE_LENGTH, joint.position.length())


## Hip to knee (the knee socket's distance from the hip).
static func thigh(knee: Node3D, fallback: float) -> float:
	return knee.position.length() if knee != null else fallback


## Shoulder to elbow (the elbow socket's distance from the shoulder).
static func upper_arm(elbow: Node3D, fallback: float) -> float:
	return elbow.position.length() if elbow != null else fallback


## Knee to ankle: the distance of the foot pivot (group foot_pivot_l or foot_pivot_r) from the knee.
static func shin(knee: Node3D, fallback: float) -> float:
	if knee == null:
		return fallback
	for child in knee.get_children():
		if child is Node3D and (child.is_in_group(&"foot_pivot_l") or child.is_in_group(&"foot_pivot_r")):
			return (child as Node3D).position.length()
	return fallback


## Height of a frame node above the mech origin (the feet), in the rest pose.
static func height(node: Node3D, mech: Node3D, fallback: float) -> float:
	if node == null or mech == null:
		return fallback
	return (mech.global_transform.affine_inverse() * node.global_position).y


## New length / scene length of a joint socket (1.0 with the mech scene's places). Scripts scale
## their tuned reach values with it.
static func scale(joint: Node3D) -> float:
	if joint == null:
		return 1.0
	var scene_length: float = joint.get_meta(SCENE_LENGTH, joint.position.length())
	return joint.position.length() / scene_length if scene_length > 0.001 else 1.0
