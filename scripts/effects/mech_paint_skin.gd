class_name MechPaintSkin
extends RefCounted
## Makes paint skin materials (shaders/mech_paint.gdshader) from a body mesh's own materials and a MechPaint.
## Effect surfaces (glowing, see-through, unshaded or added) keep their own materials, as in RealisticSkin.

const SHADER := preload("res://shaders/mech_paint.gdshader")
## The paint the "Paint" skin uses.
const DEFAULT_PAINT := preload("res://data/skins/paint_black_red.tres")


## Puts the paint on every plain surface of a mesh. Returns the new materials.
static func apply(mesh: MeshInstance3D, paint: MechPaint) -> Array[ShaderMaterial]:
	var made: Array[ShaderMaterial] = []
	if mesh.mesh == null:
		return made
	var originals: Array[Material] = []
	for surface in mesh.mesh.get_surface_count():
		originals.append(mesh.get_active_material(surface))
	for surface in originals.size():
		var material := make(originals[surface], paint)
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


## The paint material for an original material, or null for an effect material.
static func make(original: Material, paint: MechPaint) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		if base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or base.emission_enabled \
				or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			return null
		material.set_shader_parameter(&"albedo_color", base.albedo_color)
		if base.albedo_texture != null:
			material.set_shader_parameter(&"albedo_texture", base.albedo_texture)
		if base.normal_enabled and base.normal_texture != null:
			material.set_shader_parameter(&"has_normal", true)
			material.set_shader_parameter(&"normal_texture", base.normal_texture)
			material.set_shader_parameter(&"normal_scale", base.normal_scale)
	elif original != null:
		return null
	if original == null or (original as BaseMaterial3D).albedo_texture == null:
		# No texture: a white one, so the color alone decides.
		material.set_shader_parameter(&"albedo_texture", _white())
	for key: StringName in [&"armor_color", &"accent_color", &"frame_color", &"lamp_color", &"lamp_glow",
			&"metallic", &"roughness", &"detail", &"paint_saturation", &"accent_split", &"grey_armor_split"]:
		material.set_shader_parameter(key, paint.get(key))
	return material


static var _white_texture: ImageTexture


static func _white() -> ImageTexture:
	if _white_texture == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(image)
	return _white_texture
