class_name SkeletalAimStance
extends SkeletonModifier3D
## Sniping stance of the rigged mech (user reference "sniper rifle standing in shooting position",
## 2026-10-12): while a two-hand rifle is aimed, the hips turn right and drop a little, the left leg
## steps forward with a bent knee, the right leg steps back almost straight, braced, and both feet stay
## flat (the right foot turned out). The torso turns further with the weapon's aim twist (SkeletalArmRig),
## so the chest turns about 70 degrees in all; the head turns back to the aim (SkeletalArmRig). It blends
## in with the weapon raise (WeaponPose.aim_amount). The mech does not walk while aiming (MechInput).
## A skeleton modifier must be a child of the Skeleton3D; this node moves itself there at start. Keep
## it after SkeletalHipTurn and before SkeletalArmRig.

@export var model: Node3D
@export var mech: Mech
@export var weapon_pose: WeaponPose
@export var weapons: WeaponController
## Hip turn to the right (degrees) and drop (m) at full stance.
@export var hip_turn_deg: float = 45.0
@export var pelvis_drop: float = 0.6
## Ankle places from their rest places (model space: +Z forward, +X the mech's left), at full stance.
@export var left_foot_offset: Vector3 = Vector3(-0.25, 0.0, 1.9)
@export var right_foot_offset: Vector3 = Vector3(0.0, 0.0, -1.9)
## Foot turn about the up axis (degrees, + = toward the mech's left).
@export var left_foot_yaw_deg: float = -10.0
@export var right_foot_yaw_deg: float = -60.0
## Knee directions (model space).
@export var left_knee_pole: Vector3 = Vector3(0.3, 0.0, 1.0)
@export var right_knee_pole: Vector3 = Vector3(-0.5, 0.0, 1.0)
@export var pelvis_bone: StringName = &"pelvis"
@export var leg_bones_left: PackedStringArray = ["thigh_L", "shin_L", "foot_L"]
@export var leg_bones_right: PackedStringArray = ["thigh_R", "shin_R", "foot_R"]

## The hip turn applied now (radians, negative = right); SkeletalArmRig turns the head back by it.
var applied_turn: float = 0.0
## 0 = normal, 1 = full stance.
var amount: float = 0.0


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


## True while the weapon in the hands is a two-hand rifle.
func is_two_hand() -> bool:
	return weapons != null and weapons.right_data != null and weapons.right_data.two_handed \
			and weapons.right_weapon != null and is_instance_valid(weapons.right_weapon)


func _process_modification_with_delta(_delta: float) -> void:
	amount = 0.0
	applied_turn = 0.0
	if not is_two_hand() or weapon_pose == null or mech == null or not mech.is_on_floor():
		return
	amount = smoothstep(0.0, 1.0, weapon_pose.aim_amount)
	if amount <= 0.0:
		return
	var skeleton := get_skeleton()
	var pelvis := skeleton.find_bone(pelvis_bone)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var now := skeleton.get_bone_global_pose(pelvis)
	var turn := -deg_to_rad(hip_turn_deg)
	var full := Transform3D(Basis(Vector3.UP, turn) * now.basis, now.origin + Vector3.DOWN * pelvis_drop)
	var legs := [
		_solve_leg(skeleton, full, leg_bones_left, left_foot_offset, left_foot_yaw_deg, left_knee_pole),
		_solve_leg(skeleton, full, leg_bones_right, right_foot_offset, right_foot_yaw_deg, right_knee_pole)]
	# Blend: the pelvis turn and drop by amount, the leg bones toward their solved turns.
	applied_turn = turn * amount
	var blended := Transform3D(Basis(Vector3.UP, applied_turn) * now.basis,
			now.origin + Vector3.DOWN * pelvis_drop * amount)
	var local := parent.affine_inverse() * blended
	skeleton.set_bone_pose_position(pelvis, local.origin)
	skeleton.set_bone_pose_rotation(pelvis, local.basis.get_rotation_quaternion())
	for leg: Dictionary in legs:
		for bone: int in leg:
			var from := skeleton.get_bone_pose_rotation(bone)
			skeleton.set_bone_pose_rotation(bone, from.slerp(leg[bone], amount))


## Two-bone leg solve with the pelvis at pelvis_pose: the ankle on its stance place, the knee toward the
## pole, the foot flat (its rest turn plus yaw). Returns {bone: local rotation}.
func _solve_leg(skeleton: Skeleton3D, pelvis_pose: Transform3D, names: PackedStringArray, offset: Vector3,
		yaw_deg: float, pole: Vector3) -> Dictionary:
	var thigh := skeleton.find_bone(names[0])
	var shin := skeleton.find_bone(names[1])
	var foot := skeleton.find_bone(names[2])
	var thigh_pose := pelvis_pose * skeleton.get_bone_pose(thigh)
	var shin_pose := thigh_pose * skeleton.get_bone_pose(shin)
	var foot_pose := shin_pose * skeleton.get_bone_pose(foot)
	var upper := skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(shin).origin)
	var lower := skeleton.get_bone_global_rest(shin).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)
	var hip := thigh_pose.origin
	var ankle := skeleton.get_bone_global_rest(foot).origin + offset
	var reach := ankle - hip
	var distance := clampf(reach.length(), 0.01, upper + lower - 0.001)
	var along := reach.normalized()
	var cos_hip := clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0)
	var side := pole - along * pole.dot(along)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.FORWARD
	var knee := hip + along * upper * cos_hip + side * upper * sqrt(1.0 - cos_hip * cos_hip)
	ankle = hip + along * distance
	# Thigh: swing from its knee direction now to the new one; the shin turns with it, then swings.
	var thigh_swing := Basis(Quaternion((shin_pose.origin - hip).normalized(), (knee - hip).normalized()))
	var thigh_basis := thigh_swing * thigh_pose.basis
	var shin_basis := thigh_swing * shin_pose.basis
	var shin_dir := (thigh_swing * (foot_pose.origin - shin_pose.origin)).normalized()
	shin_basis = Basis(Quaternion(shin_dir, (ankle - knee).normalized())) * shin_basis
	var foot_basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * skeleton.get_bone_global_rest(foot).basis
	return {
		thigh: (pelvis_pose.basis.orthonormalized().inverse() * thigh_basis).get_rotation_quaternion(),
		shin: (thigh_basis.orthonormalized().inverse() * shin_basis).get_rotation_quaternion(),
		foot: (shin_basis.orthonormalized().inverse() * foot_basis).get_rotation_quaternion(),
	}
