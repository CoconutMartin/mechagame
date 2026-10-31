class_name BackPackEnergyBar
extends Node
## Boost energy light on a back pack (Boost Pack, user request 2026-10-31: "a third bar for the boost energy
## indicator. Full energy = bright light blue light, then color and brightness fade as energy approaches empty").
## The pack model has an EnergyBar mesh and/or EnergyCable* meshes (Power Pack, user request 2026-10-31: "make the
## cables glow with the energy level"); this node colors them each frame from the mech's energy fraction. The bar
## is an unshaded light; the cables keep their shading and glow (emission) brighter with more energy.
## When the energy runs empty the bar blinks twice (user request 2026-10-31), then it follows the energy again and
## slowly gets brighter as the energy recharges. BackPackMount adds this node when the model has an EnergyBar mesh.

## Bar color at full energy (bright light blue).
@export var full_color: Color = Color(0.3, 0.8, 1.0)
## Bar color at empty energy (dim, gray blue).
@export var empty_color: Color = Color(0.1, 0.12, 0.15)
## Shape of the fade (1 = even; above 1 = stays bright longer, then drops faster near empty).
@export var fade_curve: float = 0.6
## Cable color at full energy (bright orange) and at empty (dark, dull orange).
@export var cable_full_color: Color = Color(1.0, 0.36, 0.08)
@export var cable_empty_color: Color = Color(0.22, 0.09, 0.05)
## Cable glow strength at full energy (emission energy; 0 at empty).
@export var cable_glow: float = 1.1
## Bar color in the "on" part of a blink when the energy runs empty.
@export var blink_color: Color = Color(0.3, 0.8, 1.0)
## Blinks when the energy runs empty.
@export var blink_count: int = 2
## Time of one blink, on and off (s).
@export var blink_period: float = 0.36

var mech: Mech
## The shown energy fraction (0 to 1).
var fraction: float = 1.0

var _bar: MeshInstance3D
var _material: StandardMaterial3D
var _cables: Array[MeshInstance3D] = []
var _cable_material: StandardMaterial3D
## Time since the energy ran empty (s); the bar blinks while it is under blink_count * blink_period.
var _blink_time: float = INF


## Adds the energy light for a pack model (null when the model has no EnergyBar or EnergyCable mesh).
static func attach(target: Mech, pack_model: Node3D) -> BackPackEnergyBar:
	if target == null or pack_model == null:
		return null
	var bar := pack_model.find_child("EnergyBar", true, false) as MeshInstance3D
	var cables: Array[MeshInstance3D] = []
	for node in pack_model.find_children("EnergyCable*", "MeshInstance3D", true, false):
		cables.append(node as MeshInstance3D)
	if bar == null and cables.is_empty():
		return null
	var light := BackPackEnergyBar.new()
	light.name = "BackPackEnergyBar"
	light.mech = target
	light._bar = bar
	light._cables = cables
	target.add_child(light)
	return light


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Emission on: the PS1 skin leaves emissive materials as they are.
	_cable_material = StandardMaterial3D.new()
	_cable_material.roughness = 0.45
	_cable_material.emission_enabled = true
	if mech != null and mech.energy != null:
		mech.energy.depleted.connect(_on_depleted)
	_apply()


func _on_depleted() -> void:
	_blink_time = 0.0


## True while the empty-energy blink plays.
func is_blinking() -> bool:
	return _blink_time < blink_count * blink_period


func _process(delta: float) -> void:
	_blink_time += delta
	_apply()


func _apply() -> void:
	fraction = mech.energy.get_fraction() if mech != null and mech.energy != null else 1.0
	var t := pow(clampf(fraction, 0.0, 1.0), fade_curve)
	_material.albedo_color = empty_color.lerp(full_color, t)
	var cable_t := t
	if is_blinking():
		var on := fmod(_blink_time, blink_period) < blink_period * 0.5
		_material.albedo_color = blink_color if on else empty_color
		cable_t = 1.0 if on else 0.0
	_cable_material.albedo_color = cable_empty_color.lerp(cable_full_color, cable_t)
	_cable_material.emission = cable_full_color
	_cable_material.emission_energy_multiplier = cable_glow * cable_t
	# Each mesh keeps its light material (set again if something replaced it).
	if is_instance_valid(_bar) and _bar.material_override != _material:
		_bar.material_override = _material
	for cable in _cables:
		if is_instance_valid(cable) and cable.material_override != _cable_material:
			cable.material_override = _cable_material


## The bar's color now (for tests).
func get_color() -> Color:
	return _material.albedo_color


## The cables' glow strength now (for tests).
func get_cable_glow() -> float:
	return _cable_material.emission_energy_multiplier


## Cables this node lights (for tests).
func get_cables() -> Array[MeshInstance3D]:
	return _cables
