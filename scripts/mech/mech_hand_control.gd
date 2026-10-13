class_name MechHandControl
extends Node
## Drives the two jointed hands (MechHand, user request 2026-10-13) of a rigged mech from what each hand
## does: a gun's grip (the fingers fit around it), the left hand on a two-hand weapon (around the
## forestock), the shield or the pile bunker (a fist), or nothing (a fist while the mech moves, a relaxed
## open hand while it stands). It hides the old hand meshes, and a hand whose arm is destroyed.
## The grips are where the arm IK puts the old grip bones (grip_R, grip_L): the right fist hollow is
## PALM_HOLLOW from grip_R (tools/mech_gen/arm_poses.py), the left grip is at grip_L.

const PALM_HOLLOW := Vector3(0.2, 0.0, 0.18)

@export var mech: Mech
@export var skeleton: Skeleton3D
@export var weapons: WeaponController
@export var health: MechHealth
@export var hitboxes: SkeletalHitboxes
@export var hand_right: MechHand
@export var hand_left: MechHand
## Grip cylinder radius (meters): gun pistol grips, and the forestock under a two-hand weapon.
@export var grip_radius: float = 0.12
@export var forestock_radius: float = 0.15
## Moving faster than this (m/s), a free hand makes a fist.
@export var fist_speed: float = 1.0
@export var grip_bones: PackedStringArray = ["grip_L", "grip_R"]
## Old hand meshes: meshes skinned to bones with these name starts are hidden.
@export var old_hand_bones: PackedStringArray = ["hand_", "index_", "middle_", "ring_", "pinky_", "thumb_", "grip_"]


func _ready() -> void:
	_hide_old_hands.call_deferred()
	if health != null:
		health.part_destroyed.connect(_on_part_destroyed)


func _process(_delta: float) -> void:
	if skeleton == null or weapons == null:
		return
	var moving := mech != null and Vector3(mech.velocity.x, 0.0, mech.velocity.z).length() > fist_speed
	if is_instance_valid(hand_right) and hand_right.visible:
		var gun := weapons.right_weapon
		if gun != null and is_instance_valid(gun) and not gun is PileBunkerWeapon:
			var grip := _grip_pose(grip_bones[1])
			hand_right.set_grip(grip * PALM_HOLLOW, grip.basis.y, grip_radius)
		elif gun != null and is_instance_valid(gun):
			hand_right.mode = MechHand.Mode.FIST
		else:
			hand_right.mode = MechHand.Mode.FIST if moving else MechHand.Mode.RELAXED
	if is_instance_valid(hand_left) and hand_left.visible:
		if weapons.two_handed_left_grip() and weapons.right_weapon != null and is_instance_valid(weapons.right_weapon):
			var grip := _grip_pose(grip_bones[0])
			hand_left.set_grip(grip.origin, grip.basis.y, forestock_radius)
		elif weapons.left_data != null:
			hand_left.mode = MechHand.Mode.FIST
		else:
			hand_left.mode = MechHand.Mode.FIST if moving else MechHand.Mode.RELAXED


func _grip_pose(bone_name: StringName) -> Transform3D:
	var bone := skeleton.find_bone(bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone)


func _hide_old_hands() -> void:
	if hitboxes == null:
		return
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		var bone_name := String(skeleton.get_bone_name(hitboxes.mesh_bones[mesh]))
		for start in old_hand_bones:
			if bone_name.begins_with(start):
				mesh.visible = false
				break


func _on_part_destroyed(key: String) -> void:
	if key == "Arm R" and is_instance_valid(hand_right):
		hand_right.visible = false
	elif key == "Arm L" and is_instance_valid(hand_left):
		hand_left.visible = false
