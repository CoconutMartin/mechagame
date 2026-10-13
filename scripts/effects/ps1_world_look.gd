class_name PS1WorldLook
extends Node
## PS1 look for the whole environment (user request 2026-10-12): every mesh under root (ground,
## buildings, props, cars, people) and every mesh added later (rubble, debris, falling chunks, broken
## props) keeps its colors and texture and gets the PS1 effects (PS1World). Mechs keep their own PS1
## skin (PS1SkinLook), and effects (flashes, beams, particles) keep their materials.
## Uses the same settings as the mech skin (data/skins/ps1_skin.tres, with the player's tuning).
## On or off from the garage's PS1 menu (PS1Tuning.environment_on, user request 2026-10-13): off puts the
## original materials back.

@export var settings: PS1SkinSettings = preload("res://data/skins/ps1_skin.tres")
## Everything under this node gets the look (empty = the parent, the map).
@export var root: Node

var active: bool = false
## Geometry -> [material_override, surface override materials] before the look.
var _originals: Dictionary = {}


func _ready() -> void:
	add_to_group(&"ps1_world_look")
	settings = PS1Tuning.settings()
	if root == null:
		root = get_parent()
	get_tree().node_added.connect(_on_node_added)
	set_active(PS1Tuning.environment_on())


## Puts the look on (every mesh now and later) or takes it off (the original materials come back).
func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if active:
		_apply_tree(root)
		PS1Skin.refresh_all(root, settings)
		return
	for geometry: GeometryInstance3D in _originals:
		if not is_instance_valid(geometry):
			continue
		var before: Array = _originals[geometry]
		geometry.material_override = before[0]
		if geometry is MeshInstance3D:
			var surfaces: Array = before[1]
			for surface in surfaces.size():
				(geometry as MeshInstance3D).set_surface_override_material(surface, surfaces[surface])
	_originals.clear()


func _on_node_added(node: Node) -> void:
	if active and node is GeometryInstance3D:
		_apply_deferred.call_deferred(node)


func _apply_deferred(node: Node) -> void:
	if active and is_instance_valid(node) and node.is_inside_tree():
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
	if geometry is CPUParticles3D or geometry is GPUParticles3D or _in_mech(geometry) \
			or _originals.has(geometry):
		return
	_remember(geometry)
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


func _remember(geometry: GeometryInstance3D) -> void:
	var surfaces: Array = []
	if geometry is MeshInstance3D:
		var mesh := geometry as MeshInstance3D
		for surface in mesh.get_surface_override_material_count():
			surfaces.append(mesh.get_surface_override_material(surface))
	_originals[geometry] = [geometry.material_override, surfaces]


func _in_mech(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is Mech:
			return true
		parent = parent.get_parent()
	return false
