class_name CrouchPose
extends RefCounted
## A crouch of the rigged mech (bent knees, hips down and back, body leaning forward from the hips and
## the waist) with the feet where they stand. WeaponPickup uses it to reach the ground. The leg solve
## is the one of SkeletalJumpPose's ground pose: the hips go down until the legs have the wanted reach,
## then each leg is a two-bone solve (the ankle on its place, the knee toward the front, the foot flat).
## Call apply() from a skeleton modifier that runs before SkeletalArmRig, so the arms follow the body.
## Skeleton space: +Z is the front, +X is the mech's left, +Y is up.

const PELVIS := &"pelvis"
const TORSO := &"torso"
const LEFT_LEG: Array[StringName] = [&"thigh_L", &"shin_L", &"foot_L"]
const RIGHT_LEG: Array[StringName] = [&"thigh_R", &"shin_R", &"foot_R"]


## amount: 0 = standing, 1 = full crouch. lean_deg: hip bend forward (the whole upper body). torso_lean_deg:
## extra bend forward at the waist. hips_back: hips moved back (m). knee_deg: inner knee angle at full crouch.
## knee_out: the knees point this far to the side (to the front is 1). shift_x: hips moved to the mech's
## left (m, skeleton space +X) at full crouch, toward a weapon that lies to the side.
static func apply(skeleton: Skeleton3D, amount: float, lean_deg: float, torso_lean_deg: float, hips_back: float,
		knee_deg: float, knee_out: float, shift_x: float = 0.0) -> void:
	if amount <= 0.0001:
		return
	var pelvis := skeleton.find_bone(PELVIS)
	var torso := skeleton.find_bone(TORSO)
	if pelvis < 0 or torso < 0:
		return
	var legs := [_leg(skeleton, LEFT_LEG), _leg(skeleton, RIGHT_LEG)]
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var now := skeleton.get_bone_global_pose(pelvis)
	var upper: float = legs[0].upper
	var lower: float = legs[0].lower
	var standing := 0.0
	for leg: Dictionary in legs:
		standing += (leg.ankle as Vector3).distance_to(now * (leg.hip_local as Vector3)) * 0.5
	var reach := lerpf(standing, _reach(upper, lower, knee_deg), amount)
	reach = clampf(reach, 0.6, upper + lower - 0.01)
	var turned := Basis(Vector3.RIGHT, deg_to_rad(lean_deg) * amount) * now.basis
	var shift := Vector3(shift_x * amount, 0.0, -hips_back * amount)
	# The drop of the hips that gives the leg reach (searched).
	var low := -0.5
	var high := 4.0
	for step in 14:
		var mid := (low + high) * 0.5
		var pose := Transform3D(turned, now.origin + shift + Vector3.DOWN * mid)
		var mean := 0.0
		for leg: Dictionary in legs:
			mean += (leg.ankle as Vector3).distance_to(pose * (leg.hip_local as Vector3)) * 0.5
		if mean > reach:
			low = mid
		else:
			high = mid
	var pelvis_pose := Transform3D(turned, now.origin + shift + Vector3.DOWN * (low + high) * 0.5)
	var local := parent.affine_inverse() * pelvis_pose
	skeleton.set_bone_pose_position(pelvis, local.origin)
	skeleton.set_bone_pose_rotation(pelvis, local.basis.get_rotation_quaternion())
	for i in legs.size():
		var side := 1.0 if i == 0 else -1.0
		_solve(skeleton, pelvis_pose, legs[i], legs[i].ankle, legs[i].foot_basis, Vector3(knee_out * side, 0.0, 1.0))
	# The waist bends on top of the hips.
	if torso_lean_deg != 0.0:
		var torso_now := pelvis_pose * skeleton.get_bone_pose(torso)
		var bent := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(torso_lean_deg) * amount) * torso_now.basis, torso_now.origin)
		var torso_local := pelvis_pose.affine_inverse() * bent
		skeleton.set_bone_pose_rotation(torso, torso_local.basis.orthonormalized().get_rotation_quaternion())


## Hip-to-ankle length for an inner knee angle.
static func _reach(upper: float, lower: float, knee_deg: float) -> float:
	return sqrt(upper * upper + lower * lower - 2.0 * upper * lower * cos(deg_to_rad(knee_deg)))


## The leg as it is now: bones, lengths, ankle place, foot turn, hip place in the pelvis.
static func _leg(skeleton: Skeleton3D, names: Array[StringName]) -> Dictionary:
	var thigh := skeleton.find_bone(names[0])
	var shin := skeleton.find_bone(names[1])
	var foot := skeleton.find_bone(names[2])
	var pelvis_pose := skeleton.get_bone_global_pose(skeleton.get_bone_parent(thigh))
	return {
		"thigh": thigh, "shin": shin, "foot": foot,
		"upper": skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(shin).origin),
		"lower": skeleton.get_bone_global_rest(shin).origin.distance_to(skeleton.get_bone_global_rest(foot).origin),
		"ankle": skeleton.get_bone_global_pose(foot).origin,
		"foot_basis": skeleton.get_bone_global_pose(foot).basis,
		"hip_local": pelvis_pose.affine_inverse() * skeleton.get_bone_global_pose(thigh).origin,
	}


## Two-bone leg solve with the pelvis at pelvis_pose: the ankle at ankle, the knee toward pole, the
## foot at foot_basis (skeleton space). Sets the three bone rotations.
static func _solve(skeleton: Skeleton3D, pelvis_pose: Transform3D, leg: Dictionary, ankle: Vector3, foot_basis: Basis,
		pole: Vector3) -> void:
	var thigh: int = leg.thigh
	var shin: int = leg.shin
	var foot: int = leg.foot
	var upper: float = leg.upper
	var lower: float = leg.lower
	var thigh_pose := pelvis_pose * skeleton.get_bone_pose(thigh)
	var shin_pose := thigh_pose * skeleton.get_bone_pose(shin)
	var foot_pose := shin_pose * skeleton.get_bone_pose(foot)
	var hip := thigh_pose.origin
	var reach := ankle - hip
	var distance := clampf(reach.length(), 0.01, upper + lower - 0.001)
	var along := reach.normalized()
	var cos_hip := clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0)
	var side := pole - along * pole.dot(along)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.FORWARD
	var knee := hip + along * upper * cos_hip + side * upper * sqrt(1.0 - cos_hip * cos_hip)
	var end := hip + along * distance
	var thigh_swing := Basis(Quaternion((shin_pose.origin - hip).normalized(), (knee - hip).normalized()))
	var thigh_basis := thigh_swing * thigh_pose.basis
	var shin_basis := thigh_swing * shin_pose.basis
	var shin_dir := (thigh_swing * (foot_pose.origin - shin_pose.origin)).normalized()
	shin_basis = Basis(Quaternion(shin_dir, (end - knee).normalized())) * shin_basis
	skeleton.set_bone_pose_rotation(thigh, (pelvis_pose.basis.orthonormalized().inverse() * thigh_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(shin, (thigh_basis.orthonormalized().inverse() * shin_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(foot, (shin_basis.orthonormalized().inverse() * foot_basis.orthonormalized()).get_rotation_quaternion())
