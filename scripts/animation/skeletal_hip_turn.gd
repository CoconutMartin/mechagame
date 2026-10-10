class_name SkeletalHipTurn
extends SkeletonModifier3D
## Turns a rigged mech's hips (the whole model) to the way it moves, so strafing steps that way, then
## twists the waist bone back to the aim. Moving backward the hips face the other way (forward) and
## the mech steps backward (SkeletalLocomotion plays the cycle in reverse). Past the twist limit the upper body
## turns with the hips. A skeleton modifier must be a child of the Skeleton3D (it then runs after the
## animation); the skeleton is inside the imported model, so this node moves itself there at start.

@export var mech: Mech
## The node the hips turn (the model root).
@export var model: Node3D
## Model yaw when the hips face the mech front (the glTF model faces +Z: PI).
@export var model_base_yaw: float = PI
## Bone that twists back to the aim (the bone above the hips).
@export var waist_bone: StringName = &"torso"
## How fast the hips turn to the move direction (degrees per second).
@export var turn_speed_deg: float = 270.0
## Below this ground speed (m/s) the hips turn back to the mech front.
@export var min_speed: float = 1.0
## Largest waist twist from the hips (degrees).
@export var max_twist_deg: float = 90.0
## Moving more than this far from the front (degrees) the mech steps backward; it steps forward again
## below 180 minus this. The gap keeps a pure strafe from flipping between the two.
@export var back_step_angle_deg: float = 100.0

## True while the mech steps backward.
var is_backward: bool = false

## Hip turn from the mech front now (radians, positive = left).
var hip_yaw: float = 0.0
## True: the hips keep their turn (SkeletalMoves sets it while a stop animation plays).
var hold: bool = false


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


func _process_modification_with_delta(delta: float) -> void:
	var target := 0.0
	var move := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	if hold:
		target = hip_yaw
	elif move.length() > min_speed:
		var local := mech.global_basis.inverse() * move
		target = atan2(-local.x, -local.z)
		var angle := absf(rad_to_deg(target))
		if angle > back_step_angle_deg:
			is_backward = true
		elif angle < 180.0 - back_step_angle_deg:
			is_backward = false
		if is_backward:
			target = wrapf(target + PI, -PI, PI)
	else:
		is_backward = false
	hip_yaw = wrapf(rotate_toward(hip_yaw, target, deg_to_rad(turn_speed_deg) * delta), -PI, PI)
	model.rotation.y = model_base_yaw + hip_yaw
	var limit := deg_to_rad(max_twist_deg)
	var twist := clampf(wrapf(mech.get_torso_twist() - hip_yaw, -PI, PI), -limit, limit)
	var skeleton := get_skeleton()
	var bone := skeleton.find_bone(waist_bone)
	if bone < 0:
		return
	# The skeleton is upright (Y up), so a turn about its Y axis is a turn about the world up axis.
	var pose := skeleton.get_bone_global_pose(bone)
	var turned := Transform3D(Basis(Vector3.UP, twist) * pose.basis, pose.origin)
	var parent := skeleton.get_bone_parent(bone)
	var local_pose := turned if parent < 0 else skeleton.get_bone_global_pose(parent).affine_inverse() * turned
	skeleton.set_bone_pose_rotation(bone, local_pose.basis.get_rotation_quaternion())
