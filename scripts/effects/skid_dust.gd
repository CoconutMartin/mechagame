class_name SkidDust
extends Node
## Placeholder dust from the feet while the mech skids to a stop after a boost.
## Makes one CPUParticles3D per foot at start. Phase 8 replaces it with real effects.

@export var mech: Mech
@export var feet: Array[Node3D] = []
## Dust puffs per second from each foot.
@export var amount: int = 40
@export var dust_color: Color = Color(0.55, 0.52, 0.47, 0.55)

var _emitters: Array[CPUParticles3D] = []


func _ready() -> void:
	for foot in feet:
		var emitter := _make_emitter()
		foot.add_child(emitter)
		_emitters.append(emitter)


func _physics_process(_delta: float) -> void:
	for emitter in _emitters:
		emitter.emitting = mech.is_skidding


func _make_emitter() -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.amount = amount
	emitter.lifetime = 1.2
	emitter.local_coords = false
	emitter.position = Vector3(0.0, -0.2, 0.0)
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 0.8
	emitter.direction = Vector3(0.0, 1.0, 0.0)
	emitter.spread = 70.0
	emitter.initial_velocity_min = 1.0
	emitter.initial_velocity_max = 3.0
	emitter.gravity = Vector3(0.0, -1.0, 0.0)
	emitter.damping_min = 1.0
	emitter.damping_max = 2.0
	emitter.scale_amount_min = 1.0
	emitter.scale_amount_max = 2.2
	var fade := Gradient.new()
	fade.set_color(0, dust_color)
	fade.set_color(1, Color(dust_color, 0.0))
	emitter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	emitter.mesh = quad
	return emitter
