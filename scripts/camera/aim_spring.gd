class_name AimSpring
extends RefCounted
## A damped spring that follows a target angle.
## With damping below 1 it passes the target a little and comes back (overshoot).

## Current angle in radians.
var value: float = 0.0
var velocity: float = 0.0


func _init(start: float = 0.0) -> void:
	value = start


## frequency: oscillations per second. Lower = slower, heavier aim.
## damping: 1.0 = no overshoot. 0.5 to 0.6 = about 10 to 15% overshoot.
## max_offset: largest allowed gap to the target, in radians.
func update(target: float, frequency: float, damping: float, max_offset: float, delta: float) -> void:
	var omega := TAU * frequency
	# Small substeps keep the spring stable at low frame rates.
	var steps := ceili(delta / (1.0 / 240.0))
	var step := delta / steps
	for i in steps:
		var accel := omega * omega * (target - value) - 2.0 * damping * omega * velocity
		velocity += accel * step
		value += velocity * step
	value = clampf(value, target - max_offset, target + max_offset)
