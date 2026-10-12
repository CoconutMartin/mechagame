class_name PS1WorldLook
extends Node
## PS1 look for the whole environment (user request 2026-10-12): every mesh under root (ground,
## buildings, props, cars, people) and every mesh added later (rubble, debris, falling chunks, broken
## props) keeps its colors and texture and gets the PS1 effects (PS1World). Mechs keep their own PS1
## skin (PS1SkinLook), and effects (flashes, beams, particles) keep their materials.
## Uses the same settings as the mech skin (data/skins/ps1_skin.tres).

@export var settings: PS1SkinSettings = preload("res://data/skins/ps1_skin.tres")
## Everything under this node gets the look (empty = the parent, the map).
@export var root: Node
@export var enabled: bool = true


func _ready() -> void:
	if not enabled:
		return
	if root == null:
		root = get_parent()
	_apply_tree(root)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_apply_deferred.call_deferred(node)


func _apply_deferred(node: Node) -> void:
	if is_instance_valid(node) and node.is_inside_tree():
		_apply(node as GeometryInstance3D)


## Walks the tree, generated (internal) children too: buildings and ground boxes make theirs.
func _apply_tree(node: Node) -> void:
	if node is Mech:
		return
	if node is GeometryInstance3D:
		_apply(node as GeometryInstance3D)
	for child in node.get_children(true):
		_apply_tree(child)


func _apply(geometry: GeometryInstance3D) -> void:
	if geometry is CPUParticles3D or geometry is GPUParticles3D or _in_mech(geometry):
		return
	if geometry.material_override != null:
		var made := PS1World.convert(geometry.material_override, settings)
		if made != null:
			geometry.material_override = made
		return
	if geometry is MultiMeshInstance3D:
		var multimesh := (geometry as MultiMeshInstance3D).multimesh
		if multimesh != null and multimesh.mesh != null and multimesh.mesh.get_surface_count() > 0:
			var made := PS1World.convert(multimesh.mesh.surface_get_material(0), settings)
			if made != null:
				geometry.material_override = made
		return
	var mesh := geometry as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	for surface in mesh.mesh.get_surface_count():
		var made := PS1World.convert(mesh.get_active_material(surface), settings)
		if made != null:
			mesh.set_surface_override_material(surface, made)


func _in_mech(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is Mech:
			return true
		parent = parent.get_parent()
	return false
