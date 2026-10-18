class_name DamageSmoke
extends CPUParticles3D
## Dark smoke with a few sparks from a damaged or broken part. Add it as a child of the part.

## Smoke size and amount. Heavy = a broken part.
var heavy: bool = false

## The soft look (quad, material, puff texture, size curve, color ramp) is made once per game and shared
## by all smokes (lag spike fix 2026-10-18: no new material or texture per smoke).
static var _soft_quad: QuadMesh
static var _soft_curve: Curve
static var _soft_ramp: Gradient
static var _puff: GradientTexture2D


## How see-through the puffs are: 0 = clear, 1 = solid (PixelSmoke.set_opacity).
func set_opacity(value: float) -> void:
	PixelSmoke.set_opacity(self, value)


static func create(parent: Node3D, offset: Vector3 = Vector3.ZERO, is_heavy: bool = false,
		opacity: float = 1.0) -> DamageSmoke:
	var smoke := DamageSmoke.new()
	smoke.heavy = is_heavy
	# Before _ready (PixelSmoke.register reads it), so the look is built once.
	smoke.set_meta(&"opacity", clampf(snappedf(opacity, PixelSmoke.OPACITY_STEP), 0.0, 1.0))
	smoke.position = offset
	parent.add_child(smoke)
	return smoke


func _ready() -> void:
	name = "DamageSmoke"
	amount = 40 if heavy else 18
	lifetime = 2.2
	local_coords = false
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.6 if heavy else 0.3
	direction = Vector3.UP
	spread = 25.0
	gravity = Vector3(0.0, 1.5, 0.0)
	initial_velocity_min = 1.0
	initial_velocity_max = 3.0
	scale_amount_min = 1.2 if heavy else 0.7
	scale_amount_max = 2.6 if heavy else 1.4
	scale_amount_curve = _shared_curve()
	color_ramp = _shared_ramp()
	mesh = _shared_quad()
	PixelSmoke.register(self)
	emitting = true


static func _shared_curve() -> Curve:
	if _soft_curve == null:
		_soft_curve = Curve.new()
		_soft_curve.add_point(Vector2(0.0, 0.3))
		_soft_curve.add_point(Vector2(0.4, 1.0))
		_soft_curve.add_point(Vector2(1.0, 1.4))
	return _soft_curve


static func _shared_ramp() -> Gradient:
	if _soft_ramp == null:
		_soft_ramp = Gradient.new()
		_soft_ramp.set_color(0, Color(0.25, 0.23, 0.22, 0.8))
		_soft_ramp.set_color(1, Color(0.15, 0.15, 0.15, 0.0))
	return _soft_ramp


static func _shared_quad() -> QuadMesh:
	if _soft_quad == null:
		_soft_quad = QuadMesh.new()
		_soft_quad.size = Vector2.ONE
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = _puff_texture()
		_soft_quad.material = material
	return _soft_quad


## A soft round puff: white in the middle, clear at the edge (one texture per game, shared).
static func _puff_texture() -> GradientTexture2D:
	if _puff != null:
		return _puff
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_puff = texture
	return texture
