class_name SkeletalAssembler
extends Node
## Builds a skeletal mech from a Loadout: the part models (one glTF per part, made with
## tools/blender/export_std_parts.py) go onto the standard rig's skeleton. Every part is skinned to
## the same standard bones (found by name), so any part of the rig's size fits and plays the rig's
## animations. Keep this node before Visual and the logic nodes, so the parts exist before the
## hitboxes and part breaking look for their meshes.

@export var loadout: Loadout
## The standard rig model (models/std_rig/<size>/std_<size>_rig.glb): skeleton and animations.
@export var model: Node3D
## Skinned meshes in the rig file that only exist to make Godot import a skeleton.
@export var anchor_names: PackedStringArray = PackedStringArray(["RigAnchor"])

## Meshes each part added, by loadout slot name ("head", "core", "arm_left"...).
var part_meshes: Dictionary = {}


func _ready() -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	for anchor_name in anchor_names:
		var anchor := skeleton.find_child(anchor_name, false, false)
		if anchor != null:
			anchor.free()
	if loadout == null:
		return
	for slot: StringName in [&"head", &"core", &"arm_left", &"arm_right", &"legs", &"booster"]:
		var part := loadout.get(slot) as PartData
		if part != null and part.scene != null:
			part_meshes[slot] = attach(part.scene, skeleton)


## Moves the skinned meshes of one part model onto the skeleton. Returns the meshes it added.
static func attach(scene: PackedScene, skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var added: Array[MeshInstance3D] = []
	var model := scene.instantiate()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null:
			push_warning("SkeletalAssembler: %s in %s has no skin" % [mesh.name, scene.resource_path])
			continue
		for i in mesh.skin.get_bind_count():
			var bone_name := mesh.skin.get_bind_name(i)
			if bone_name != &"" and skeleton.find_bone(bone_name) < 0:
				push_warning("SkeletalAssembler: %s uses bone %s, not in the rig" % [mesh.name, bone_name])
				break
		var place := mesh.transform
		mesh.get_parent().remove_child(mesh)
		mesh.owner = null
		skeleton.add_child(mesh)
		mesh.transform = place
		mesh.skeleton = NodePath("..")
		added.append(mesh)
	model.free()
	return added
