class_name SkeletalHitboxes
extends Node
## Gives a rigged mech its part HP: adds each part of the data to MechHealth and puts one hitbox per
## bone on the skeleton (a BoneAttachment3D, so the box follows the animation). Each box covers the
## meshes skinned to that bone, at rest.

@export var health: MechHealth
## The rigged model (its Skeleton3D is found inside).
@export var model: Node3D
@export var parts: BoneHitParts
## Meshes smaller than this (m, largest side) are left out (stray bits).
@export var min_mesh_size: float = 0.1

## The rigged model's skeleton.
var skeleton: Skeleton3D
## Part meshes by hit key (a mesh goes to the part of its bone whose X range holds the mesh center).
var part_meshes: Dictionary = {}
## The bone each part mesh follows.
var mesh_bones: Dictionary = {}
var _attachments: Dictionary = {}


func _ready() -> void:
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var meshes := _meshes_by_bone()
	for part: BoneHitPart in parts.parts:
		health.add_part(part.key, part.max_hp)
		var own: Array[MeshInstance3D] = []
		for mesh: MeshInstance3D in mesh_bones:
			var center := (mesh.transform * mesh.get_aabb()).get_center().x
			if skeleton.get_bone_name(mesh_bones[mesh]) in part.bones and center >= part.min_x and center <= part.max_x:
				own.append(mesh)
		part_meshes[part.key] = own
		var cut := AABB(Vector3(part.min_x, -1000.0, -1000.0), Vector3(part.max_x - part.min_x, 2000.0, 2000.0))
		for bone_name: StringName in part.bones:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0 or not meshes.has(bone):
				continue
			var bounds := AABB()
			var first := true
			for box: AABB in meshes[bone]:
				var clipped := box.intersection(cut)
				if clipped.size == Vector3.ZERO:
					continue
				bounds = clipped if first else bounds.merge(clipped)
				first = false
			if first:
				continue
			var local := skeleton.get_bone_global_rest(bone).affine_inverse() * bounds
			health.add_hitbox(part.key, PartHitbox.create(get_attachment(bone), part.key, local, health))


## Model-space boxes of the part meshes, by the bone each mesh follows (the top bone among its
## weights, so a hand with finger bones goes to the hand bone).
func _meshes_by_bone() -> Dictionary:
	var found := {}
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.transform * mesh.get_aabb()
		if mesh.skin == null or box.get_longest_axis_size() < min_mesh_size:
			continue
		var bone := _top_bone(mesh)
		if bone < 0:
			continue
		var list: Array = found.get(bone, [])
		list.append(box)
		found[bone] = list
		mesh_bones[mesh] = bone
	return found


func _top_bone(mesh: MeshInstance3D) -> int:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var best := -1
	var best_depth := 1000
	var seen := {}
	for i in bones.size():
		if weights[i] < 0.01 or seen.has(bones[i]):
			continue
		seen[bones[i]] = true
		var bone := mesh.skin.get_bind_bone(bones[i])
		if bone < 0:
			bone = skeleton.find_bone(mesh.skin.get_bind_name(bones[i]))
		if bone < 0:
			continue
		var depth := 0
		var up := skeleton.get_bone_parent(bone)
		while up >= 0:
			depth += 1
			up = skeleton.get_bone_parent(up)
		if depth < best_depth:
			best_depth = depth
			best = bone
	return best


## The bone attachment node of a bone (made the first time), for hitboxes and smoke.
func get_attachment(bone: int) -> BoneAttachment3D:
	if not _attachments.has(bone):
		var attachment := BoneAttachment3D.new()
		attachment.name = "Hit_" + skeleton.get_bone_name(bone)
		skeleton.add_child(attachment)
		attachment.bone_idx = bone
		_attachments[bone] = attachment
	return _attachments[bone]
