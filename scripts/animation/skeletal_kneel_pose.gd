class_name SkeletalKneelPose
extends SkeletonModifier3D
## Ctrl kneel of the rigged mech (user report 2026-11-02: "only the camera lowers"). The kneel was written for the
## part-built mech (MechLegSwing) and never ported to the skeleton. MechKneel.amount (0 = standing, 1 = down, 1.25 s
## each way) drives this pose: the hips go down and back, the right knee is on the ground with the shin lying back
## and the toes tucked (the toes touch the ground), the left foot steps forward and stands flat with the knee bent,
## and the waist leans a little forward. The legs use the two-bone solve of CrouchPose (the ankle on its place,
## the knee toward its pole). The pose blends from whatever pose is under it (idle, stance), so the transition
## starts where the body is. The arms keep their weapon holds (SkeletalArmRig runs after this node and follows the
## torso). ShoulderBrace does not brace while kneeling (it is set at once), so BracePose adds nothing on top.
## Skeleton space: +Z is the front, +X is the mech's left, +Y is up, y = 0 is the ground.
## A skeleton modifier must be a child of the Skeleton3D; this node moves itself there at start.
## Keep it after SkeletalJumpPose and before SkeletalArmRig.

@export var model: Node3D
@export var mech: Mech
## True for the second node, after the hit reaction clip: a flinch clip has the whole body (standing legs), so while it
## plays this node puts the hips and legs of the kneel back on (the clip keeps the upper body).
@export var after_hit_clip: bool = false

@export_group("Hips")
## The hips go back this far (m) at full kneel, from their standing place.
@export var hips_back: float = 1.2
## Forward lean of the waist at full kneel (degrees; the chest stays up).
@export var torso_lean_deg: float = 6.0

@export_group("Front leg (left)")
## The left foot steps forward this far (m) from its standing place and stands flat.
@export var front_step: float = 1.2
## The left foot lifts this high (m) on the way.
@export var front_lift: float = 0.5

@export_group("Back leg (right)")
## The right knee centre (the shin bone) is this high above the ground (m). The shin armor reaches
## about 0.6 m in front of its bone, so 0.65 puts the armor on the ground.
@export var knee_height: float = 0.65
## The right thigh leans forward from vertical by this much (degrees), and the knee points this much
## to the side (degrees).
@export var back_thigh_deg: float = 10.0
@export var back_knee_out_deg: float = 4.0
## The foot box under the right ankle (m, along the foot): sole, top, toes, heel. The shin is tilted
## up from the knee until the toes touch the ground.
@export var foot_sole_depth: float = 1.05
@export var foot_top_depth: float = 0.13
@export var foot_toe_length: float = 1.81
@export var foot_heel_length: float = 0.84
## The toes stop this far above the ground (m).
@export var toe_clearance: float = 0.03
## The right foot lifts this high (m) on the way.
@export var back_lift: float = 0.7

@export_group("Timing")
## Parts of the kneel (0 to 1 of MechKneel.amount) over which the left foot steps and the right foot swings
## back. The hips use the whole kneel.
@export var front_foot_span: Vector2 = Vector2(0.0, 0.6)
@export var back_foot_span: Vector2 = Vector2(0.15, 0.85)

@export_group("Bones")
@export var pelvis_bone: StringName = &"pelvis"
@export var torso_bone: StringName = &"torso"
@export var leg_bones_left: PackedStringArray = ["thigh_L", "shin_L", "foot_L"]
@export var leg_bones_right: PackedStringArray = ["thigh_R", "shin_R", "foot_R"]

## Pelvis drop from its standing height now (m, for tests and the camera).
var drop_now: float = 0.0
## The kneel blend applied now (0 to 1).
var applied: float = 0.0

var _toe_angle: float = -1.0
var _hit: Node


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


func _process_modification_with_delta(_delta: float) -> void:
	applied = 0.0
	drop_now = 0.0
	if mech == null or mech.kneel == null:
		return
	var amount := clampf(mech.kneel.amount, 0.0, 1.0)
	if amount <= 0.0001:
		return
	if after_hit_clip:
		if _hit == null or not is_instance_valid(_hit):
			_hit = mech.find_child("HitAnimation", true, false)
		if _hit == null or _hit.get("is_playing") != true:
			return
	var skeleton := get_skeleton()
	var pelvis := skeleton.find_bone(pelvis_bone)
	var torso := skeleton.find_bone(torso_bone)
	if pelvis < 0 or torso < 0:
		return
	var hips := smoothstep(0.0, 1.0, amount)
	var front := smoothstep(front_foot_span.x, front_foot_span.y, amount)
	var back := smoothstep(back_foot_span.x, back_foot_span.y, amount)
	applied = hips
	var legs := [CrouchPose.read_leg(skeleton, leg_bones_left), CrouchPose.read_leg(skeleton, leg_bones_right)]
	var left: Dictionary = legs[0]
	var right: Dictionary = legs[1]
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(pelvis))
	var now := skeleton.get_bone_global_pose(pelvis)
	# The pelvis keeps its turn (the aim stance turns the hips); forward is the turned front, level.
	var forward := now.basis * Vector3.BACK
	forward = Vector3(forward.x, 0.0, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else Vector3.BACK
	var yaw := atan2(forward.x, forward.z)
	var turn := Basis(Vector3.UP, yaw)
	var upper: float = right.upper
	var lower: float = right.lower
	# The pelvis height that puts the right knee on the ground with the thigh leaning back_thigh_deg.
	var lean := deg_to_rad(back_thigh_deg)
	var out := deg_to_rad(back_knee_out_deg)
	var thigh_dir := turn * Vector3(-sin(out), -cos(lean) * cos(out), sin(lean) * cos(out)).normalized()
	var hip_local: Vector3 = right.hip_local
	var hip_offset := now.basis * hip_local
	var hip_y := knee_height - thigh_dir.y * upper
	var rest_pelvis := skeleton.get_bone_global_rest(pelvis).origin
	var full_origin := Vector3(now.origin.x, hip_y - hip_offset.y, rest_pelvis.z - hips_back)
	var pelvis_origin := now.origin.lerp(full_origin, hips)
	drop_now = now.origin.y - pelvis_origin.y
	var pelvis_pose := Transform3D(now.basis, pelvis_origin)
	var full_pose := Transform3D(now.basis, full_origin)
	var local := parent.affine_inverse() * pelvis_pose
	skeleton.set_bone_pose_position(pelvis, local.origin)
	skeleton.set_bone_pose_rotation(pelvis, local.basis.get_rotation_quaternion())

	# Back leg: the full kneel (knee on the ground, shin lying back and up, toes on the ground).
	var hip_full := full_pose * hip_local
	var knee_full := hip_full + thigh_dir * upper
	var tilt := _toe_down_angle(lower)
	var shin_dir := turn * Vector3(0.0, sin(tilt), -cos(tilt))
	var ankle_full := knee_full + shin_dir * lower
	var rest_foot_basis := skeleton.get_bone_global_rest(right.foot as int).basis.orthonormalized()
	var foot_full := turn * Basis(Vector3.RIGHT, PI * 0.5 + tilt) * rest_foot_basis
	var hip_now := pelvis_pose * hip_local
	# The knee hangs from the moved hips (its leg bones still have the earlier pose).
	var knee_now := (pelvis_pose * skeleton.get_bone_pose(right.thigh as int) * skeleton.get_bone_pose(right.shin as int)).origin
	var knee_back := knee_now.lerp(knee_full, back)
	var ankle_back := (right.ankle as Vector3).lerp(ankle_full, back) + Vector3.UP * back_lift * 4.0 * back * (1.0 - back)
	var foot_back := (right.foot_basis as Basis).orthonormalized().get_rotation_quaternion().slerp(
			foot_full.orthonormalized().get_rotation_quaternion(), back)
	CrouchPose.solve_leg(skeleton, pelvis_pose, right, ankle_back, Basis(foot_back), knee_back - hip_now)

	# Front leg: the foot steps forward and stands flat, the knee points forward.
	var rest_ankle := skeleton.get_bone_global_rest(left.foot as int).origin
	var ankle_front_full := Vector3(rest_ankle.x, rest_ankle.y, rest_ankle.z + front_step)
	var ankle_front := (left.ankle as Vector3).lerp(ankle_front_full, front) + Vector3.UP * front_lift * 4.0 * front * (1.0 - front)
	var rest_foot := skeleton.get_bone_global_rest(left.foot as int).basis.orthonormalized().get_rotation_quaternion()
	var foot_front := (left.foot_basis as Basis).orthonormalized().get_rotation_quaternion().slerp(rest_foot, front)
	CrouchPose.solve_leg(skeleton, pelvis_pose, left, ankle_front, Basis(foot_front), turn * Vector3(0.0, 0.0, 1.0))

	# The waist leans forward on top of the hips.
	if torso_lean_deg != 0.0 and not after_hit_clip:
		var torso_now := pelvis_pose * skeleton.get_bone_pose(torso)
		var bent := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(torso_lean_deg) * hips) * torso_now.basis, torso_now.origin)
		var torso_local := pelvis_pose.affine_inverse() * bent
		skeleton.set_bone_pose_rotation(torso, torso_local.basis.orthonormalized().get_rotation_quaternion())


## Angle (radians) the shin lies above level, behind the knee: the toes of the foot box just touch the ground.
## The foot turns with the shin (foot at a right angle to it), so the toes point down and back.
func _toe_down_angle(shin_length: float) -> float:
	if _toe_angle >= 0.0:
		return _toe_angle
	var low := 0.0
	var high := deg_to_rad(70.0)
	for step in 24:
		var mid := (low + high) * 0.5
		if _lowest_foot_point(mid, shin_length) < toe_clearance:
			low = mid
		else:
			high = mid
	_toe_angle = (low + high) * 0.5
	return _toe_angle


## Height of the lowest foot-box corner (m) with the shin lying tilt radians above level behind the knee.
func _lowest_foot_point(tilt: float, shin_length: float) -> float:
	var ankle := knee_height + shin_length * sin(tilt)
	# The foot turns with the shin about the side axis: 90 degrees (down to back) plus the tilt.
	var turned := PI * 0.5 + tilt
	var lowest := INF
	for y: float in [-foot_sole_depth, -foot_top_depth]:
		for z: float in [foot_toe_length, -foot_heel_length]:
			lowest = minf(lowest, ankle + y * cos(turned) - z * sin(turned))
	return lowest
