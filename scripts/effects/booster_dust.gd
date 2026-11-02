class_name BoosterDust
extends CPUParticles3D
## Dust the booster gust kicks up from the ground (user request 2026-11-02: "plus some dust kicked up near the ground").
## While the mech boosts on the ground, thin pale dust rolls backward and up from the ground behind it and fades.
## BackPackOutlets adds one and calls follow each frame.

## Dust puffs per second at full thrust.
@export var rate: float = 14.0
## How long a puff lasts (s).
@export var life: float = 1.1
## Speed of a puff backward (m/s).
@export var speed: float = 6.0
## Puff size at the start and at the end of its life (m).
@export var size_start: float = 0.7
@export var size_end: float = 2.6
## Dust color and opacity at the start (it fades out over its life). Thin, like the foot dust.
@export var dust_color: Color = Color(0.62, 0.6, 0.57, 0.16)
## How far behind the mech origin the dust starts (m).
@export var behind: float = 1.6

static var _quad: QuadMesh


## Adds the dust to a parent node (off until follow).
static func attach(parent: Node) -> BoosterDust:
	var dust := BoosterDust.new()
	dust.name = "BoosterDust"
	parent.add_child(dust)
	return dust


func _ready() -> void:
	emitting = false
	local_coords = false
	amount = maxi(int(ceil(rate * life)) + 2, 4)
	lifetime = life
	randomness = 0.5
	spread = 35.0
	gravity = Vector3(0.0, 0.4, 0.0)
	initial_velocity_min = speed * 0.5
	initial_velocity_max = speed
	damping_min = speed * 0.6
	damping_max = speed
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(0.9, 0.1, 0.5)
	var curve := Curve.new()
	curve.max_value = size_end / maxf(size_start, 0.01)
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, curve.max_value))
	scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, dust_color)
	ramp.set_color(1, Color(dust_color, 0.0))
	color_ramp = ramp
	if _quad == null:
		_quad = QuadMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = DamageSmoke._puff_texture()
		_quad.material = material
	_quad.size = Vector2.ONE * size_start
	mesh = _quad


## Puts the dust on the ground behind the mech and blows it backward. strength: 0 (off) to 1 (full boost on the ground).
func follow(target: Mech, strength: float) -> void:
	var back := target.global_basis.z.normalized()
	global_position = target.global_position + back * behind + Vector3.UP * 0.2
	direction = (back + Vector3.UP * 0.25).normalized()
	emitting = strength > 0.3 and target.is_on_floor()
	speed_scale = 0.6 + 0.6 * strength
