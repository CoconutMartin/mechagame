class_name WeaponPose
extends Node
## Moves the weapon between the rest pose and the aim pose.
## The rest pose comes from the rest_pose marker (for example one-hand high ready: weapon upright
## beside the right shoulder). Aim pose: stock at aim_anchor (right shoulder for a two-hand weapon,
## right hip for one-hand hip fire), weapon points at MechAim.aim_point.
## The arms follow their IK targets with TwoBoneIK. For a two-hand weapon this script also moves the
## left hand between two grip markers on the weapon. For a one-hand weapon the left arm is free
## (ShieldPose moves it). It also blends the elbow directions.
## A one-hand gun or the pile bunker in the left hand has its own WeaponPose (left_arm true).
## Phase 3: WeaponController can set the weapon, its rest transform, aim anchor and raise state at
## start (use_weapon_data). A MechWeapon can change the pose (for example the blade swing).

@export var weapon: Node3D
## Rest pose of the weapon. Same parent as the weapon.
@export var rest_pose: Node3D
## Stock position in the aim pose. Same parent as the weapon.
@export var aim_anchor: Node3D
@export var mech_aim: MechAim
@export var input: MechInput
## Optional. Adds the shot kick to the weapon pose.
@export var recoil: WeaponRecoil
## Optional. Adds the swing and bounce off the body while moving (two-hand weapons at rest).
@export var bounce: WeaponBounce
## How fast the weapon comes up to aim (1 / seconds).
@export var raise_speed: float = 3.0
## How fast the weapon goes down to rest (1 / seconds).
@export var lower_speed: float = 0.8
## One-hand gun (no left grip): when the aim goes up or down it turns about this place (the right
## elbow, weapon parent space), so the gun and the forearm turn together and the level hold (stock off
## the forearm) stays the same. Off (one_hand_elbow_pivot false): about the stock.
@export var one_hand_elbow_pivot: bool = true
@export var one_hand_pivot: Vector3 = Vector3(2.18, 1.16, -0.05)
## One-hand weapons (user report 2026-10-16: the hand left the wrist): the weapon moves toward the
## shoulder until its grip is at most this part of the arm length (upper arm + forearm) from it, so the
## arm reaches the grip and the hand stays on the wrist. The aim direction does not change.
@export_range(0.5, 1.0) var max_reach_share: float = 0.92
## A one-hand gun at rest sways with the stride (user request 2026-10-24): the gun and the arm turn about the
## shoulder by this part of the empty arm's swing (FreeArmSwing.swing), so the gun arm is not dead while the
## other arm swings. 0 = off. It fades out while the gun is raised.
@export_range(0.0, 1.0) var gun_sway_share: float = 0.35

@export_group("Hands")
## Optional (two-hand rifles): the right hand IK target slides between a rest and an aim place on the
## weapon, like the left hand (the fist sits on the grip in both holds).
@export var right_grip_target: Node3D
@export var right_grip_rest: Node3D
@export var right_grip_aim: Node3D
## The left hand IK target on the weapon. Leave empty for a one-hand weapon.
@export var left_grip_target: Node3D
## Left hand place in the rest pose (on the weapon).
@export var left_grip_rest: Node3D
## Left hand place in the aim pose (on the weapon).
@export var left_grip_aim: Node3D
@export var arm_ik_left: TwoBoneIK
@export var arm_ik_right: TwoBoneIK
## True: this pose holds a one-hand weapon in the LEFT hand (a second WeaponPose made by
## WeaponController, user rule 2026-10-15). The places and elbow directions it gets are already
## mirrored; only the arm whose elbow it steers changes (arm_ik_left).
@export var left_arm: bool = false
## Elbow directions in the rest pose: both elbows out to the side.
@export var left_pole_rest: Vector3 = Vector3(-1.0, -0.4, 0.3)
@export var right_pole_rest: Vector3 = Vector3(1.0, 0.0, 0.5)
## Elbow directions in the aim pose: right elbow out and down, left elbow under the rifle.
@export var left_pole_aim: Vector3 = Vector3(-0.3, -1.0, 0.0)
@export var right_pole_aim: Vector3 = Vector3(1.0, -0.6, 0.3)
## Low aim (user choice 2026-10-18, "Slide hand back"): a long rifle with GripLeftAimLow (and
## GripSocketLeftAimLow) markers moves the left aim hold from GripLeftAim back to them as the aim goes
## down, so the left upper arm stays inside its swing limit (SkeletalArmRig) and the rifle is not
## dragged to the hand. Aim pitch (degrees against the world up, down is negative) where the slide starts.
@export_range(-45.0, 15.0) var low_aim_start_deg: float = -3.0
## Aim pitch (degrees) where the left hand is fully at the low place.
@export_range(-60.0, 0.0) var low_aim_full_deg: float = -14.0
## How fast the left hand slides between the aim and the low place (whole slides per second), so a
## quick camera turn does not pull the fist off the wrist.
@export var low_aim_speed: float = 3.0

## 0 = rest pose, 1 = aim pose.
var aim_amount: float = 0.0
## 0 = left aim hold at GripLeftAim, 1 = at GripLeftAimLow (low aim). Stays 0 without that marker.
## MechHandControl reads it to slide the left aim socket the same way.
var low_aim_amount: float = 0.0
## Set by WeaponController: rest transform and aim anchor position come from the weapon data,
## and wants_raise replaces the aim key.
var use_weapon_data: bool = false
var rest_transform: Transform3D = Transform3D.IDENTITY
var aim_origin: Vector3 = Vector3.ZERO
## Weapon-space shift of the aim pose (a borrowed hold, BorrowedHold.shift): the weapon moves by it after it is
## aimed from aim_origin.
var aim_shift: Vector3 = Vector3.ZERO
var wants_raise: bool = false
var _swing: FreeArmSwing


func _ready() -> void:
	# After MechAim and before the arm IK.
	process_physics_priority = 5


func _physics_process(delta: float) -> void:
	if weapon == null:
		return
	var raise := wants_raise if use_weapon_data else input.aim_held
	var speed := raise_speed if raise else lower_speed
	aim_amount = move_toward(aim_amount, 1.0 if raise else 0.0, speed * delta)
	var t := smoothstep(0.0, 1.0, aim_amount)

	var parent := weapon.get_parent_node_3d()
	var origin := aim_origin if use_weapon_data else aim_anchor.transform.origin
	var rest := rest_transform if use_weapon_data else rest_pose.transform
	var target := parent.global_transform.affine_inverse() * mech_aim.aim_point
	var aim_pose := Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin).translated_local(aim_shift)
	low_aim_amount = move_toward(low_aim_amount, _low_aim(mech_aim.aim_point - parent.global_transform * origin),
			low_aim_speed * delta)
	if one_hand_elbow_pivot and left_grip_target == null and weapon is GunWeapon \
			and not weapon is ForearmGunWeapon:
		aim_pose.origin = one_hand_pivot + aim_pose.basis * (origin - one_hand_pivot)
	if weapon is MechWeapon:
		weapon.transform = (weapon as MechWeapon).get_pose(rest, aim_pose, t)
	else:
		weapon.transform = rest.interpolate_with(aim_pose, t)
	if left_grip_target == null and not weapon is ForearmGunWeapon and not weapon is MeleeWeapon:
		_sway_gun(parent, left_arm, 1.0 - t)
	if recoil != null:
		weapon.transform = weapon.transform * recoil.get_offset()
	if bounce != null:
		weapon.position += bounce.offset * bounce.amount()

	var hold_ik := arm_ik_left if left_arm else arm_ik_right
	if left_grip_target == null and not weapon is ForearmGunWeapon:
		_keep_in_reach(hold_ik)
	hold_ik.pole_direction = right_pole_rest.lerp(right_pole_aim, t)
	if right_grip_target != null and right_grip_rest != null and right_grip_aim != null:
		right_grip_target.position = right_grip_rest.position.lerp(right_grip_aim.position, t)
	if left_grip_target == null:
		return  # One-hand weapon: the left arm is free.
	left_grip_target.position = left_grip_rest.position.lerp(left_aim_position(), t)
	arm_ik_left.pole_direction = left_pole_rest.lerp(left_pole_aim, t)


## The gun at rest turns about the shoulder (torso space, forward is positive about the torso's right axis) by
## gun_sway_share of the stride swing of that arm; weight is 1 at rest and 0 when raised.
func _sway_gun(parent: Node3D, left: bool, weight: float) -> void:
	var swing_node := _arm_swing()
	var ik := arm_ik_left if left else arm_ik_right
	if swing_node == null or ik == null or ik.root_joint == null or gun_sway_share <= 0.0 or weight <= 0.0:
		return
	var angle := swing_node.swing(not left).x * gun_sway_share * weight
	if absf(angle) < 0.00001:
		return
	var pivot := parent.global_transform.affine_inverse() * ik.root_joint.global_position
	var turn := Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO)
	weapon.transform = Transform3D(Basis(), pivot) * turn * Transform3D(Basis(), -pivot) * weapon.transform


## The mech's FreeArmSwing (found on first use; Mech adds it at runtime), or null.
func _arm_swing() -> FreeArmSwing:
	if _swing == null or not is_instance_valid(_swing):
		var node: Node = get_parent()
		while node != null and not node is Mech:
			node = node.get_parent()
		_swing = node.get_node_or_null(^"FreeArmSwing") as FreeArmSwing if node != null else null
	return _swing


## The left hand place in the aim pose (weapon space): GripLeftAim, slid toward GripLeftAimLow by
## low_aim_amount.
func left_aim_position() -> Vector3:
	var low := _low_marker()
	if low == null:
		return left_grip_aim.position
	return left_grip_aim.position.lerp(low.position, low_aim_amount)


## 0..1: how far the left aim hold slides to the low place at this aim direction (world space; the
## torso pitches with the aim in the sniping stance, so the pitch is taken against the world up).
func _low_aim(direction: Vector3) -> float:
	var flat := Vector2(direction.x, direction.z).length()
	if _low_marker() == null or flat + absf(direction.y) < 0.001:
		return 0.0
	return smoothstep(low_aim_start_deg, low_aim_full_deg, rad_to_deg(atan2(direction.y, flat)))


func _low_marker() -> Node3D:
	if left_grip_target == null or left_grip_aim == null or weapon == null:
		return null
	return weapon.get_node_or_null(^"GripLeftAimLow") as Node3D


## Moves a one-hand weapon toward the shoulder when its grip is out of the arm's reach.
func _keep_in_reach(ik: TwoBoneIK) -> void:
	if ik == null or ik.root_joint == null:
		return
	var grip := weapon.get_node_or_null(^"GripLeft" if left_arm else ^"GripRight") as Node3D
	if grip == null:
		return
	var to_grip := grip.global_position - ik.root_joint.global_position
	var reach := (ik.upper_length + ik.lower_length) * max_reach_share
	var distance := to_grip.length()
	if distance > reach:
		weapon.global_position -= to_grip / distance * (distance - reach)
