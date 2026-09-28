class_name ChargeGlow
extends Node3D
## Lights up a weapon while it charges: the coils light one after another from the back to the
## front, then the emitter lens and a small light at the muzzle. Fully lit at level 1.
## Set level every frame (0 to 1).

## Glow color (the beam color).
@export var color: Color = Color(0.45, 0.9, 1.0)
## Emission strength of a fully lit coil and of the lens.
@export var coil_energy: float = 2.5
@export var lens_energy: float = 4.0
## Muzzle light strength and reach at level 1.
@export var light_energy: float = 2.0
@export var light_range: float = 5.0
## How fast the glow follows the level, and how fast it fades after (1 / seconds).
@export var rise_speed: float = 12.0
@export var fade_speed: float = 2.5

## 0 = dark, 1 = fully lit.
var level: float = 0.0

var _shown: float = 0.0
var _coils: Array[StandardMaterial3D] = []
var _lens: StandardMaterial3D
var _light: OmniLight3D


## coils: meshes from back to front. lens: the emitter mesh. muzzle: where the light goes.
func setup(coils: Array[MeshInstance3D], lens: MeshInstance3D, muzzle: Node3D) -> void:
	for coil in coils:
		_coils.append(_glow_material(coil))
	_lens = _glow_material(lens)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = light_range
	_light.light_energy = 0.0
	_light.visible = false
	muzzle.add_child(_light)
	_apply()


func _process(delta: float) -> void:
	var speed := rise_speed if level > _shown else fade_speed
	_shown = move_toward(_shown, clampf(level, 0.0, 1.0), speed * delta)
	_apply()


func _apply() -> void:
	var count := _coils.size()
	for i in count:
		# Each coil lights in its own part of the charge.
		var part := clampf(_shown * count - i, 0.0, 1.0)
		_coils[i].emission_energy_multiplier = coil_energy * part
	if _lens != null:
		_lens.emission_energy_multiplier = lens_energy * _shown * _shown
	if _light != null:
		_light.light_energy = light_energy * _shown * _shown
		_light.visible = _shown > 0.02


## A copy of the mesh material with emission in the glow color, set as the mesh override.
func _glow_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var base := mesh.get_active_material(0)
	var material: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	mesh.material_override = material
	return material
