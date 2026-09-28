class_name MuzzleFlash
extends Node3D
## A short flash at the weapon muzzle. Random turn and size at each shot.

## Seconds the flash stays visible.
@export var duration: float = 0.05
@export var light: OmniLight3D
@export var light_energy: float = 3.0

var _time_left: float = 0.0


func _ready() -> void:
	visible = false


func flash() -> void:
	_time_left = duration
	visible = true
	rotation.z = randf() * TAU
	scale = Vector3.ONE * randf_range(0.8, 1.2)
	if light != null:
		light.light_energy = light_energy


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		visible = false
