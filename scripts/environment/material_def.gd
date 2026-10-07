@tool
class_name MaterialDef
extends Resource
## A building or ground material: its look and how strong it is (urban map).
## The look is a StandardMaterial3D with world-space triplanar mapping, so the texture keeps its real
## size on every box (texture_scale_m = meters per texture repeat).

@export var display_name: String = ""

@export_group("Strength")
## Hit points per cubic meter of chunk volume.
@export var hp_per_m3: float = 100.0
## A hit below this damage does nothing to this material (glass 0, concrete 80).
@export var damage_threshold: float = 0.0
## Tons per cubic meter (falling chunk mass).
@export var density: float = 2.0

@export_group("Look")
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export var roughness_texture: Texture2D
## Meters covered by one texture repeat.
@export var texture_scale_m: float = 2.0
## Color multiplier (white = the texture colors). Without a texture: the color.
@export var tint: Color = Color.WHITE
@export_range(0.0, 1.0) var metallic: float = 0.0
@export_range(0.0, 1.0) var roughness: float = 0.85
## Light the material gives off (0 = none). Used by lit windows.
@export var emission_energy: float = 0.0
@export var emission_color: Color = Color(1.0, 0.85, 0.6)
## 1 = solid. Below 1 the material is see-through (glass).
@export_range(0.0, 1.0) var opacity: float = 1.0
## Dust and debris color when this material breaks.
@export var debris_color: Color = Color(0.5, 0.5, 0.5)

var _material: StandardMaterial3D


## The render material (made once and shared by every piece with this MaterialDef).
func get_material() -> StandardMaterial3D:
	if _material == null:
		_material = _make()
	return _material


func _make() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = albedo_texture
	m.metallic = metallic
	m.roughness = roughness
	if roughness_texture != null:
		m.roughness_texture = roughness_texture
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if normal_texture != null:
		m.normal_enabled = true
		m.normal_texture = normal_texture
	var repeat := 1.0 / maxf(texture_scale_m, 0.01)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(repeat, repeat, repeat)
	m.uv1_triplanar_sharpness = 4.0
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission_color
		m.emission_energy_multiplier = emission_energy
	if opacity < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.albedo_color.a = opacity
	return m
