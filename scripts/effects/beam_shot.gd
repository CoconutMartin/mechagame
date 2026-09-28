class_name BeamShot
extends Node3D
## The visible beam of a beam rifle shot: a glowing rod from the muzzle to the hit point that
## gets thinner and fades out.

## Seconds the beam stays visible.
@export var duration: float = 0.35
## Beam thickness at the start, in meters.
@export var width: float = 0.6

@onready var _mesh: MeshInstance3D = $Beam
var _age: float = 0.0


func show_beam(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	global_position = (from + to) * 0.5
	if length > 0.01:
		look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	scale = Vector3(width, width, maxf(length, 0.01))


func _process(delta: float) -> void:
	_age += delta
	var left := 1.0 - _age / duration
	if left <= 0.0:
		queue_free()
		return
	scale.x = width * left
	scale.y = width * left
