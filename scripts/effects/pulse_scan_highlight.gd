class_name PulseScanHighlight
extends Node3D
## Highlight on a mech that a pulse scan found (user answer 2026-10-14): the mech glows at once (seen
## through walls and buildings) for the highlight time and fades out. The green wire sphere that shrank
## onto it first was removed (user request 2026-10-24).
## A child of the target, so it follows it. A new scan restarts it.

const HIGHLIGHT_SHADER := preload("res://shaders/pulse_scan_highlight.gdshader")

## Glow color on the found mech.
@export var color: Color = Color(1.0, 0.25, 0.1)
## Seconds of the fade out at the end of the highlight.
@export var fade_time: float = 1.0

var _time: float = 0.0
var _duration: float = 4.0
var _glow: ShaderMaterial
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
	var parent := get_parent() as Node3D
	for node in parent.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		_meshes.append([mesh, mesh.material_overlay])
		mesh.material_overlay = _glow


func _process(delta: float) -> void:
	_time += delta
	var glow := 1.0
	if _time > _duration - fade_time:
		glow = clampf((_duration - _time) / maxf(fade_time, 0.01), 0.0, 1.0)
	_glow.set_shader_parameter(&"strength", glow)
	if _time >= _duration:
		queue_free()


func _exit_tree() -> void:
	for entry in _meshes:
		var mesh := entry[0] as MeshInstance3D
		if is_instance_valid(mesh) and mesh.material_overlay == _glow:
			mesh.material_overlay = entry[1]
	_meshes.clear()
