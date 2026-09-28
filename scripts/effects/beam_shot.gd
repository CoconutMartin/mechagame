class_name BeamShot
extends Node3D
## The visible beam of a beam rifle shot: a glowing rod from the muzzle to the hit point.
## A short shot fades out at once. A sustained beam (charged shot) stays while the weapon holds it
## (hold = true, update the ends each frame with show_beam), pulses a little, then fades after
## release().

## Seconds the beam takes to fade out.
@export var duration: float = 0.35
## Beam thickness, in meters.
@export var width: float = 0.6
## Pulse size of a sustained beam (part of the width).
@export var pulse: float = 0.15

var hold: bool = false

var _age: float = 0.0
var _time: float = 0.0


func show_beam(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	global_position = (from + to) * 0.5
	if length > 0.01:
		look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	scale = Vector3(width, width, maxf(length, 0.01))


## Ends a sustained beam: it fades out.
func release() -> void:
	hold = false
	_age = 0.0


func _process(delta: float) -> void:
	_time += delta
	if hold:
		var size := width * (1.0 + pulse * sin(_time * 40.0))
		scale.x = size
		scale.y = size
		return
	_age += delta
	var left := 1.0 - _age / duration
	if left <= 0.0:
		queue_free()
		return
	scale.x = width * left
	scale.y = width * left
