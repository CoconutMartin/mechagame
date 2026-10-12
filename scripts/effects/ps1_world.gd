class_name PS1World
extends RefCounted
## Makes PS1 environment materials (shaders/ps1_world.gdshader) from the original materials: the same
## colors, texture and texture mapping (UV, world or mesh box mapping), with the PS1 effects. One new
## material per original (cached), so meshes that shared a material still share one. Effect materials
## (unshaded, glowing add or other blends) are not changed: null.

const SOLID := preload("res://shaders/ps1_world.gdshader")
const SEE_THROUGH := preload("res://shaders/ps1_world_alpha.gdshader")
const FACADE := preload("res://shaders/building_facade.gdshader")

static var _cache := {}


## The PS1 material for original, or null when it stays as it is.
static func convert(original: Material, settings: PS1SkinSettings) -> Material:
	if original == null:
		return null
	if original is ShaderMaterial:
		var shader := (original as ShaderMaterial).shader
		if shader == SOLID or shader == SEE_THROUGH:
			return null
	var key := original.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var made: ShaderMaterial = null
	if original is BaseMaterial3D:
		made = _from_base(original as BaseMaterial3D, settings)
	elif original is ShaderMaterial and (original as ShaderMaterial).shader == FACADE:
		made = _from_facade(original as ShaderMaterial, settings)
	_cache[key] = made
	return made


static func _from_base(base: BaseMaterial3D, settings: PS1SkinSettings) -> ShaderMaterial:
	if base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
		return null
	var see_through := base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and base.albedo_color.a < 0.99
	var material := _new(SEE_THROUGH if see_through else SOLID, settings)
	material.set_shader_parameter(&"albedo_color", base.albedo_color)
	var texture := base.albedo_texture
	material.set_shader_parameter(&"use_albedo_texture", texture != null)
	if texture != null:
		material.set_shader_parameter(&"albedo_texture", texture)
	material.set_shader_parameter(&"uv_scale", base.uv1_scale)
	material.set_shader_parameter(&"uv_offset", base.uv1_offset)
	var mode := 0
	var repeat_m := 0.0
	if base.uv1_triplanar:
		mode = 1 if base.uv1_world_triplanar else 2
		repeat_m = 1.0 / maxf(base.uv1_scale.x, 0.0001)
	material.set_shader_parameter(&"map_mode", mode)
	# World-mapped textures: chunky pixels by size in meters; UV textures: across the texture.
	var pixels := settings.world_pixels_per_meter * repeat_m if mode != 0 else settings.uv_pixels
	material.set_shader_parameter(&"pixels_per_repeat", maxf(pixels, 1.0))
	if base.emission_enabled:
		var glow := base.emission * base.emission_energy_multiplier
		material.set_shader_parameter(&"emission", Vector3(glow.r, glow.g, glow.b))
	return material


## Rubble's building facade material: its tint on the concrete texture (world box mapping).
static func _from_facade(facade: ShaderMaterial, settings: PS1SkinSettings) -> ShaderMaterial:
	var material := _new(SOLID, settings)
	var tint: Color = facade.get_shader_parameter(&"tint")
	var mean: Variant = facade.get_shader_parameter(&"texture_mean")
	var size: Variant = facade.get_shader_parameter(&"texture_size")
	var scale := 1.0 / (float(mean) if mean != null else 0.36)
	material.set_shader_parameter(&"albedo_color", Color(tint.r * scale, tint.g * scale, tint.b * scale))
	material.set_shader_parameter(&"albedo_texture", facade.get_shader_parameter(&"concrete_albedo"))
	material.set_shader_parameter(&"use_albedo_texture", true)
	var repeat_m := float(size) if size != null else 4.0
	material.set_shader_parameter(&"map_mode", 1)
	material.set_shader_parameter(&"uv_scale", Vector3.ONE / repeat_m)
	material.set_shader_parameter(&"pixels_per_repeat", settings.world_pixels_per_meter * repeat_m)
	return material


static func _new(shader: Shader, settings: PS1SkinSettings) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"color_steps", settings.color_steps)
	material.set_shader_parameter(&"snap_grid", settings.snap_grid)
	return material
