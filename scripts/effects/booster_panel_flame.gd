class_name BoosterPanelFlame
extends Node3D
## Fire from a whole outlet panel (Boost Pack grilles; user request 2026-11-03: "Boost Pack boosts should come from the
## entire backpack panel, light blue fire. Make it look realistic, add some character"). A child of the Outlet node
## (+Y out of the panel), sized to the panel's OutletGlow plate. Flame tongues stand across the whole panel (seen
## from the side), each with its own flicker and now and then a longer lick; stacked glowing cards over the panel give
## it body from behind (the game camera looks into the exhaust). Same use as BoosterPlume: set_thrust each frame.

const SHADER := preload("res://shaders/booster_panel_flame.gdshader")

## Flame length at full thrust (m).
@export var length: float = 2.0
## Space between the tongues along the panel (m).
@export var tongue_spacing: float = 0.24
## How often each tongue picks a new length (per second), how much it varies, and the chance per pick of a long lick.
@export var lick_rate: float = 14.0
@export var lick_spread: float = 0.35
@export var lick_chance: float = 0.08
@export var lick_length: float = 1.5
## Cards over the panel (from the panel out to card_reach of the length).
@export var card_count: int = 5
@export var card_reach: float = 0.7

var _material: ShaderMaterial
var _tongues: Array[MeshInstance3D] = []
var _tongue_basis: Array[Basis] = []
var _tongue_place: Array[Vector3] = []
var _tongue_scale: PackedFloat32Array = PackedFloat32Array()
var _cards: Array[MeshInstance3D] = []
var _next_pick: float = 0.0
var _size := Vector2(0.4, 0.4)
var _long_x: bool = true


## Adds a panel flame to an outlet, sized to its plate (in the outlet's frame). Off until set_thrust.
static func attach(outlet: Node3D, plate: MeshInstance3D, color: Color, flame_length: float) -> BoosterPanelFlame:
	var flame := BoosterPanelFlame.new()
	flame.name = "PanelFlame"
	flame.length = flame_length
	flame._material = ShaderMaterial.new()
	flame._material.shader = SHADER
	flame._material.set_shader_parameter(&"mid_color", color)
	flame._material.set_shader_parameter(&"hot_color", color.lerp(Color.WHITE, 0.7))
	flame._material.set_shader_parameter(&"tail_color", Color(color.r * 0.25, color.g * 0.4, color.b))
	if plate != null and outlet.is_inside_tree():
		var to_outlet := outlet.global_transform.affine_inverse() * plate.global_transform
		var aabb := plate.get_aabb()
		var low := Vector3.INF
		var high := -Vector3.INF
		for i in 8:
			var point := to_outlet * aabb.get_endpoint(i)
			low = low.min(point)
			high = high.max(point)
		flame._size = Vector2(maxf(high.x - low.x, 0.1), maxf(high.z - low.z, 0.1))
		flame.position = Vector3((high.x + low.x) * 0.5, 0.0, (high.z + low.z) * 0.5)
	outlet.add_child(flame)
	return flame


func _ready() -> void:
	add_to_group(BoosterPlume.SKIN_SKIP)
	_long_x = _size.x >= _size.y
	var long_size := _size.x if _long_x else _size.y
	var short_size := _size.y if _long_x else _size.x
	var count := clampi(roundi(long_size / maxf(tongue_spacing, 0.05)), 3, 16)
	# Across the panel: the tongue planes run along the short side (seen from the side) and along the long side.
	var along := Vector3.RIGHT if _long_x else Vector3.BACK
	var across := Vector3.BACK if _long_x else Vector3.RIGHT
	for i in count:
		var offset := lerpf(-0.5, 0.5, (float(i) + 0.5) / float(count)) * long_size
		for plane in 2:
			var tongue := _quad(Vector2(short_size * 1.1 if plane == 0 else long_size / count * 2.8, 1.0))
			# A quad lies in X (width) and Y (length); turn its width onto the chosen panel axis.
			var width_axis := across if plane == 0 else along
			var basis := Basis(width_axis, Vector3.UP, width_axis.cross(Vector3.UP))
			_tongues.append(tongue)
			_tongue_basis.append(basis)
			_tongue_place.append(along * offset)
			_tongue_scale.append(1.0)
			tongue.set_instance_shader_parameter(&"seed", randf() * 100.0)
			tongue.set_instance_shader_parameter(&"mode", 0.0)
	for k in card_count:
		var card := _quad(Vector2(_size.x, _size.y))
		var layer := float(k) / float(maxi(card_count - 1, 1))
		card.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		card.set_instance_shader_parameter(&"seed", randf() * 100.0)
		card.set_instance_shader_parameter(&"mode", 1.0)
		card.set_instance_shader_parameter(&"layer", layer)
		_cards.append(card)
	set_thrust(0.0, 0.0)


func _quad(size: Vector2) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.add_to_group(BoosterPlume.SKIN_SKIP)
	add_child(mesh)
	return mesh


## thrust 0 (off) to 1 (full) and more in a burst; flicker a small random change this frame.
func set_thrust(thrust: float, flicker: float) -> void:
	visible = thrust > 0.02
	if not visible:
		return
	var level := clampf(thrust, 0.0, 1.6) * (1.0 + flicker)
	_next_pick -= get_process_delta_time()
	if _next_pick <= 0.0:
		_next_pick = 1.0 / maxf(lick_rate, 1.0)
		for i in _tongue_scale.size():
			var lick := lick_length if randf() < lick_chance else 1.0
			_tongue_scale[i] = randf_range(1.0 - lick_spread, 1.0 + lick_spread * 0.5) * lick
	var fade := clampf(thrust * 1.5, 0.0, 1.0)
	for i in _tongues.size():
		var tongue_length := maxf(length * level * _tongue_scale[i], 0.05)
		_tongues[i].transform = Transform3D(_tongue_basis[i] * Basis.from_scale(Vector3(1.0, tongue_length, 1.0)),
				_tongue_place[i] + Vector3.UP * tongue_length * 0.5)
		_tongues[i].set_instance_shader_parameter(&"fade", fade)
	for k in _cards.size():
		var layer := float(k) / float(maxi(_cards.size() - 1, 1))
		_cards[k].position = Vector3.UP * (0.02 + length * level * card_reach * layer)
		_cards[k].scale = Vector3.ONE * (1.0 - 0.25 * layer)
		_cards[k].set_instance_shader_parameter(&"fade", fade)
