extends RefCounted
## The rest pose of Haliya HLY-101 with only its legs aligned to SGG-101 (user choice 2026-11-08, "Legs only"): the leg chain takes
## the SGG offsets (pelvis height, thigh and shin lengths, ankle height, the foot control and knee pole bones), so the shared clips
## land the feet as on SGG; everything else keeps Haliya's own offsets from its light-rig export (hip width, waist, neck, shoulders,
## arm lengths, hands, the skirt and pauldron bones). Bone names, parents and rest rotations are SGG's (the same on both rigs).
## Used by tools/godot/refit_haliya_parts.gd (part files) and tools/godot/make_haliya_rig.gd (rig file) through preload.

## Bones with the SGG offset: pelvis height, thigh length (the shin's offset), shin length (the foot's offset).
const SGG_BONES: Array[String] = ["pelvis", "shin_L", "shin_R", "foot_L", "foot_R"]
## Hip joints: the SGG offset from the pelvis, but Haliya's own side offset (x, the hip width).
const HIP_BONES: Array[String] = ["thigh_L", "thigh_R"]
## Leg IK helper bones (children of the root): the SGG offset, moved with the joint they stand for (the narrower hips move them in).
const LEG_HELPERS: Dictionary = {"foot_ctrl_L": "foot_L", "foot_ctrl_R": "foot_R", "knee_pole_L": "shin_L", "knee_pole_R": "shin_R"}
## Arm IK helper bones (children of the root): Haliya's offset, moved with the joint they stand for (the pelvis height moves them).
const ARM_HELPERS: Dictionary = {"elbow_pole_L": "forearm_L", "elbow_pole_R": "forearm_R", "hand_ik_L": "hand_L", "hand_ik_R": "hand_R"}


## Sets the rest of skeleton (a copy of the SGG skeleton) to the legs-aligned Haliya rest. haliya is the skeleton of the light-rig
## export. Returns bone name -> the change of its local rest offset (new minus SGG), for the clips' position tracks.
static func apply(skeleton: Skeleton3D, haliya: Skeleton3D) -> Dictionary:
	var sgg_global := {}
	var sgg_local := {}
	for i in skeleton.get_bone_count():
		sgg_global[skeleton.get_bone_name(i)] = skeleton.get_bone_global_rest(i)
		sgg_local[skeleton.get_bone_name(i)] = skeleton.get_bone_rest(i)
	var hly_global := {}
	for i in haliya.get_bone_count():
		hly_global[haliya.get_bone_name(i)] = haliya.get_bone_global_rest(i)
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		if name in SGG_BONES or LEG_HELPERS.has(name):
			continue
		var from := haliya.find_bone(name)
		if from < 0:
			push_error("haliya_legs_aligned_rest: no bone %s in the Haliya rig" % name)
			continue
		var rest := skeleton.get_bone_rest(i)
		var own := haliya.get_bone_rest(from).origin
		rest.origin = Vector3(own.x, rest.origin.y, rest.origin.z) if name in HIP_BONES else own
		skeleton.set_bone_rest(i, rest)
	# The helpers last: they follow their joints, whose global rest is now known.
	for name: String in LEG_HELPERS:
		_follow(skeleton, name, LEG_HELPERS[name], (sgg_local[name] as Transform3D).origin, (sgg_global[LEG_HELPERS[name]] as Transform3D).origin)
	for name: String in ARM_HELPERS:
		var joint: String = ARM_HELPERS[name]
		_follow(skeleton, name, joint, haliya.get_bone_rest(haliya.find_bone(name)).origin, (hly_global[joint] as Transform3D).origin)
	var changes := {}
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		changes[name] = skeleton.get_bone_rest(i).origin - (sgg_local[name] as Transform3D).origin
		skeleton.set_bone_pose(i, skeleton.get_bone_rest(i))
	return changes


## A helper bone at offset (in its parent's frame) from a skeleton where its joint was at joint_was (skeleton space): it moves with
## the joint to the joint's place in this skeleton.
static func _follow(skeleton: Skeleton3D, name: String, joint: String, offset: Vector3, joint_was: Vector3) -> void:
	var bone := skeleton.find_bone(name)
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	var move := skeleton.get_bone_global_rest(skeleton.find_bone(joint)).origin - joint_was
	var rest := skeleton.get_bone_rest(bone)
	rest.origin = offset + parent_basis.inverse() * move
	skeleton.set_bone_rest(bone, rest)


## The Skeleton3D of a loaded rig or part scene (the last one found, as in the export files).
static func skeleton_of(scene: Node) -> Skeleton3D:
	var found: Skeleton3D
	for node in scene.find_children("*", "Skeleton3D", true, false):
		found = node
	return found
