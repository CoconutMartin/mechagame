class_name MeshColorOverride
extends Node
## Gives some of a model's meshes a new base color and texture (user requests 2026-10-15: the ball
## joints of the SGG-101 are dark, then textured like the joint connectors). It copies each mesh's
## own material and changes only its color, texture, metallic and roughness, so the skin
## (PS1SkinLook, which reads the active material) keeps them. Put it before PS1SkinLook in the scene.

## The model that holds the meshes.
@export var model: Node3D
## Names of the meshes to color.
@export var mesh_names: PackedStringArray = []
## The new color. With a texture it multiplies the texture.
@export var color: Color = Color(0.035, 0.037, 0.04)
## Optional texture (on the mesh's own UVs). Empty: plain color.
@export var texture: Texture2D
## Metal look of the new material (0 = paint, 1 = bare metal).
@export_range(0.0, 1.0) var metallic: float = 0.6
## Surface roughness of the new material (0 = mirror, 1 = matte).
@export_range(0.0, 1.0) var roughness: float = 0.4


func _ready() -> void:
	if model == null:
		return
	for mesh_name in mesh_names:
		var mesh := model.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			push_warning("MeshColorOverride: no mesh named " + mesh_name)
			continue
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as BaseMaterial3D
			var material: BaseMaterial3D = original.duplicate() if original != null else StandardMaterial3D.new()
			material.albedo_color = color
			material.albedo_texture = texture
			material.metallic = metallic
			material.roughness = roughness
			mesh.set_surface_override_material(surface, material)
