class_name MechFootsteps
extends Node
## Sends a footstep signal each time the walking mech takes a stride.
## No steps while boosting, because the mech skates on its thrusters.

signal footstep(strength: float)

@export var mech: Mech
## Meters traveled per footstep.
@export var stride_length: float = 7.0
## Below this speed (m/s) the mech takes no steps.
@export var min_speed: float = 1.0

var _distance: float = 0.0


func _physics_process(delta: float) -> void:
	if not mech.is_on_floor() or mech.is_boosting:
		return
	var speed := mech.get_horizontal_speed()
	if speed < min_speed:
		return
	_distance += speed * delta
	if _distance >= stride_length:
		_distance -= stride_length
		footstep.emit(clampf(speed / mech.walk_speed, 0.4, 1.0))
