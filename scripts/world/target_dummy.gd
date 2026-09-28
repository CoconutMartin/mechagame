class_name TargetDummy
extends StaticBody3D
## A mech-sized target for weapon tests. Missiles can lock it (group "lockable").
## It flashes when hit. Real HP and damage come in Phase 4.

## Lock point height above the base, in meters.
@export var lock_height: float = 5.0
@export var mesh: MeshInstance3D

var _flash: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"lockable")
	if mesh != null:
		_material = (mesh.get_active_material(0) as StandardMaterial3D).duplicate()
		mesh.material_override = _material


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * lock_height


## Called by weapons when they hit (Phase 4 adds damage).
func on_hit(_damage: float) -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _material == null or _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_material.emission_enabled = _flash > 0.0
	_material.emission = Color(1.0, 0.5, 0.2)
	_material.emission_energy_multiplier = _flash * 3.0
