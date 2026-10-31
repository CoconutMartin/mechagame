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

## Slot names: the Loadout properties of the part slots, in build order.
const SLOTS: Array[StringName] = [&"head", &"core", &"arm_left", &"arm_right", &"legs"]
## Mesh meta: the slot the mesh came from.
const SLOT_META := &"mech_part_slot"

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
