class_name PartLook
extends RefCounted
## Gives part variants their look (Phase 5): each model piece is scaled in place by the part's
## model_scale (its place moves out a little too), and the armor materials get the part's
## armor_tint. Frame and joint materials keep their colors, so a broken leg still shows the frame.
## Pieces that other scripts move or scale every frame (pauldron and foot pivots, flames, lights) are not
## scaled themselves; the pieces inside a pauldron pivot are.

## How much of the scale moves the piece away from its socket (0 = stays, 1 = full scale).
const SPREAD := 0.6
const SKIP_GROUPS := [&"booster_flame", &"brake_flame", &"booster_light"]

static var _tinted := {}


static func apply(nodes: Array[Node3D], scale: Vector3, tint: Color) -> void:
	for node in nodes:
		_scale_node(node, scale)
		if tint != Color.WHITE:
			_tint(node, tint)


static func _scale_node(node: Node3D, scale: Vector3) -> void:
	if scale == Vector3.ONE or _skipped(node):
		return
	if node.is_in_group(&"pauldron_l") or node.is_in_group(&"pauldron_r") \
			or node.is_in_group(&"foot_pivot_l") or node.is_in_group(&"foot_pivot_r"):
		for child in node.get_children():
			if child is Node3D:
				_scale_node(child, scale)
		return
	var spread := Vector3.ONE + (scale - Vector3.ONE) * SPREAD
	node.transform = Transform3D(Basis.from_scale(scale) * node.basis, node.position * spread)


static func _skipped(node: Node) -> bool:
	for group in SKIP_GROUPS:
		if node.is_in_group(group):
			return true
	return node is Light3D


## Armor meshes (not frame or joint) get a tinted copy of their material.
static func _tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var material := mesh.get_active_material(0)
		if material != null and material.resource_path.get_file().begins_with("armor"):
			mesh.material_override = _tinted_material(material, tint)
	for child in node.get_children():
		_tint(child, tint)


static func _tinted_material(material: Material, tint: Color) -> Material:
	var key := [material.resource_path, tint]
	if not _tinted.has(key):
		var copy := material.duplicate() as Material
		if copy is StandardMaterial3D:
			(copy as StandardMaterial3D).albedo_color = (material as StandardMaterial3D).albedo_color * tint
		elif copy is ShaderMaterial:
			# The mech panel shader (Phase 8).
			var shader_copy := copy as ShaderMaterial
			shader_copy.set_shader_parameter("albedo", (material as ShaderMaterial).get_shader_parameter("albedo") * tint)
		_tinted[key] = copy
	return _tinted[key]
