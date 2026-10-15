class_name PixelSmoke
extends RefCounted
## PS1-style smoke and dust (user request 2026-10-13): solid puffs with hard pixel edges (a 16 x 16
## texture, nearest filter, 3 shades, alpha scissor), no see-through blending, so they do not flicker
## with TAA or cut the mech with jumping edges. A puff keeps its color and shrinks to nothing at
## the end of its life (it does not fade). Each emitter keeps its soft look as metadata, so the garage
## toggle (SmokeChoice) switches emitters that already exist too.
## Opacity (user request 2026-10-15): an emitter's "opacity" metadata (0 to 1, default 1; set_opacity)
## makes its puffs see-through. Below 1 the pixel puffs blend at that opacity (the edges stay hard,
## the puff texture alpha is 0 or 1).

const GROUP := &"smoke_particles"
const PUFF_PIXELS := 16
## Opacity changes smaller than this are not applied (each change builds the look again).
const OPACITY_STEP := 0.05

static var _puff: ImageTexture


## Call once when the emitter has its soft look. It gets the look the player picked.
static func register(particles: CPUParticles3D) -> void:
	particles.add_to_group(GROUP)
	particles.set_meta(&"soft_mesh", particles.mesh)
	particles.set_meta(&"soft_ramp", particles.color_ramp)
	particles.set_meta(&"soft_curve", particles.scale_amount_curve)
	apply(particles, SmokeChoice.pixel_on())


static func apply_all(tree: SceneTree, on: bool) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		apply(node as CPUParticles3D, on)


## Sets an emitter's opacity (0 = clear, 1 = solid, in OPACITY_STEP steps) and applies its look again.
static func set_opacity(particles: CPUParticles3D, opacity: float) -> void:
	opacity = clampf(snappedf(opacity, OPACITY_STEP), 0.0, 1.0)
	if is_equal_approx(float(particles.get_meta(&"opacity", 1.0)), opacity):
		return
	particles.set_meta(&"opacity", opacity)
	if particles.has_meta(&"soft_mesh"):
		apply(particles, SmokeChoice.pixel_on())


static func apply(particles: CPUParticles3D, on: bool) -> void:
	var soft_mesh := particles.get_meta(&"soft_mesh") as Mesh
	var soft_ramp := particles.get_meta(&"soft_ramp") as Gradient
	var soft_curve := particles.get_meta(&"soft_curve") as Curve
	var opacity := float(particles.get_meta(&"opacity", 1.0))
	if not on:
		particles.mesh = soft_mesh
		particles.color_ramp = _faded_ramp(soft_ramp, opacity)
		particles.scale_amount_curve = soft_curve
		return
	particles.mesh = _pixel_mesh(soft_mesh, opacity < 1.0)
	particles.color_ramp = _solid_ramp(soft_ramp, opacity)
	particles.scale_amount_curve = _shrink_curve(soft_curve)


static func _pixel_mesh(soft: Mesh, see_through: bool = false) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = (soft as QuadMesh).size if soft is QuadMesh else Vector2.ONE
	var material := StandardMaterial3D.new()
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = puff_texture()
	quad.material = material
	return quad


## The soft ramp's colors at one alpha for the whole life (solid at 1: the scissor cuts at half
## alpha, so a fade would pop).
static func _solid_ramp(soft: Gradient, opacity: float = 1.0) -> Gradient:
	var ramp := Gradient.new()
	if soft == null:
		return ramp
	ramp.offsets = soft.offsets
	var colors := soft.colors
	for i in colors.size():
		colors[i].a = opacity
	ramp.colors = colors
	return ramp


## The soft ramp with its alpha times opacity.
static func _faded_ramp(soft: Gradient, opacity: float) -> Gradient:
	if soft == null or opacity >= 1.0:
		return soft
	var ramp := Gradient.new()
	ramp.offsets = soft.offsets
	var colors := soft.colors
	for i in colors.size():
		colors[i].a *= opacity
	ramp.colors = colors
	return ramp


## The soft size curve, then down to nothing at the end of the life.
static func _shrink_curve(soft: Curve) -> Curve:
	var curve := Curve.new()
	curve.max_value = maxf(soft.max_value if soft != null else 1.0, 1.0)
	for t in [0.0, 0.3, 0.6]:
		curve.add_point(Vector2(t, soft.sample(t) if soft != null else 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	return curve


## A lumpy round puff, 16 x 16 pixels: light middle, two darker rings, clear outside.
static func puff_texture() -> ImageTexture:
	if _puff != null:
		return _puff
	var image := Image.create(PUFF_PIXELS, PUFF_PIXELS, false, Image.FORMAT_RGBA8)
	var center := Vector2(PUFF_PIXELS, PUFF_PIXELS) * 0.5
	for y in PUFF_PIXELS:
		for x in PUFF_PIXELS:
			var offset := Vector2(x + 0.5, y + 0.5) - center
			var angle := offset.angle()
			var edge := 6.4 + 0.9 * sin(3.0 * angle) + 0.6 * sin(5.0 * angle + 1.3)
			var r := offset.length() / edge
			if r > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var shade := 1.0 if r < 0.45 else (0.82 if r < 0.78 else 0.66)
				image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	_puff = ImageTexture.create_from_image(image)
	return _puff
