class_name ShotGlow
extends Node
## Makes some weapon meshes glow in one color for a moment at each shot (flash()), then fade.
## Used for the red muzzle parts of the beam rifles (user request 2026-11-01).

@export var color: Color = Color(1.0, 0.08, 0.04)
## Emission strength at a shot.
@export var energy: float = 5.0
## Seconds fully lit after a shot, then seconds to fade to dark.
@export var hold: float = 0.15
@export var fade: float = 0.5

var _materials: Array[StandardMaterial3D] = []
var _since: float = 1000.0


func setup(meshes: Array[MeshInstance3D]) -> void:
	for mesh in meshes:
		if mesh != null:
			_materials.append(glow_material(mesh, color))
	_apply()


func flash() -> void:
	_since = 0.0
	_apply()


func _process(delta: float) -> void:
	if _since > hold + fade:
		return
	_since += delta
	_apply()


func _apply() -> void:
	var level := 1.0 if _since < hold else clampf(1.0 - (_since - hold) / maxf(fade, 0.01), 0.0, 1.0)
	for material in _materials:
		material.emission_energy_multiplier = energy * level


## A copy of the mesh material that glows in color (energy 0 at first), set as the mesh override. The PS1
## skin keeps glowing materials as they are.
static func glow_material(mesh: MeshInstance3D, glow_color: Color) -> StandardMaterial3D:
	var base := mesh.get_active_material(0)
	var material: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = glow_color
	material.emission_energy_multiplier = 0.0
	mesh.material_override = material
	return material
