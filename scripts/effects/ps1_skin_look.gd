class_name PS1SkinLook
extends Node
## PS1-style skin of a rigged mech and everything it carries (user request 2026-10-11): every body mesh
## and every weapon or equipment mesh under the mech keeps its own colors and gets the PS1 effects
## (PS1Skin: chunky pixels, seams / rivets / vents / dirt detail, 15-bit color with a dither, a light
## vertex wobble). Weapons added later (loadout change, garage) are skinned when they enter the tree.
## Body detail sits on each part's rest position (to_rest each frame, like CharDamageLook), so it
## stays on the part; weapon meshes are rigid, so theirs is in their own mesh space.

@export var hitboxes: SkeletalHitboxes
## The mech root: weapon and equipment meshes under it get the skin too.
@export var mech: Node3D
@export var settings: PS1SkinSettings = preload("res://data/skins/ps1_skin.tres")

## Body meshes and their skin materials: [MeshInstance3D, Array[ShaderMaterial]].
var _skins: Array = []
var _skinned: Dictionary = {}
var _count := 0


func _ready() -> void:
	# The player's saved PS1 tuning (garage menu) goes on the shared settings first.
	if settings == preload("res://data/skins/ps1_skin.tres"):
		settings = PS1Tuning.settings()
	var skeleton := hitboxes.skeleton
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		var bone_name := String(skeleton.get_bone_name(hitboxes.mesh_bones[mesh]))
		var joint := String(mesh.name).to_lower().contains("joint") or bone_name.begins_with("hand")
		_skins.append([mesh, _skin(mesh, joint)])
	skeleton.skeleton_updated.connect(_follow_bones)
	if mech != null:
		for node in mech.find_children("*", "MeshInstance3D", true, false):
			_skin_equipment(node)
		get_tree().node_added.connect(_on_node_added)


func _skin(mesh: MeshInstance3D, joint: bool) -> Array[ShaderMaterial]:
	_skinned[mesh] = true
	_count += 1
	return PS1Skin.apply(mesh, settings, joint, _count)


## A weapon or equipment mesh (not a body part) under the mech.
func _skin_equipment(node: Node) -> void:
	if is_instance_valid(node) and node is MeshInstance3D and not _skinned.has(node) \
			and not hitboxes.mesh_bones.has(node):
		_skin(node as MeshInstance3D, false)


func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D and is_instance_valid(mech) and mech.is_ancestor_of(node):
		_skin_equipment.call_deferred(node)


func _follow_bones() -> void:
	for pair: Array in _skins:
		var mesh := pair[0] as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		var to_rest := Projection(hitboxes.mesh_to_rest(mesh))
		for material: ShaderMaterial in pair[1]:
			material.set_shader_parameter(&"to_rest", to_rest)
