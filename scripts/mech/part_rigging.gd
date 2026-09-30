class_name PartRigging
extends RefCounted
## Gives the nodes of an imported part model (a .glb from Blender) their game roles by name, after
## MechAssembler attached them. Blender files cannot carry Godot groups, so names decide:
##   PauldronPivotL / R    -> groups pauldron_l / pauldron_r (PauldronFollow turns them)
##   FootPivotL / R        -> groups foot_pivot_l / foot_pivot_r (FootLeveler turns them)
##   FootL / FootR         -> group foot (SkidDust)
##   BoosterFlame...       -> group booster_flame; an empty one gets flame meshes (points down -Y)
##   BrakeFlame...         -> group brake_flame; an empty one gets small flame meshes
##   a Torso node with booster flames and no BoosterLight gets a BoosterLight (group booster_light)
## Materials: a material whose name matches a file in the material library (for example "armor"
## -> materials/warden/armor.tres) is replaced by that file, so the game look, tints and damage
## rules apply. Other materials stay as they came from Blender.
## Models made by the project generator already have their groups; this changes nothing there.

const FLAME := preload("res://materials/effects/booster_flame.tres")
const FLAME_CORE := preload("res://materials/effects/booster_core.tres")

const GROUPS := {
	"PauldronPivotL": &"pauldron_l", "PauldronPivotR": &"pauldron_r",
	"FootPivotL": &"foot_pivot_l", "FootPivotR": &"foot_pivot_r",
	"FootL": &"foot", "FootR": &"foot",
}


## nodes: the nodes the part added. library: folder of material files ("" = keep the materials).
static func rig(nodes: Array[Node3D], library: String) -> void:
	for node in nodes:
		_rig_tree(node, library)


static func _rig_tree(node: Node, library: String) -> void:
	# Blender adds ".001" to a repeated name (Godot shows "_001"): "FootL_001" counts as FootL.
	var node_name := _base_name(String(node.name))
	if GROUPS.has(node_name):
		node.add_to_group(GROUPS[node_name])
	if node_name.begins_with("BoosterFlame") and node is Node3D:
		node.add_to_group(&"booster_flame")
		_add_flame(node as Node3D, 3.0, 0.45)
		_add_light(node.get_parent() as Node3D)
	elif node_name.begins_with("BrakeFlame") and node is Node3D:
		node.add_to_group(&"brake_flame")
		_add_flame(node as Node3D, 2.2, 0.24)
	if node is MeshInstance3D and not library.is_empty():
		_use_library(node as MeshInstance3D, library)
	for child in node.get_children():
		_rig_tree(child, library)


static func _base_name(node_name: String) -> String:
	var regex := RegEx.create_from_string("[._]\\d{3}$")
	return regex.sub(node_name, "")


## Flame meshes like the generator makes: an outer cone and a bright core, pointing down -Y.
static func _add_flame(flame: Node3D, length: float, radius: float) -> void:
	if flame.get_child_count() > 0:
		return
	for part in [["Outer", radius, 0.04, length, FLAME, -length * 0.5], ["Core", radius * 0.55, 0.02, length * 0.6, FLAME_CORE, -length * 0.3]]:
		var mesh := MeshInstance3D.new()
		mesh.name = part[0]
		var cone := CylinderMesh.new()
		cone.top_radius = part[1]
		cone.bottom_radius = part[2]
		cone.height = part[3]
		mesh.mesh = cone
		mesh.material_override = part[4]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = Vector3(0.0, part[5], 0.0)
		flame.add_child(mesh)


static func _add_light(holder: Node3D) -> void:
	if holder == null or holder.get_node_or_null(^"BoosterLight") != null:
		return
	var light := OmniLight3D.new()
	light.name = "BoosterLight"
	light.visible = false
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 14.0
	light.position = Vector3(0.0, -0.34, 2.55)
	light.add_to_group(&"booster_light")
	holder.add_child(light)


## Replaces each surface material that has a library file with the same name.
static func _use_library(mesh: MeshInstance3D, library: String) -> void:
	if mesh.mesh == null:
		return
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material == null or PartLook.has_own_file(material):
			continue
		# Blender adds ".001" to copies of a material name: "armor.001" uses armor.tres too.
		var path := library.path_join(material.resource_name.get_slice(".", 0) + ".tres")
		if ResourceLoader.exists(path):
			mesh.set_surface_override_material(surface, load(path))
