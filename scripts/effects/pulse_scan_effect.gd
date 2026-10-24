class_name PulseScanEffect
extends MeshInstance3D
## The pulse scan look (user answer 2026-10-14): a full screen wire frame pass
## (shaders/pulse_scan_wire.gdshader). The ring spreads from the scan origin at the ring speed; each
## place shows the green wire frame for the wire frame time after the ring passes it, then fades out slowly.
## The fade starts at the mech and moves out at the ring speed; there is no second ring (user request
## 2026-10-24). Frees itself when the last place has faded out.

const WIRE_SHADER := preload("res://shaders/pulse_scan_wire.gdshader")

## Wire frame color.
@export var color: Color = Color(0.3, 1.0, 0.4)
## Dark green over the scanned places (0 = none, 1 = only the lines show).
@export var tint: float = 0.5
## World grid spacing in meters.
@export var grid_m: float = 10.0
## Fade out length after the wire frame time, in meters of ring travel (150 m at 70 m/s = about 2.1 s per place).
@export var end_band_m: float = 150.0

var data: PulseScanData
var _elapsed: float = 0.0
var _material: ShaderMaterial


static func create(world: Node, origin: Vector3, scan: PulseScanData) -> PulseScanEffect:
	var effect := PulseScanEffect.new()
	effect.data = scan
	world.add_child(effect)
	effect.global_position = origin
	# _ready ran inside add_child, before the place was set: the wave started at the world origin, not at the
	# mech (user report 2026-10-24: "the scan should start from the mech").
	effect._material.set_shader_parameter(&"origin", origin)
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
	material_override = _material


func _process(delta: float) -> void:
	_elapsed += delta
	_material.set_shader_parameter(&"elapsed", _elapsed)
	if _elapsed > (data.range_m + end_band_m) / maxf(data.ring_speed, 1.0) + data.wireframe_time:
		queue_free()
