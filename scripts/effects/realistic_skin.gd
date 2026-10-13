class_name RealisticSkin
extends RefCounted
## Makes realistic skin materials (shaders/mech_realistic.gdshader) from a mesh's own materials: the
## model's colors as painted metal with a worn paint texture, normal map and roughness map.
## Effect surfaces (glowing, see-through, unshaded or added) keep their own materials, as in PS1Skin.

const SHADER := preload("res://shaders/mech_realistic.gdshader")
const DETAIL_ALBEDO := preload("res://assets/textures/painted_metal/painted_metal_albedo.jpg")
const DETAIL_NORMAL := preload("res://assets/textures/painted_metal/painted_metal_normal.jpg")
const DETAIL_ROUGHNESS := preload("res://assets/textures/painted_metal/painted_metal_rough.jpg")

## Paint on armor, bare metal on joints.
const ARMOR_METALLIC := 0.25
const ARMOR_ROUGHNESS := 0.55
const JOINT_METALLIC := 0.75
const JOINT_ROUGHNESS := 0.4


## Puts the skin on every surface of a mesh that has a plain material. Returns the new materials.
## body: a body part (gets road dirt low down). index shifts the textures, so parts differ.
static func apply(mesh: MeshInstance3D, joint: bool, body: bool, index: int) -> Array[ShaderMaterial]:
	var made: Array[ShaderMaterial] = []
	if mesh.mesh == null:
		return made
	var originals: Array[Material] = []
	for surface in mesh.mesh.get_surface_count():
		originals.append(mesh.get_active_material(surface))
	for surface in originals.size():
		var material := make(originals[surface], joint, body, index)
		if material == null:
			continue
		mesh.set_surface_override_material(surface, material)
		made.append(material)
	if not made.is_empty() and mesh.material_override != null:
		for surface in originals.size():
			if mesh.get_surface_override_material(surface) == null:
				mesh.set_surface_override_material(surface, originals[surface])
		mesh.material_override = null
	return made


## The skin material for an original material, or null for an effect material (or none).
static func make(original: Material, joint: bool, body: bool, index: int) -> ShaderMaterial:
	var color := Color.WHITE
	var texture: Texture2D = null
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		if base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or base.emission_enabled \
				or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			return null
		color = base.albedo_color
		texture = base.albedo_texture
	elif original is ShaderMaterial and original.get_shader_parameter(&"albedo") is Color:
		color = original.get_shader_parameter(&"albedo")
	else:
		return null
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"albedo_color", color)
	material.set_shader_parameter(&"use_albedo_texture", texture != null)
	if texture != null:
		material.set_shader_parameter(&"albedo_texture", texture)
	material.set_shader_parameter(&"metallic", JOINT_METALLIC if joint else ARMOR_METALLIC)
	material.set_shader_parameter(&"roughness", JOINT_ROUGHNESS if joint else ARMOR_ROUGHNESS)
	material.set_shader_parameter(&"detail_albedo", DETAIL_ALBEDO)
	material.set_shader_parameter(&"detail_normal", DETAIL_NORMAL)
	material.set_shader_parameter(&"detail_roughness", DETAIL_ROUGHNESS)
	material.set_shader_parameter(&"height_dirt", 1.0 if body else 0.0)
	material.set_shader_parameter(&"uv_offset", Vector3(0.37, 0.61, 0.23) * index)
	return material
