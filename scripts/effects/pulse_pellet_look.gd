class_name PulsePelletLook
extends Node3D
## The look of one electric pulse pellet (Shotgun 2 and 3; user request 2026-11-02: "more electric looking, more
## believable, more character"). A child of the pellet (Bullet). A crackling orb (shaders/pulse_pellet.gdshader) that
## keeps a readable size on screen, a jagged lightning trail behind it that grows out of the muzzle, and short sparks
## that spit off to the side now and then.

const ORB_SHADER := preload("res://shaders/pulse_pellet.gdshader")

static var _orb_material: ShaderMaterial

## Orb size seen from the camera (degrees across), and its smallest size in meters.
@export var orb_deg: float = 1.8
@export var orb_min_m: float = 0.8
## Seconds the orb takes to grow to full size out of the muzzle.
@export var bloom_time: float = 0.05
## Trail length behind the pellet (m) and its width seen from the camera (degrees).
@export var trail_length: float = 9.0
@export var trail_deg: float = 0.28
## Lightning redraws per second (lower = calmer, higher = more crackle).
@export var refresh_hz: float = 30.0
## Chance per redraw that a spark spits off the pellet, and the spark length seen from the camera (degrees).
@export var spit_chance: float = 0.35
@export var spit_deg: float = 1.2
## Arc tint (multiplies the shader colors).
@export var tint: Color = Color(1.0, 1.0, 1.0)

var _orb: MeshInstance3D
var _arcs: ElectricArcs
var _start: Vector3 = Vector3.INF
var _age: float = 0.0
var _next_refresh: float = 0.0


func _ready() -> void:
	if _orb_material == null:
		_orb_material = ShaderMaterial.new()
		_orb_material.shader = ORB_SHADER
	_orb = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_orb.mesh = quad
	_orb.material_override = _orb_material
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.custom_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	_orb.set_instance_shader_parameter(&"seed", randf() * 100.0)
	_orb.set_instance_shader_parameter(&"size", 0.01)
	add_child(_orb)
	_arcs = ElectricArcs.new()
	add_child(_arcs)


func _process(delta: float) -> void:
	_age += delta
	var here := global_position
	if not _start.is_finite():
		_start = here
	var view := ElectricArcs.view_position(self)
	var distance := maxf(view.distance_to(here), 1.0)
	var per_deg := distance * tan(deg_to_rad(1.0))
	var grow := clampf(_age / maxf(bloom_time, 0.001), 0.2, 1.0)
	_orb.set_instance_shader_parameter(&"size", maxf(orb_min_m, per_deg * orb_deg) * grow)
	_next_refresh -= delta
	if _next_refresh > 0.0:
		return
	_next_refresh = 1.0 / maxf(refresh_hz, 1.0)
	_arcs.clear_arcs()
	var bullet := get_parent() as Bullet
	var back := -bullet.velocity.normalized() if bullet != null and not bullet.velocity.is_zero_approx() \
			else global_basis.z
	var length := minf(trail_length, _start.distance_to(here))
	if length > 0.3:
		var width := per_deg * trail_deg
		_arcs.add_bolt(here, here + back * length, width, length * 0.06, 7, tint, 0.15, 1.0, 0.0)
	if randf() < spit_chance:
		var out := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var spit := per_deg * spit_deg * randf_range(0.6, 1.2)
		_arcs.add_bolt(here, here + out * spit, per_deg * trail_deg * 0.7, spit * 0.3, 3, tint, 0.0, 1.0, 0.2)
	_arcs.commit()
