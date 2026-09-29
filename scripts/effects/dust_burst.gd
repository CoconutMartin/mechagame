class_name DustBurst
extends CPUParticles3D
## A grey cloud of concrete dust when a building chunk breaks. It plays once and then frees itself.

## Box size the dust starts from, in meters (the chunk size).
var box: Vector3 = Vector3(4.0, 4.0, 4.0)


static func create(world: Node, point: Vector3, size: Vector3) -> DustBurst:
	var dust := DustBurst.new()
	dust.box = size
	world.add_child(dust)
	dust.global_position = point
	return dust


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
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 1.5))
	scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.48, 0.45, 0.85))
	ramp.set_color(1, Color(0.46, 0.45, 0.43, 0.0))
	color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = DamageSmoke._puff_texture()
	quad.material = material
	mesh = quad
	emitting = true
	finished.connect(queue_free)
