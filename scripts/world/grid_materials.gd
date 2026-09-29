class_name GridMaterials
extends RefCounted
## Shared grid materials by tint, for the many building blocks and rubble pieces (Phase 4c).
## One material per tint (rounded to 1/32 steps) instead of a per-object tint value: the
## per-object shader values have a small limit on some graphics cards.

const SHADER := preload("res://shaders/greybox_grid_tinted.gdshader")

static var _cache := {}


static func get_material(tint: Color) -> ShaderMaterial:
	var key := Color(snappedf(tint.r, 1.0 / 32.0), snappedf(tint.g, 1.0 / 32.0), snappedf(tint.b, 1.0 / 32.0))
	if not _cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("tint", key)
		_cache[key] = material
	return _cache[key]
