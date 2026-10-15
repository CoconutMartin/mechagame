class_name ImpactSpark
extends Node3D
## Sparks, a dust puff and a short flash where a bullet hits. Frees itself when done.

@export var sparks: CPUParticles3D
## Optional dust puff.
@export var dust: CPUParticles3D
@export var light: OmniLight3D
## Seconds before this node is removed.
@export var life: float = 1.4

var _age: float = 0.0


func _ready() -> void:
	# The creator sets the place and the turn after add_child. CPUParticles3D that start in _ready
	# make their one-shot burst at once, at the world origin (user report 2026-10-15: sparks near
	# the mech's foot where the map origin is). So the burst waits until the end of the frame.
	_start.call_deferred()


func _start() -> void:
	sparks.emitting = true
	if dust != null:
		dust.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if light != null:
		light.light_energy = maxf(0.0, 1.0 - _age / 0.1) * 4.0
	if _age > life:
		queue_free()
