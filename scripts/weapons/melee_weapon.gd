class_name MeleeWeapon
extends MechWeapon
## A melee weapon (user request 2026-10-15): fists (one per arm, its own mouse button: LMB left,
## RMB right) and the two-hand hammer (either mouse button). The mouse button plus the move keys
## picks the attack (SkeletalMeleeAnimation). The model sits on the hand bone (BoneAttachment3D), and
## the arm follows the animation (no grip IK).

## True for a weapon on the left arm (set by WeaponController).
var is_left: bool = false
## Moves the model with the hand.
var _attachment: BoneAttachment3D
var _model: Node3D
var _melee: SkeletalMeleeAnimation


func is_melee() -> bool:
	return true


func is_busy() -> bool:
	return _melee != null and _melee.is_attacking_with(self)


## The model, on the hand (PartBreaker drops it with the arm).
func get_model() -> Node3D:
	return _model


## The hand bone that holds the weapon.
func get_hand_bone() -> String:
	return "hand_L" if is_left else "hand_R"


## Where the weapon hits (world position): the "StrikePoint" marker of the model.
func get_strike_point() -> Vector3:
	var point := _model.get_node_or_null("StrikePoint") as Node3D if is_instance_valid(_model) else null
	return point.global_position if point != null else global_position


## Puts the model on the hand bone. Called by WeaponController after setup (is_left is known then).
func attach_to_hand() -> void:
	var skeleton := controller.mech.find_child("Skeleton3D", true, false) as Skeleton3D
	_melee = controller.mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	_model = get_node_or_null("Model") as Node3D
	if skeleton == null or _model == null:
		return
	_attachment = BoneAttachment3D.new()
	_attachment.name = "%sAttachment" % name
	skeleton.add_child(_attachment)
	_attachment.bone_name = get_hand_bone()
	var local := _model.transform
	if is_left:
		# Both hand bones have the same axes; only the X place is the mirror (the palm sides face).
		local.origin.x = -local.origin.x
	_model.reparent(_attachment, false)
	_model.transform = local


## No ammo or heat to show.
func get_status_text() -> String:
	return ""


func _update(_delta: float) -> void:
	if trigger_pressed() and _melee != null:
		_melee.request(self)


func _exit_tree() -> void:
	if is_instance_valid(_attachment) and _attachment.get_child_count() == 0:
		_attachment.queue_free()
