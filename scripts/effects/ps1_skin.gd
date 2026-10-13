class_name PS1Skin
extends RefCounted
## Makes PS1 skin materials (shaders/ps1_skin.gdshader) from a mesh's own materials, so any mech,
## weapon or equipment keeps its colors and gets the PS1 effects. Effect surfaces (glowing,
## see-through, unshaded or added: muzzle flashes, beams, flames) keep their own materials.

const SHADER := preload("res://shaders/ps1_skin.gdshader")
const ARMOR_TEXTURE := preload("res://assets/textures/ps1/metal_panels.png")
const JOINT_TEXTURE := preload("res://assets/textures/ps1/joint_metal.png")


## Puts the skin on every surface of a mesh that has a plain material. Returns the new materials
## (empty when nothing was skinned). index shifts the detail texture, so parts differ.
static func apply(mesh: MeshInstance3D, settings: PS1SkinSettings, joint: bool, index: int) -> Array[ShaderMaterial]:
	var made: Array[ShaderMaterial] = []
	if mesh.mesh == null:
		return made
	var originals: Array[Material] = []
	for surface in mesh.mesh.get_surface_count():
		originals.append(mesh.get_active_material(surface))
	for surface in originals.size():
		var material := make(originals[surface], settings, joint, index)
		if material == null:
			continue
		mesh.set_surface_override_material(surface, material)
		made.append(material)
	# A surface that kept its effect material needs it as a surface override now.
	if not made.is_empty() and mesh.material_override != null:
		for surface in originals.size():
			if mesh.get_surface_override_material(surface) == null:
				mesh.set_surface_override_material(surface, originals[surface])
		mesh.material_override = null
	return made


## The skin material for an original material, or null for an effect material (or none).
static func make(original: Material, settings: PS1SkinSettings, joint: bool, index: int) -> ShaderMaterial:
	var color := Color.WHITE
	var texture: Texture2D = null
	var metallic := 0.0
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		if base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or base.emission_enabled \
				or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			return null
		color = base.albedo_color
		texture = base.albedo_texture
		metallic = base.metallic
	elif original is ShaderMaterial and original.get_shader_parameter(&"albedo") is Color:
		# Panel shader materials (shaders/mech_panel.gdshader): base color and grime texture.
		color = original.get_shader_parameter(&"albedo")
		texture = original.get_shader_parameter(&"grime_texture") as Texture2D
		var value: Variant = original.get_shader_parameter(&"metallic")
		metallic = float(value) if value != null else 0.0
	else:
		return null
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"albedo_color", color)
	material.set_shader_parameter(&"use_albedo_texture", texture != null)
	if texture != null:
		material.set_shader_parameter(&"albedo_texture", texture)
		material.set_shader_parameter(&"albedo_smooth", texture)
	material.set_shader_parameter(&"brightness", lerpf(1.0, settings.metal_brightness, clampf(metallic, 0.0, 1.0)))
	var detail: Texture2D = JOINT_TEXTURE if joint else ARMOR_TEXTURE
	material.set_shader_parameter(&"grey_texture", detail)
	material.set_shader_parameter(&"texture_size", float(detail.get_width()))
	material.set_shader_parameter(&"texels_per_meter", settings.texels_per_meter)
	material.set_shader_parameter(&"detail_strength", settings.detail_strength)
	material.set_shader_parameter(&"uv_pixels", settings.uv_pixels)
	material.set_shader_parameter(&"uv_offset", Vector2(0.37 * index, 0.61 * index))
	material.set_shader_parameter(&"color_steps", settings.color_steps)
	material.set_shader_parameter(&"snap_grid", settings.snap_grid)
	# The original metallic value: a settings change sets the brightness again (refresh_all).
	material.set_meta(&"ps1_metallic", metallic)
	return material


## Sets the tuning values on every PS1 material under root: the mech skin and the environment look
## (the PS1 tuning menu, 2026-10-13). Generated (internal) children count too.
static func refresh_all(root: Node, settings: PS1SkinSettings) -> void:
	if root is GeometryInstance3D:
		var geometry := root as GeometryInstance3D
		_refresh_material(geometry.material_override, settings)
		if geometry is MeshInstance3D:
			var mesh := geometry as MeshInstance3D
			for surface in mesh.get_surface_override_material_count():
				_refresh_material(mesh.get_surface_override_material(surface), settings)
	for child in root.get_children(true):
		refresh_all(child, settings)


static func _refresh_material(material: Material, settings: PS1SkinSettings) -> void:
	if material is ShaderMaterial and (material as ShaderMaterial).shader == SHADER:
		var skin := material as ShaderMaterial
		var metallic := float(skin.get_meta(&"ps1_metallic", 0.0))
		skin.set_shader_parameter(&"brightness", lerpf(1.0, settings.metal_brightness, clampf(metallic, 0.0, 1.0)))
		skin.set_shader_parameter(&"texels_per_meter", settings.texels_per_meter)
		skin.set_shader_parameter(&"detail_strength", settings.detail_strength)
		skin.set_shader_parameter(&"uv_pixels", settings.uv_pixels)
		skin.set_shader_parameter(&"color_steps", settings.color_steps)
		skin.set_shader_parameter(&"snap_grid", settings.snap_grid)
	elif PS1World.is_world(material):
		PS1World.refresh(material as ShaderMaterial, settings)
