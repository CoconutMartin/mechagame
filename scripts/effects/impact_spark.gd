class_name ImpactSpark
extends Node3D
## Sparks and a short flash where a bullet hits. Frees itself when done.

@export var sparks: CPUParticles3D
@export var light: OmniLight3D
## Seconds before this node is removed.
@export var life: float = 0.8

var _age: float = 0.0


func _ready() -> void:
	sparks.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if light != null:
		light.light_energy = maxf(0.0, 1.0 - _age / 0.1) * 4.0
	if _age > life:
		queue_free()
