class_name PulseScanHighlight
extends Node3D
## Highlight on a mech that a pulse scan found (user answer 2026-10-14): a green wire sphere converges on
## it, then the mech glows (seen through walls and buildings) for the highlight time and fades out.
## A child of the target, so it follows it. A new scan restarts it.

const HIGHLIGHT_SHADER := preload("res://shaders/pulse_scan_highlight.gdshader")
const CONVERGE_SHADER := preload("res://shaders/pulse_scan_converge.gdshader")

## Glow color on the found mech.
@export var color: Color = Color(1.0, 0.25, 0.1)
## Seconds the wire sphere takes to shrink onto the mech.
@export var converge_time: float = 0.5
## Wire sphere start radius in meters.
@export var converge_start_radius: float = 40.0
## Seconds of the fade out at the end of the highlight.
@export var fade_time: float = 1.0

var _time: float = 0.0
var _duration: float = 4.0
var _radius: float = 6.0
var _glow: ShaderMaterial
var _shell: MeshInstance3D
var _shell_material: ShaderMaterial
## Meshes with the glow and their overlay before it: [mesh, old overlay].
var _meshes: Array = []


## Highlights target for seconds (restarts a highlight it already has).
static func attach(target: Node3D, seconds: float) -> PulseScanHighlight:
	var highlight := target.get_node_or_null(^"PulseScanHighlight") as PulseScanHighlight
	if highlight == null:
		highlight = PulseScanHighlight.new()
		highlight.name = "PulseScanHighlight"
		target.add_child(highlight)
	highlight._time = 0.0
	highlight._duration = seconds
	return highlight


func _ready() -> void:
	_glow = ShaderMaterial.new()
	_glow.shader = HIGHLIGHT_SHADER
	_glow.set_shader_parameter(&"color", color)
	_glow.set_shader_parameter(&"strength", 0.0)
	var bounds := AABB()
	var first := true
	var parent := get_parent() as Node3D
	for node in parent.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		_meshes.append([mesh, mesh.material_overlay])
		mesh.material_overlay = _glow
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		_radius = maxf(bounds.size.length() * 0.5, 1.0)
		position = parent.to_local(bounds.get_center())
	_shell_material = ShaderMaterial.new()
	_shell_material.shader = CONVERGE_SHADER
	_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 32
	sphere.rings = 16
	_shell.mesh = sphere
	_shell.material_override = _shell_material
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)


func _process(delta: float) -> void:
	_time += delta
	var shrink := clampf(_time / maxf(converge_time, 0.01), 0.0, 1.0)
	_shell.visible = shrink < 1.0
	if _shell.visible:
		var radius := lerpf(converge_start_radius, _radius, 1.0 - pow(1.0 - shrink, 2.0))
		_shell.scale = Vector3.ONE * radius * 2.0
		_shell_material.set_shader_parameter(&"strength", 0.4 + 0.6 * shrink)
	var glow := shrink
	var end := converge_time + _duration
	if _time > end - fade_time:
		glow *= clampf((end - _time) / maxf(fade_time, 0.01), 0.0, 1.0)
	_glow.set_shader_parameter(&"strength", glow)
	if _time >= end:
		queue_free()


func _exit_tree() -> void:
	for entry in _meshes:
		var mesh := entry[0] as MeshInstance3D
		if is_instance_valid(mesh) and mesh.material_overlay == _glow:
			mesh.material_overlay = entry[1]
	_meshes.clear()
