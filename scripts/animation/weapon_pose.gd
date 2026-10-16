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

## 0 = rest pose, 1 = aim pose.
var aim_amount: float = 0.0
## Set by WeaponController: rest transform and aim anchor position come from the weapon data,
## and wants_raise replaces the aim key.
var use_weapon_data: bool = false
var rest_transform: Transform3D = Transform3D.IDENTITY
var aim_origin: Vector3 = Vector3.ZERO
var wants_raise: bool = false


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
	var aim_pose := Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)
	if one_hand_elbow_pivot and left_grip_target == null and weapon is GunWeapon \
			and not weapon is ForearmGunWeapon:
		aim_pose.origin = one_hand_pivot + aim_pose.basis * (origin - one_hand_pivot)
	if weapon is MechWeapon:
		weapon.transform = (weapon as MechWeapon).get_pose(rest, aim_pose, t)
	else:
		weapon.transform = rest.interpolate_with(aim_pose, t)
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
	left_grip_target.position = left_grip_rest.position.lerp(left_grip_aim.position, t)
	arm_ik_left.pole_direction = left_pole_rest.lerp(left_pole_aim, t)


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
