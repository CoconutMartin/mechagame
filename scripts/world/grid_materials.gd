class_name GridMaterials
extends RefCounted
## Shared building materials by tint, for the many building blocks and rubble pieces (Phase 4c).
## Since Phase 8 they use the building facade shader (concrete, floor slabs, windows); rubble has
## no windows. Concrete: CC0 textures from Poly Haven (materials/textures/cc0). One material per tint (rounded to 1/32 steps) and window choice instead of a
## per-object tint value: the per-object shader values have a small limit on some graphics cards.

const SHADER := preload("res://shaders/building_facade.gdshader")
const CONCRETE_ALBEDO := preload("res://materials/textures/cc0/concrete_albedo.jpg")
const CONCRETE_NORMAL := preload("res://materials/textures/cc0/concrete_normal.jpg")
const CONCRETE_ROUGH := preload("res://materials/textures/cc0/concrete_rough.jpg")

static var _cache := {}


static func get_material(tint: Color, windows: bool = true) -> ShaderMaterial:
	var color := Color(snappedf(tint.r, 1.0 / 32.0), snappedf(tint.g, 1.0 / 32.0), snappedf(tint.b, 1.0 / 32.0))
	var key := [color, windows]
	if not _cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("tint", color)
		material.set_shader_parameter("windows", 1.0 if windows else 0.0)
		material.set_shader_parameter("concrete_albedo", CONCRETE_ALBEDO)
		material.set_shader_parameter("concrete_normal", CONCRETE_NORMAL)
		material.set_shader_parameter("concrete_rough", CONCRETE_ROUGH)
		_cache[key] = material
	return _cache[key]
