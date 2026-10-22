class_name PulseScanEffect
extends MeshInstance3D
## The pulse scan look (user answer 2026-10-14): a full screen wire frame pass
## (shaders/pulse_scan_wire.gdshader). The ring spreads from the scan origin at the ring speed; each
## place shows the green wire frame for the wire frame time after the ring passes it. The end is a second,
## dimmer ring at the same speed that wipes the wire frame out as it goes (user request 2026-10-22). Frees
## itself when the end ring has reached the range.

const WIRE_SHADER := preload("res://shaders/pulse_scan_wire.gdshader")

## Wire frame color.
@export var color: Color = Color(0.3, 1.0, 0.4)
## Dark green over the scanned places (0 = none, 1 = only the lines show).
@export var tint: float = 0.5
## World grid spacing in meters.
@export var grid_m: float = 10.0
## Width of the band (m) in which the wire frame goes out ahead of the end ring.
@export var end_band_m: float = 40.0
## Brightness of the end ring (the front ring is 0.7).
@export var end_ring_strength: float = 0.45

var data: PulseScanData
var _elapsed: float = 0.0
var _material: ShaderMaterial


static func create(world: Node, origin: Vector3, scan: PulseScanData) -> PulseScanEffect:
	var effect := PulseScanEffect.new()
	effect.data = scan
	world.add_child(effect)
	effect.global_position = origin
	return effect


func _ready() -> void:
	name = "PulseScanEffect"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	# The quad covers the screen from the vertex shader; never cull it.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = WIRE_SHADER
	_material.set_shader_parameter(&"origin", global_position)
	_material.set_shader_parameter(&"ring_speed", data.ring_speed)
	_material.set_shader_parameter(&"range_m", data.range_m)
	_material.set_shader_parameter(&"wire_time", data.wireframe_time)
	_material.set_shader_parameter(&"color", color)
	_material.set_shader_parameter(&"tint", tint)
	_material.set_shader_parameter(&"grid_m", grid_m)
	_material.set_shader_parameter(&"end_band", end_band_m)
	_material.set_shader_parameter(&"end_ring_strength", end_ring_strength)
	material_override = _material


func _process(delta: float) -> void:
	_elapsed += delta
	_material.set_shader_parameter(&"elapsed", _elapsed)
	if _elapsed > data.range_m / maxf(data.ring_speed, 1.0) + data.wireframe_time:
		queue_free()
