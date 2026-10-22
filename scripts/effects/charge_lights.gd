class_name ChargeLights
extends Node
## Charge indicator on a weapon: a row of small lamps that light up one after another with the
## charge level (3 lamps on the Beam Rifle: 1 = a tap, 2 = half charge, 3 = full charge).
## Set level every frame (0 to 1). A lamp lights fast and fades out slowly, like ChargeGlow.

## Lamp color (the beam color).
@export var color: Color = Color(0.45, 0.9, 1.0)
## Emission strength of a lit lamp.
@export var lamp_energy: float = 1.6
## Charge level at which each lamp lights (same order as the lamps). A lamp is lit when
## level >= its value. Any level above 0 lights lamp 1 (the tap shot).
@export var thresholds: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0])
## How fast a lamp lights, and how fast it fades after (1 / seconds).
@export var rise_speed: float = 12.0
@export var fade_speed: float = 2.5

## 0 = no lamp, 1 = all lamps.
var level: float = 0.0

var _lamps: Array[StandardMaterial3D] = []
var _dark: Array[Color] = []
var _shown: PackedFloat32Array = PackedFloat32Array()


## lamps: the lamp meshes in order (lamp 1 first).
func setup(lamps: Array[MeshInstance3D]) -> void:
	for lamp in lamps:
		_lamps.append(_glow_material(lamp))
		_dark.append(_lamps[-1].albedo_color)
	_shown.resize(_lamps.size())
	_apply()


func _process(delta: float) -> void:
	for i in _lamps.size():
		var threshold := thresholds[i] if i < thresholds.size() else 1.0
		var target := 1.0 if level >= threshold and level > 0.0 else 0.0
		var speed := rise_speed if target > _shown[i] else fade_speed
		_shown[i] = move_toward(_shown[i], target, speed * delta)
	_apply()


func _apply() -> void:
	for i in _lamps.size():
		_lamps[i].emission_energy_multiplier = lamp_energy * _shown[i]
		# The lamp body also brightens when lit, so it reads without bloom.
		_lamps[i].albedo_color = _dark[i].lerp(color, _shown[i] * 0.25)


## A copy of the mesh material with emission in the lamp color, set as the mesh override.
## An emissive material keeps its own look under the PS1 skin (PS1Skin leaves it alone).
func _glow_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var base := mesh.get_active_material(0)
	var material: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	mesh.material_override = material
	return material
