class_name MechFootsteps
extends Node
## Sends a footstep signal each time the walking mech takes a stride.
## No steps while boosting, because the mech skates on its thrusters.
## Strides get shorter at low speed, like a person who walks slowly.

signal footstep(strength: float)

@export var mech: Mech
## Meters per footstep at walk speed and above.
@export var stride_length: float = 6.0
## Stride near standstill = stride_length x this value.
@export_range(0.1, 1.0) var min_stride_ratio: float = 0.3
## Below this speed (m/s) the mech takes no steps.
@export var min_speed: float = 1.0

## 0 to 1: how far the current stride is done.
var _progress: float = 0.0
var _step_count: int = 0
## Planned stride lengths for the next steps (for example after the boost exit hop).
var _stride_plan: Array[float] = []


func _physics_process(delta: float) -> void:
	if not mech.is_on_floor() or mech.is_boosting:
		return
	var speed := mech.get_horizontal_speed()
	if speed < min_speed:
		return
	_progress += speed * delta / get_stride(speed)
	if _progress >= 1.0:
		_progress -= 1.0
		_step_count += 1
		if not _stride_plan.is_empty():
			_stride_plan.pop_front()
		footstep.emit(clampf(speed / mech.walk_speed, 0.4, 1.0))


## Uses these stride lengths (meters) for the next steps, in order. The next stride starts now.
func start_stride_plan(strides: PackedFloat32Array) -> void:
	_stride_plan.clear()
	for stride in strides:
		_stride_plan.append(stride)
	_progress = 0.0


func has_stride_plan() -> bool:
	return not _stride_plan.is_empty()


## Meters left in the stride plan, plus a quarter of the last stride so the last step lands before the stop.
func get_stride_plan_distance() -> float:
	if _stride_plan.is_empty():
		return 0.0
	var total := _stride_plan[0] * (1.0 - _progress)
	for i in range(1, _stride_plan.size()):
		total += _stride_plan[i]
	return total + 0.25 * _stride_plan[_stride_plan.size() - 1]


## Stride length in meters at a speed.
func get_stride(speed: float) -> float:
	if not _stride_plan.is_empty():
		return _stride_plan[0]
	return stride_length * lerpf(min_stride_ratio, 1.0, clampf(speed / mech.walk_speed, 0.0, 1.0))


## Walk cycle position in radians. One full cycle (TAU) is two steps.
## A foot touches the ground at each multiple of PI.
func get_cycle_phase() -> float:
	return (float(_step_count % 2) + _progress) * PI


## Part of a stride left until the next footstep (0 to 1).
func get_progress_to_next_step() -> float:
	return 1.0 - _progress


## Steps taken while the speed changes from speed_from to speed_to at a steady rate,
## multiplied by that rate. Divide by the rate (m/s per second) to get the step count.
func get_steps_times_rate(speed_from: float, speed_to: float) -> float:
	var low := maxf(speed_to, min_speed)
	if speed_from <= low:
		return 0.0
	var samples := 32
	var width := (speed_from - low) / samples
	var total := 0.0
	for i in samples:
		var speed := low + (i + 0.5) * width
		total += speed / get_stride(speed) * width
	return total
