class_name PS1SkinLook
extends Node
## Skin of a rigged mech and everything it carries: every body mesh and every weapon or equipment
## mesh under the mech keeps its own colors and gets the skin the player picked in the garage
## (MechSkinChoice, user request 2026-10-13):
##   Basic: the model's own materials.
##   PS1 (user request 2026-10-11): PS1Skin (chunky pixels, seams / rivets / vents / dirt detail,
##   15-bit color with a dither, a light vertex wobble).
##   Realistic: RealisticSkin (painted metal with a worn metal plate texture, normal and roughness maps).
## Weapons added later (loadout change, garage) are skinned when they enter the tree.
## Body detail sits on each part's rest position (to_rest each frame, like CharDamageLook), so it
## stays on the part; weapon meshes are rigid, so theirs is in their own mesh space.

@export var hitboxes: SkeletalHitboxes
## The mech root: weapon and equipment meshes under it get the skin too.
@export var mech: Node3D
@export var settings: PS1SkinSettings = preload("res://data/skins/ps1_skin.tres")

## One entry per skinned mesh: {mesh, joint, body, index, overrides (the mesh's own surface
## overrides), override (its own material_override), made (the skin materials in use)}.
var _entries: Array[Dictionary] = []
var _skinned: Dictionary = {}
var _count := 0
var _style := MechSkinChoice.Style.PS1


func _ready() -> void:
	add_to_group(MechSkinChoice.GROUP)
	_style = MechSkinChoice.style()
	# The player's saved PS1 tuning (garage menu) goes on the shared settings first.
	if settings == preload("res://data/skins/ps1_skin.tres"):
		settings = PS1Tuning.settings()
	var skeleton := hitboxes.skeleton
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		var bone_name := String(skeleton.get_bone_name(hitboxes.mesh_bones[mesh]))
		var joint := String(mesh.name).to_lower().contains("joint") or bone_name.begins_with("hand")
		_add(mesh, joint, true)
	skeleton.skeleton_updated.connect(_follow_bones)
	if mech != null:
		for node in mech.find_children("*", "MeshInstance3D", true, false):
			_skin_equipment(node)
		get_tree().node_added.connect(_on_node_added)


## Changes the skin on every mesh of this mech.
func set_style(value: MechSkinChoice.Style) -> void:
	_style = value
	_entries = _entries.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry.mesh))
	for entry in _entries:
		_restore(entry)
		_apply(entry)


func _add(mesh: MeshInstance3D, joint: bool, body: bool) -> void:
	_skinned[mesh] = true
	_count += 1
	var overrides: Array[Material] = []
	for surface in mesh.get_surface_override_material_count():
		overrides.append(mesh.get_surface_override_material(surface))
	var entry := {"mesh": mesh, "joint": joint, "body": body, "index": _count, "overrides": overrides,
			"override": mesh.material_override, "made": [] as Array[ShaderMaterial]}
	_entries.append(entry)
	_apply(entry)


func _apply(entry: Dictionary) -> void:
	var mesh := entry.mesh as MeshInstance3D
	match _style:
		MechSkinChoice.Style.PS1:
			entry.made = PS1Skin.apply(mesh, settings, entry.joint, entry.index)
		MechSkinChoice.Style.REALISTIC:
			entry.made = RealisticSkin.apply(mesh, entry.joint, entry.body, entry.index)
		_:
			entry.made = [] as Array[ShaderMaterial]


## Back to the mesh's own materials.
func _restore(entry: Dictionary) -> void:
	var mesh := entry.mesh as MeshInstance3D
	var overrides: Array[Material] = entry.overrides
	for surface in mesh.get_surface_override_material_count():
		mesh.set_surface_override_material(surface, overrides[surface] if surface < overrides.size() else null)
	mesh.material_override = entry.override
	entry.made = [] as Array[ShaderMaterial]


## A weapon or equipment mesh (not a body part) under the mech.
func _skin_equipment(node: Node) -> void:
	if is_instance_valid(node) and node is MeshInstance3D and not _skinned.has(node) \
			and not hitboxes.mesh_bones.has(node):
		_add(node as MeshInstance3D, false, false)


func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D and is_instance_valid(mech) and mech.is_ancestor_of(node):
		_skin_equipment.call_deferred(node)


func _follow_bones() -> void:
	for entry in _entries:
		# Check before the cast: casting a freed mesh (a part that broke off) is an error.
		if not entry.body or (entry.made as Array).is_empty() or not is_instance_valid(entry.mesh):
			continue
		var mesh := entry.mesh as MeshInstance3D
		var to_rest := Projection(hitboxes.mesh_to_rest(mesh))
		for material: ShaderMaterial in entry.made:
			material.set_shader_parameter(&"to_rest", to_rest)
