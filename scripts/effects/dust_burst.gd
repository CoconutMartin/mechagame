class_name DustBurst
extends CPUParticles3D
## A grey cloud of concrete dust when a building chunk breaks. It plays once and then frees itself.

## Box size the dust starts from, in meters (the chunk size).
var box: Vector3 = Vector3(4.0, 4.0, 4.0)
## Dust opacity: 1 = solid, 0 = clear (PixelSmoke.set_opacity).
var opacity: float = 1.0

## Most new bursts in one physics frame (phase 5a, 2026-10-19: 45 chunks breaking at once made 45
## bursts, each with its own mesh, material, curve and ramp). More in the same frame are skipped.
static var max_per_frame: int = 12
static var _frame: int = -1
static var _made: int = 0
## Shared by every burst.
static var _curve: Curve
static var _ramp: Gradient
static var _quad: QuadMesh


static func create(world: Node, point: Vector3, size: Vector3, alpha: float = 1.0) -> DustBurst:
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_made = 0
	if _made >= max_per_frame:
		return null
	_made += 1
	var dust := DustBurst.new()
	dust.box = size
	dust.opacity = alpha
	world.add_child(dust)
	dust.global_position = point
	return dust


static func _shared_look() -> void:
	if _quad != null:
		return
	_curve = Curve.new()
	_curve.add_point(Vector2(0.0, 0.4))
	_curve.add_point(Vector2(0.3, 1.0))
	_curve.add_point(Vector2(1.0, 1.5))
	_ramp = Gradient.new()
	_ramp.set_color(0, Color(0.5, 0.48, 0.45, 0.85))
	_ramp.set_color(1, Color(0.46, 0.45, 0.43, 0.0))
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = DamageSmoke._puff_texture()
	_quad.material = material


func _ready() -> void:
	name = "DustBurst"
	one_shot = true
	explosiveness = 0.85
	amount = 28
	lifetime = 3.0
	local_coords = false
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = box * 0.5
	direction = Vector3.UP
	spread = 80.0
	gravity = Vector3(0.0, -0.6, 0.0)
	initial_velocity_min = 1.5
	initial_velocity_max = 5.0
	damping_min = 1.5
	damping_max = 3.0
	var size := maxf(box.x, box.z)
	scale_amount_min = size * 0.45
	scale_amount_max = size * 0.9
	_shared_look()
	scale_amount_curve = _curve
	color_ramp = _ramp
	mesh = _quad
	# Before register (it reads the opacity), so the look is built once.
	set_meta(&"opacity", clampf(snappedf(opacity, PixelSmoke.OPACITY_STEP), 0.0, 1.0))
	PixelSmoke.register(self)
	# create() places the burst after add_child: start at the end of the frame, at that place (a
	# burst started here came out at the world origin, the ImpactSpark bug of 2026-10-15).
	set_deferred(&"emitting", true)
	finished.connect(queue_free)
