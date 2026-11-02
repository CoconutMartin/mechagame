class_name BoosterPlume
extends Node3D
## A realistic rocket exhaust at one booster outlet (user request 2026-11-02: "make the fire coming out of the boosters
## for all backpacks with boosters realistic"). It points along the outlet's +Y axis (out of the nozzle). Layers, all
## unshaded and blended (mix) with colors above 1 so the map glow blooms them, also in the Compatibility renderer:
## a long soft orange plume that breaks up into tongues toward a dark red tail, a shorter white-blue core with faint
## shock diamonds, a tiny white-hot tip, a flare at the nozzle and a faint heat haze glow along the plume.
## BackPackOutlets adds one to every outlet and calls set_thrust each frame.

const PLUME_SHADER := preload("res://shaders/booster_plume.gdshader")
const GLOW_SHADER := preload("res://shaders/booster_glow.gdshader")
## Group of the effect meshes: no skin (PS1 or realistic) is put on them.
const SKIN_SKIP := &"skin_skip"
const RINGS: int = 18
const SEGMENTS: int = 14

## Plume length at full thrust, in meters.
@export var length: float = 3.0
## Radius of the plume at the nozzle, in meters.
@export var radius: float = 0.25
## Core length as a fraction of the plume length.
@export var core_length: float = 0.5
## Strength of the shock diamonds in the core (0 = none).
@export var diamond_strength: float = 0.9
## Brightness of the plume layers. Keep it low: bright emissive colors wash out in the tonemapper.
@export var energy: float = 1.45

static var _mesh: ArrayMesh
static var _noise: NoiseTexture2D

var _plume: MeshInstance3D
var _core: MeshInstance3D
var _tip: MeshInstance3D
var _flare: MeshInstance3D
var _haze: MeshInstance3D
var _plume_material: ShaderMaterial
var _core_material: ShaderMaterial
var _tip_material: ShaderMaterial
var _flare_material: ShaderMaterial
var _haze_material: ShaderMaterial


## Adds a plume to an outlet node (+Y = out of the nozzle). The plume is off until set_thrust.
static func attach(outlet: Node3D, plume_radius: float, plume_length: float) -> BoosterPlume:
	var plume := BoosterPlume.new()
	plume.name = "BoosterPlume"
	plume.radius = plume_radius
	plume.length = plume_length
	outlet.add_child(plume)
	# A different noise pattern on each plume.
	plume.rotate_y(randf() * TAU)
	return plume


func _ready() -> void:
	_plume_material = _plume_material_make(Color(0.8, 0.9, 1.0), Color(1.0, 0.3, 0.02), Color(0.5, 0.04, 0.01), 0.0, 1.0, 1.0)
	_core_material = _plume_material_make(Color(0.65, 0.82, 1.0), Color(1.0, 0.8, 0.4), Color(1.0, 0.4, 0.06), diamond_strength, 1.2, 1.0)
	_core_material.set_shader_parameter(&"energy", energy * 1.5)
	_tip_material = _plume_material_make(Color(1.0, 1.0, 1.0), Color(0.9, 0.95, 1.0), Color(1.0, 0.8, 0.5), 0.0, 1.0, 1.0)
	_tip_material.set_shader_parameter(&"energy", energy * 2.0)
	_plume = _layer("Plume", _plume_material)
	_core = _layer("Core", _core_material)
	_tip = _layer("Tip", _tip_material)
	_flare = _sprite("Flare", Color(1.0, 0.72, 0.4), 1.4, 0.4)
	_haze = _sprite("Haze", Color(1.0, 0.4, 0.08), 1.2, 0.1)
	_flare_material = _flare.material_override as ShaderMaterial
	_haze_material = _haze.material_override as ShaderMaterial
	set_thrust(0.0, 0.0)


## Thrust 0 (off) to about 1.4 (burst) and a random change of the length (-1 to 1 times the flicker fraction).
func set_thrust(thrust: float, flicker: float) -> void:
	visible = thrust > 0.02
	if not visible:
		return
	var level := thrust * (1.0 + flicker)
	var wide := 0.75 + 0.25 * minf(thrust, 1.0)
	# The plume grows a little shorter and fatter in a puff, the core follows its length.
	_place(_plume, radius * 1.15 * wide, length * level, 0.0)
	_place(_core, radius * 0.62 * wide, length * core_length * level, 0.0)
	_place(_tip, radius * 0.32 * wide, length * core_length * 0.45 * level, 0.0)
	_flare.position = Vector3(0.0, radius * 0.25, 0.0)
	_haze.position = Vector3(0.0, length * 0.3 * level, 0.0)
	var shine := clampf(thrust, 0.0, 1.4)
	for material: ShaderMaterial in [_plume_material, _core_material, _tip_material, _flare_material, _haze_material]:
		material.set_shader_parameter(&"intensity", shine)
	_flare_material.set_shader_parameter(&"size", radius * 3.6 * (0.85 + 0.3 * randf()))
	_haze_material.set_shader_parameter(&"size", radius * 7.0 + length * 0.18 * level)
	# The diamonds slide a little with the thrust.
	_core_material.set_shader_parameter(&"diamond_count", 3.0 + 2.0 * clampf(thrust, 0.0, 1.0))


func _place(layer: MeshInstance3D, width: float, height: float, y: float) -> void:
	layer.position = Vector3(0.0, y, 0.0)
	layer.scale = Vector3(width, maxf(height, 0.001), width)


func _plume_material_make(hot: Color, mid: Color, tail: Color, diamonds: float, edge_power: float, alpha: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PLUME_SHADER
	material.set_shader_parameter(&"noise_tex", _noise_texture())
	material.set_shader_parameter(&"hot_color", hot)
	material.set_shader_parameter(&"mid_color", mid)
	material.set_shader_parameter(&"tail_color", tail)
	material.set_shader_parameter(&"energy", energy)
	material.set_shader_parameter(&"diamonds", diamonds)
	material.set_shader_parameter(&"edge_power", edge_power)
	material.set_shader_parameter(&"alpha_scale", alpha)
	return material


func _layer(layer_name: String, material: ShaderMaterial) -> MeshInstance3D:
	var layer := MeshInstance3D.new()
	layer.name = layer_name
	layer.mesh = _lathe()
	layer.material_override = material
	_no_shadow(layer)
	add_child(layer)
	return layer


func _sprite(sprite_name: String, color: Color, power: float, alpha: float) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	sprite.name = sprite_name
	sprite.mesh = QuadMesh.new()
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"glow_color", color)
	material.set_shader_parameter(&"energy", power)
	material.set_shader_parameter(&"alpha_scale", alpha)
	sprite.material_override = material
	_no_shadow(sprite)
	add_child(sprite)
	return sprite


func _no_shadow(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_to_group(SKIN_SKIP)


## Seamless noise for the tongues (made once).
static func _noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.03
		_noise = NoiseTexture2D.new()
		_noise.noise = noise
		_noise.width = 128
		_noise.height = 128
		_noise.seamless = true
	return _noise


## The plume body: a lathe along +Y, 1 m long and 1 m wide at its widest (made once). It swells a little after the
## nozzle and narrows to a point. UV.x runs round, UV.y along.
static func _lathe() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in RINGS + 1:
		var y := float(ring) / RINGS
		var r := _profile(y)
		var slope := (_profile(minf(y + 0.01, 1.0)) - _profile(maxf(y - 0.01, 0.0))) / 0.02
		for segment in SEGMENTS + 1:
			var angle := TAU * float(segment) / SEGMENTS
			var out := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(out * r + Vector3(0.0, y, 0.0))
			normals.append((out + Vector3(0.0, -slope, 0.0)).normalized())
			uvs.append(Vector2(float(segment) / SEGMENTS, y))
	for ring in RINGS:
		for segment in SEGMENTS:
			var a := ring * (SEGMENTS + 1) + segment
			var b := a + SEGMENTS + 1
			indices.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


## Radius of the plume at y (0 to 1 along it): 0.8 at the nozzle, a swell, then a taper to a point.
static func _profile(y: float) -> float:
	return (0.8 + 0.35 * sin(clampf(y / 0.35, 0.0, 1.0) * PI * 0.5)) * pow(1.0 - y, 0.75) * 0.87
