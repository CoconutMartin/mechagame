class_name MechFrameApplier
extends RefCounted
## Gives a mech the joint layout of its parts (MechFrame, see PartData.frame), before the parts are
## added and before the animation nodes start (MechAssembler calls it first):
##   Frame joints: Lower (hips) and Torso height, hip width, knee drop, shoulder places, elbow drop.
##   Hand markers (AimAnchor, LeftHand...): keep their offset from their shoulder.
##   Animation nodes: leg and arm lengths (FootPlanter, FootLeveler, MechLegSwing, FallPose,
##   PowerDownPose, the arm TwoBoneIK nodes).
## The OG layout (MechFrame defaults) changes nothing.

## Hand markers under Torso, and the shoulder they follow.
const MARKERS := {"AimAnchor": "R", "LeftHand": "L", "LeftHandRest": "L", "LeftHandRaised": "L"}


static func apply(mech: Node, frame_root: Node3D, loadout: Loadout) -> void:
	var og := MechFrame.new()
	var legs := _frame_of(loadout.legs)
	var core := _frame_of(loadout.core)
	var arms := {"L": _frame_of(loadout.arm_left), "R": _frame_of(loadout.arm_right)}
	var upper := frame_root.get_node_or_null(^"Roll/Upper") as Node3D
	if upper == null:
		return
	var torso := upper.get_node(^"Torso") as Node3D
	var lower := upper.get_node(^"Lower") as Node3D
	lower.position.y = legs.hip_height
	torso.position.y = legs.hip_height + core.torso_above_hip
	var shoulder_move := Vector2(core.shoulder_width - og.shoulder_width, core.shoulder_height - og.shoulder_height)
	for side: String in ["L", "R"]:
		var k := -1.0 if side == "L" else 1.0
		var arm: MechFrame = arms[side]
		(lower.get_node("Hip" + side) as Node3D).position.x = k * legs.hip_width
		(lower.get_node("Hip%s/Knee%s" % [side, side]) as Node3D).position.y = -legs.thigh_length
		(torso.get_node("Shoulder" + side) as Node3D).position = Vector3(k * core.shoulder_width, core.shoulder_height, 0.0)
		(torso.get_node("Shoulder%s/Elbow%s" % [side, side]) as Node3D).position.y = -arm.upper_arm_length
	for marker_name: String in MARKERS:
		var marker := torso.get_node_or_null(marker_name) as Node3D
		if marker != null:
			var k := -1.0 if MARKERS[marker_name] == "L" else 1.0
			marker.position += Vector3(k * shoulder_move.x, shoulder_move.y, 0.0)
	_set_lengths(mech, legs, arms)


static func _frame_of(part: PartData) -> MechFrame:
	return part.frame if part != null and part.frame != null else MechFrame.new()


static func _set_lengths(node: Node, legs: MechFrame, arms: Dictionary) -> void:
	var ankle := legs.get_ankle_height()
	if node is FootPlanter:
		node.thigh_length = legs.thigh_length
		node.shin_length = legs.shin_length
		node.ankle_height = ankle
	elif node is FootLeveler:
		node.sole_depth = ankle
	elif node is MechLegSwing:
		node.leg_length = legs.hip_height
	elif node is FallPose or node is PowerDownPose:
		# These count the leg to the sole: the shin part includes the ankle height.
		node.thigh_length = legs.thigh_length
		node.shin_length = legs.shin_length + ankle
	elif node is TwoBoneIK and node.root_joint != null:
		var side := String(node.root_joint.name).right(1)
		if arms.has(side):
			node.upper_length = (arms[side] as MechFrame).upper_arm_length
			node.lower_length = (arms[side] as MechFrame).forearm_length
	for child in node.get_children():
		_set_lengths(child, legs, arms)
