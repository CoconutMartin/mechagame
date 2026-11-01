class_name PulseShot
extends Node3D
## The look of an electric pulse shot (Shotgun 2 and 3; user requests 2026-11-01, the rune ring reference picture):
## a card drawn by shaders/pulse_rune.gdshader (a rounded rectangle with a gold outer line, a band of flickering gold
## glyphs, a gold inner line, a cyan center and sparkles). Shotgun 2: one horizontal rectangle; Shotgun 3 (`cross`): an
## X of two rune strips with cyan cores, corner to corner of the same rectangle. It flies along `velocity`, faces the
## way it flies, and keeps its size on screen: half_deg (degrees, across and up) seen from the player camera, a bit
## larger than the crosshair box. It ends at the first wall or at its range. It does no damage (the pellets do).

const SHADER := preload("res://shaders/pulse_rune.gdshader")

## Light color at the card's middle.
@export var light_color: Color = Color(0.5, 0.9, 1.0)
## X strip width as a part of the rectangle's height.
@export var strip_share: float = 0.5
## Layers that stop the look (1 world, 3 props, 4 hitboxes, 5 buildings).
@export_flags_3d_physics var collision_mask: int = 29

var velocity: Vector3 = Vector3.ZERO
## Half size seen from the camera, in degrees (across, up).
var half_deg: Vector2 = Vector2(7.2, 4.15)
var range_m: float = 270.0
var exclude: Array[RID] = []
## True: an X instead of a rectangle. Set before it enters the tree.
var cross: bool = false

var _travelled: float = 0.0
var _cards: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _fade: float = -1.0
var _age: float = 0.0


func _ready() -> void:
	var seed := randf() * 100.0
	for i in (2 if cross else 1):
		var card := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		card.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"seed", seed + i * 7.0)
		if not cross:
			# The rectangle: a narrower glyph band, so the cyan center shows (the short side is only about 60% of the long).
			material.set_shader_parameter(&"band_w", 0.19)
		if cross:
			# A strip: no corners to speak of, fewer glyph cells across, a bright cyan core along it.
			material.set_shader_parameter(&"corner", 0.9)
			material.set_shader_parameter(&"cells", 26.0)
			material.set_shader_parameter(&"band_w", 0.2)
			material.set_shader_parameter(&"core", 1.0)
			material.set_shader_parameter(&"fill", 0.45)
		card.material_override = material
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(card)
		_cards.append(card)
		_materials.append(material)
	var light := OmniLight3D.new()
	light.light_color = light_color
	light.light_energy = 3.0
	light.omni_range = 14.0
	add_child(light)
	_layout()


## World half sizes now (m): half_deg seen from the player camera at this distance.
func half_size() -> Vector2:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var distance := camera.global_position.distance_to(global_position) if camera != null else _travelled + 8.0
	return Vector2(tan(deg_to_rad(half_deg.x)), tan(deg_to_rad(half_deg.y))) * maxf(distance, 1.0)


func _layout() -> void:
	var half := half_size()
	if not cross:
		_cards[0].scale = Vector3(half.x * 2.0, half.y * 2.0, 1.0)
		_materials[0].set_shader_parameter(&"size", half * 2.0)
		return
	var length := half.length() * 2.0
	var width := half.y * 2.0 * strip_share
	var angle := atan2(half.y, half.x)
	for i in 2:
		_cards[i].rotation = Vector3(0.0, 0.0, angle if i == 0 else -angle)
		_cards[i].scale = Vector3(length, width, 1.0)
		_materials[i].set_shader_parameter(&"size", Vector2(length, width))


func _physics_process(delta: float) -> void:
	_age += delta
	if _fade >= 0.0:
		_fade += delta
		for material in _materials:
			material.set_shader_parameter(&"fade", clampf(1.0 - _fade / 0.15, 0.0, 1.0))
		if _fade >= 0.15:
			queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude))
	if not hit.is_empty():
		global_position = hit.position
		_fade = 0.0
		return
	global_position = to
	_travelled += from.distance_to(to)
	if _travelled >= range_m:
		_fade = 0.0
		return
	look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)
	# A quick bloom out of the muzzle, then a slight pulse.
	var grow := clampf(_age / 0.06, 0.25, 1.0) * (1.0 + 0.04 * sin(_age * 40.0))
	_layout()
	for card in _cards:
		card.scale *= Vector3(grow, grow, 1.0)
