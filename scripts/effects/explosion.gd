class_name Explosion
extends Node3D
## A missile explosion: a flash ball that grows and fades, fire particles, smoke and a light.

@export var life: float = 1.6
@export var flash_size: float = 7.0

@onready var _flash: MeshInstance3D = $Flash
@onready var _light: OmniLight3D = $Light
var _age: float = 0.0


func _ready() -> void:
	for child in get_children():
		if child is CPUParticles3D:
			(child as CPUParticles3D).emitting = true


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / 0.35, 0.0, 1.0)
	_flash.scale = Vector3.ONE * lerpf(0.3, 1.0, t) * flash_size
	_flash.visible = t < 1.0
	_light.light_energy = maxf(0.0, 1.0 - _age / 0.4) * 12.0
	if _age > life:
		queue_free()
