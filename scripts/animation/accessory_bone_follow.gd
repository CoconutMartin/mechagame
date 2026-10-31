class_name AccessoryBoneFollow
extends SkeletonModifier3D
## Turns the hanging armor of the joint standard (skirt panels at the hips, sleeves over the shoulders; the
## accessory bones of tools/blender/mech_rig_standard.py) with the limb next to it, so the limb does not go
## through the plate (user request 2026-10-31, Haliya HLY-101). Each plate turns about its pivot (the bone
## head) by part of its limb's swing; the part of the swing that pushes toward the plate is followed more.
## A mech with no plate on these bones shows nothing; a rig without the bones skips them.
## A skeleton modifier must be a child of the Skeleton3D; this node moves itself there at start, after the
## other modifiers (build_sanggigilid.gd adds it last), so it reads the final limb poses.

## The rigged model (its Skeleton3D is found inside).
@export var model: Node3D
## Plate bone -> limb bone it follows. Plate and limb must have the same parent bone.
@export var follows: Dictionary = {
	&"skirt_front_L": &"thigh_L", &"skirt_front_R": &"thigh_R",
	&"skirt_side_L": &"thigh_L", &"skirt_side_R": &"thigh_R",
	&"skirt_back_L": &"thigh_L", &"skirt_back_R": &"thigh_R",
	&"sleeve_L": &"upper_arm_L", &"sleeve_R": &"upper_arm_R",
}
## Part of the limb's swing the plate always follows.
@export_range(0.0, 1.0) var follow: float = 0.35
## Extra part of the swing toward the plate (the limb pushes the plate away).
@export_range(0.0, 2.0) var push_follow: float = 1.0
## Largest plate turn, in degrees.
@export_range(0.0, 120.0) var max_turn_deg: float = 70.0

## [plate bone, limb bone, push direction in the parent bone's rest frame].
var _pairs: Array = []


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)


func _setup() -> void:
	_pairs.clear()
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for plate_name: StringName in follows:
		var plate := skeleton.find_bone(plate_name)
		var limb := skeleton.find_bone(follows[plate_name])
		if plate < 0 or limb < 0 or skeleton.get_bone_parent(plate) != skeleton.get_bone_parent(limb):
			continue
		# Push direction: from the limb's line to the plate's middle, across the limb (parent rest frame).
		var plate_rest := skeleton.get_bone_rest(plate)
		var limb_rest := skeleton.get_bone_rest(limb)
		var limb_dir := _bone_dir(skeleton, limb, limb_rest)
		var plate_mid := plate_rest.origin + _bone_dir(skeleton, plate, plate_rest) * 0.5 * _bone_length(skeleton, plate)
		var across := plate_mid - limb_rest.origin
		across -= limb_dir * across.dot(limb_dir)
		_pairs.append([plate, limb, across.normalized()])


func _process_modification_with_delta(_delta: float) -> void:
	if _pairs.is_empty():
		_setup()
	var skeleton := get_skeleton()
	var limit := deg_to_rad(max_turn_deg)
	for pair: Array in _pairs:
		var plate: int = pair[0]
		var limb: int = pair[1]
		var push: Vector3 = pair[2]
		# Both bones have the same parent: their local poses share one frame.
		var rest_dir := _bone_dir(skeleton, limb, skeleton.get_bone_rest(limb))
		var now_dir := _bone_dir(skeleton, limb, skeleton.get_bone_pose(limb))
		var move := now_dir - rest_dir
		var toward := maxf(move.dot(push), 0.0)
		var target := (rest_dir + move * follow + push * toward * push_follow).normalized()
		var turn := Quaternion(rest_dir, target) if not rest_dir.is_equal_approx(target) else Quaternion.IDENTITY
		if turn.get_angle() > limit:
			turn = Quaternion.IDENTITY.slerp(turn, limit / turn.get_angle())
		var rest := skeleton.get_bone_rest(plate)
		skeleton.set_bone_pose_rotation(plate, turn * rest.basis.get_rotation_quaternion())


## Bone direction (head to tail) in its parent's frame for a local transform: the bone points along its +Y.
func _bone_dir(_skeleton: Skeleton3D, _bone: int, local: Transform3D) -> Vector3:
	return (local.basis * Vector3.UP).normalized()


func _bone_length(skeleton: Skeleton3D, bone: int) -> float:
	for child in skeleton.get_bone_children(bone):
		return skeleton.get_bone_rest(child).origin.length()
	return 3.0
