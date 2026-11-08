class_name SkeletalPartModels
extends Node
## Puts the part models of the loadout (head, core, arms, legs) on the rigged mech's shared skeleton
## (user request 2026-10-31, DESIGN "Swappable mech parts"). Each part model is a .glb made by
## tools/blender/export_mech_parts.py: the standard rig at rest and the part's meshes, skinned to the
## standard bone names. The meshes move onto the mech skeleton and keep their skin, so they follow the
## animation like the old one-file model did. A slot with no part in the loadout uses the default part.
##
## It works in _enter_tree, before the other nodes of the mech are in the tree, so every node that reads
## the meshes in _ready (SkeletalHitboxes, skins, HP indicators, MechHandControl) sees the new parts.
## Keep this node before Visual in the mech's children (build_sanggigilid.gd puts it first).
## A part brings its joints (DESIGN "Three rigs"): the legs pick the mech scene, and the core and arms here set the bone offsets of
## the skeleton from their own rig, so a part of another rig keeps its size. The clips then keep only their rotations on those bones.
## The torso bone is the exception: it sits on the legs' waist socket (the hip ball joint, DESIGN "Waist ball joint"), so a core on
## another mech's legs neither floats above the pelvis nor sinks into it.

## Slot names: the Loadout properties of the part slots, in build order.
const SLOTS: Array[StringName] = [&"head", &"core", &"arm_left", &"arm_right", &"legs"]
## Mesh meta: the slot the mesh came from.
const SLOT_META := &"mech_part_slot"
## Bones whose offset comes from the core's rig.
const CORE_BONES: Array[StringName] = [&"torso", &"head", &"upper_arm_L", &"upper_arm_R"]
## Bones whose offset comes from the arm's rig (with the side added).
const ARM_BONES: Array[String] = ["forearm_", "hand_", "sleeve_", "grip_", "index_01_", "index_02_", "index_03_", "middle_01_", "middle_02_",
		"middle_03_", "ring_01_", "ring_02_", "ring_03_", "pinky_01_", "pinky_02_", "pinky_03_", "thumb_01_", "thumb_02_", "thumb_03_"]
## An offset this close (m) to the skeleton's own counts as the same.
const SAME_OFFSET := 0.001

## The rigged model (rig file, its Skeleton3D is found inside).
@export var model: Node3D
## The node that holds the loadout (WeaponMount).
@export var loadout_holder: Node
@export_group("Default parts")
## Parts for the slots the loadout leaves empty (SGG-101).
@export var default_head: HeadPart
@export var default_core: CorePart
@export var default_arm_left: ArmPart
@export var default_arm_right: ArmPart
@export var default_legs: LegPart

## Part meshes by slot name (after the build).
var meshes_by_slot: Dictionary = {}
## Move of the torso at rest (skeleton space, m) from the place on the core's own rig to the legs' waist socket. Zero on a pure mech.
## Things placed in mech space from core data (the back pack) add it.
var torso_shift := Vector3.ZERO
## Arm slot -> the shoulder (upper arm bone) place at rest on the arm part's own rig, skeleton space.
var _arm_rig_shoulders: Dictionary = {}
var _built := false


func _enter_tree() -> void:
	if _built:
		return
	_built = true
	build()


## Removes the meshes the rig file brings (its anchor) and adds the part meshes.
func build() -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("SkeletalPartModels: no Skeleton3D in %s" % model.name)
		return
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			skeleton.remove_child(child)
			child.free()
	var loadout: Loadout = loadout_holder.get(&"loadout") if loadout_holder != null else null
	for slot in SLOTS:
		var part := get_part(loadout, slot)
		meshes_by_slot[slot] = _add_part(skeleton, part, slot) if part != null else []
		_set_hand(part as ArmPart, slot)
		_set_relaxed_hand(part as ArmPart, slot)
	_join_waist(skeleton, get_part(loadout, &"core") as CorePart, get_part(loadout, &"legs") as LegPart)
	_join_shoulders(skeleton)


## The part in a slot: the loadout's, else the default.
func get_part(loadout: Loadout, slot: StringName) -> PartData:
	var part: PartData = loadout.get(slot) if loadout != null else null
	return part if part != null else get(StringName("default_" + slot)) as PartData


func _add_part(skeleton: Skeleton3D, part: PartData, slot: StringName) -> Array[MeshInstance3D]:
	var added: Array[MeshInstance3D] = []
	if part.scene == null:
		return added
	var source := part.scene.instantiate()
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	if source_skeleton == null:
		push_error("SkeletalPartModels: part %s has no Skeleton3D" % part.display_name)
		source.free()
		return added
	_set_offsets(skeleton, source_skeleton, _slot_bones(slot))
	var upper := source_skeleton.find_bone(_upper_arm(slot))
	if upper >= 0:
		_arm_rig_shoulders[slot] = source_skeleton.get_bone_global_rest(upper).origin
	for child in source_skeleton.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		source_skeleton.remove_child(mesh)
		mesh.owner = null
		mesh.set_meta(SLOT_META, slot)
		skeleton.add_child(mesh, true)
		# The skin binds by bone name, so a part made on the standard rig fits this skeleton.
		mesh.skeleton = mesh.get_path_to(skeleton) if mesh.is_inside_tree() else NodePath("..")
		added.append(mesh)
	source.free()
	return added


func _slot_bones(slot: StringName) -> Array[StringName]:
	var bones: Array[StringName] = []
	if slot == &"core":
		bones = CORE_BONES.duplicate()
	elif slot == &"arm_left" or slot == &"arm_right":
		var side := "L" if slot == &"arm_left" else "R"
		for bone in ARM_BONES:
			bones.append(StringName(bone + side))
	return bones


## Copies the part rig's bone offsets onto the mech skeleton. Rest rotations are the same on every rig.
func _set_offsets(skeleton: Skeleton3D, source: Skeleton3D, bones: Array[StringName]) -> void:
	var changed := false
	for bone_name in bones:
		var bone := skeleton.find_bone(bone_name)
		var from := source.find_bone(bone_name)
		if bone < 0 or from < 0:
			continue
		var offset := source.get_bone_rest(from).origin
		var rest := skeleton.get_bone_rest(bone)
		if rest.origin.distance_to(offset) < SAME_OFFSET:
			continue
		rest.origin = offset
		skeleton.set_bone_rest(bone, rest)
		skeleton.set_bone_pose_position(bone, offset)
		changed = true
	if changed:
		_drop_position_tracks(bones)


## The clips' position tracks hold the offsets of the rig they were baked on: without them these bones keep the part's offsets.
func _drop_position_tracks(bones: Array[StringName]) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for track in range(animation.get_track_count() - 1, -1, -1):
			if animation.track_get_type(track) == Animation.TYPE_POSITION_3D \
					and StringName(animation.track_get_path(track).get_subname(0)) in bones:
				animation.remove_track(track)


## Puts the core's waist ball on the legs' waist socket (user 2026-11-08: "The torso should be joined at the hip 'ball joint'"). Same
## rig on both: the torso keeps its offset. Head and arms ride the torso bone, so they move with it.
func _join_waist(skeleton: Skeleton3D, core: CorePart, legs: LegPart) -> void:
	var bone := skeleton.find_bone(&"torso")
	if core == null or legs == null or legs.waist_socket == Vector3.ZERO or bone < 0:
		return
	var rest := skeleton.get_bone_rest(bone)
	var origin := legs.waist_socket - rest.basis * core.waist_ball
	if rest.origin.distance_to(origin) < SAME_OFFSET:
		return
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	torso_shift = parent_basis * (origin - rest.origin)
	rest.origin = origin
	skeleton.set_bone_rest(bone, rest)
	skeleton.set_bone_pose_position(bone, origin)
	var moved: Array[StringName] = [&"torso"]
	_drop_position_tracks(moved)
	for mesh: MeshInstance3D in meshes_by_slot.get(&"core", []):
		_rebind(mesh, &"pelvis", &"torso")


## The upper arm bone of an arm slot ("" for the other slots).
func _upper_arm(slot: StringName) -> String:
	if slot == &"arm_left":
		return "upper_arm_L"
	if slot == &"arm_right":
		return "upper_arm_R"
	return ""


## An arm part skinned to the torso at its shoulder (SGG's shoulder ball) follows its upper arm instead when the shoulder is not where the
## arm's own rig has it (another core, or the torso on another waist): the ball stays on the shoulder joint, so the arm does not float
## away from the body (user report 2026-11-08: "HLY body + SGG arms = disconnected and floating arms"). The ball is centered on the
## shoulder's turn point: it looks the same when the arm turns.
func _join_shoulders(skeleton: Skeleton3D) -> void:
	for slot: StringName in _arm_rig_shoulders:
		var bone := skeleton.find_bone(_upper_arm(slot))
		if bone < 0:
			continue
		var own: Vector3 = _arm_rig_shoulders[slot]
		if skeleton.get_bone_global_rest(bone).origin.distance_to(own) < SAME_OFFSET:
			continue
		for mesh: MeshInstance3D in meshes_by_slot.get(slot, []):
			_rebind(mesh, &"torso", StringName(_upper_arm(slot)))


## Moves a mesh's skin binds from one bone to another (with the other bone's bind pose), so those vertices follow the other bone. Used
## for the joint balls (SGG's waist ball onto the torso, the shoulder balls onto the upper arms).
func _rebind(mesh: MeshInstance3D, from: StringName, to: StringName) -> void:
	var skin := mesh.skin
	if skin == null:
		return
	var target := -1
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) == to:
			target = i
	if target < 0:
		return
	var copy: Skin = null
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) != from:
			continue
		if copy == null:
			# The skin resource is shared with the part scene: change a copy.
			copy = skin.duplicate() as Skin
		copy.set_bind_name(i, to)
		copy.set_bind_bone(i, skin.get_bind_bone(target))
		copy.set_bind_pose(i, skin.get_bind_pose(target))
	if copy != null:
		mesh.skin = copy


## An arm part's jointed hand place, measured on its own rig (tools/godot/write_arm_hand_data.gd).
func _set_hand(part: ArmPart, slot: StringName) -> void:
	if part == null or part.wrist_pin == Vector3.ZERO or not (slot == &"arm_left" or slot == &"arm_right"):
		return
	var control := get_parent().get_node_or_null("MechHandControl") as MechHandControl
	if control == null:
		return
	if slot == &"arm_right":
		control.hand_right.transform = part.hand_transform
		control.wrist_pin_right = part.wrist_pin
		control.hand_shift_right = part.hand_shift
	else:
		control.hand_left.transform = part.hand_transform
		control.wrist_pin_left = part.wrist_pin
		control.hand_shift_left = part.hand_shift


## An arm part's neutral arm (ArmPart.neutral_turn) on the arm rig and its relaxed hand place (ArmPart.relaxed_hand) on the mech's hang
## markers, so a part on another mech's legs hangs as on its own (user report 2026-11-08: SGG arms on the HLY body).
func _set_relaxed_hand(part: ArmPart, slot: StringName) -> void:
	if part == null or not (slot == &"arm_left" or slot == &"arm_right"):
		return
	var rig := get_parent().find_child("ArmRig", true, false) as SkeletalArmRig
	if rig != null and not part.neutral_turn.is_equal_approx(Quaternion.IDENTITY):
		if slot == &"arm_left":
			rig.neutral_turn_left = part.neutral_turn
		else:
			rig.neutral_turn_right = part.neutral_turn
	if part.relaxed_hand == Vector3.ZERO:
		return
	var controller := get_parent().get_node_or_null("WeaponController") as WeaponController
	if controller == null:
		return
	var left := controller.free_left_hand
	if left == null:
		left = get_parent().find_child("LeftHandRelaxed", true, false) as Node3D
	if left == null:
		return
	if slot == &"arm_left":
		left.position = part.relaxed_hand
		return
	if controller.free_right_hand == null:
		var right := Marker3D.new()
		right.name = "RightHandRelaxed"
		left.get_parent().add_child(right)
		controller.free_right_hand = right
	controller.free_right_hand.position = Vector3(-part.relaxed_hand.x, part.relaxed_hand.y, part.relaxed_hand.z)
