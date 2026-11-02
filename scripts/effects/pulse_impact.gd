class_name PulseImpact
extends Node3D
## The hit of an electric pulse pellet (Shotgun 2 and 3; user request 2026-11-02). Placed like ImpactSpark (its -Z
## along the surface normal): a blue flash, a short crackling orb, lightning forks that crawl out over the surface and
## fade, and blue sparks.

const ORB_SHADER := preload("res://shaders/pulse_pellet.gdshader")

## Fork count and length (m).
@export var fork_count: int = 6
@export var fork_length: float = 3.5
## Seconds the forks and the orb last.
@export var life: float = 0.3
## Flash light.
@export var light_color: Color = Color(0.4, 0.75, 1.0)
@export var light_energy: float = 5.0
@export var light_range: float = 9.0
## Orb size at the hit (m), and its smallest size seen from the camera (degrees across).
@export var orb_size: float = 2.2
@export var orb_min_deg: float = 2.4
## Spark count.
@export var spark_count: int = 14

var _arcs: ElectricArcs
var _light: OmniLight3D
var _orb: MeshInstance3D
var _forks: Array[Vector3] = []
var _age: float = 0.0


func _ready() -> void:
	_arcs = ElectricArcs.new()
	add_child(_arcs)
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	add_child(_light)
	_light.position = Vector3(0, 0, -0.4)
	_orb = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_orb.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = ORB_SHADER
	_orb.material_override = material
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.custom_aabb = AABB(Vector3.ONE * -4.0, Vector3.ONE * 8.0)
	_orb.set_instance_shader_parameter(&"seed", randf() * 100.0)
	add_child(_orb)
	_orb.position = Vector3(0, 0, -0.2)
	_add_sparks()


func _add_sparks() -> void:
	var sparks := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 4
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(0.45, 0.8, 1.0)
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	sparks.mesh = mesh
	sparks.amount = spark_count
	sparks.lifetime = 0.4
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3(0, 0, -1)
	sparks.spread = 75.0
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 15.0
	sparks.gravity = Vector3(0, -9, 0)
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(0.2, 0.5, 1.0, 0))
	sparks.color_ramp = fade
	add_child(sparks)
	sparks.emitting = true


## The forks are set on the first frame: the bullet turns the impact to the surface after it enters the tree.
func _make_forks() -> void:
	var normal := -global_basis.z
	for i in fork_count:
		# Mostly along the surface, a little out from it.
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		dir = (dir - normal * dir.dot(normal)).normalized() + normal * randf_range(0.05, 0.5)
		_forks.append(dir.normalized() * fork_length * randf_range(0.5, 1.0))


func _process(delta: float) -> void:
	if _forks.is_empty():
		_make_forks()
	_age += delta
	var left := clampf(1.0 - _age / life, 0.0, 1.0)
	_light.light_energy = light_energy * left * left
	var per_deg := ElectricArcs.view_position(self).distance_to(global_position) * tan(deg_to_rad(1.0))
	var orb := maxf(orb_size, per_deg * orb_min_deg)
	_orb.set_instance_shader_parameter(&"size", orb * (0.6 + 0.6 * (1.0 - left)))
	_orb.set_instance_shader_parameter(&"fade", left)
	_arcs.clear_arcs()
	if left > 0.0:
		var here := global_position
		var view := ElectricArcs.view_position(self)
		var width := maxf(0.06, view.distance_to(here) * tan(deg_to_rad(0.16)))
		# The forks crawl out over the first part of the life, then fade; some drop out each frame (flicker).
		var reach := clampf(_age / (life * 0.4), 0.3, 1.0)
		for fork in _forks:
			if randf() < 0.25:
				continue
			var tip := here + fork * reach * randf_range(0.85, 1.0)
			_arcs.add_bolt(here, tip, width, fork.length() * 0.15, 6, Color(1, 1, 1, left), 0.25, 1.0, 0.1)
	_arcs.commit()
	if _age > 0.6:
		queue_free()
