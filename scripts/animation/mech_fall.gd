class_name MechFall
extends Node
## Makes the mech fall over: optional side steps first, then it tips over a foot edge onto the
## ground, slides, can roll over along its length, and (if it is still alive) gets up again.
## It turns the Visual node only; the Mech body slides on the ground (Mech.is_fallen or wrecked).
## A mech with one leg left falls over when it stops boosting (rolls twice after a full boost).

signal landed
signal finished

enum State { IDLE, STEPS, FALL, ROLL, LIE, GET_UP }

@export var mech: Mech
@export var visual: Node3D
## The normal animation nodes. They stop while the mech is down.
@export var animation: Node
@export var camera_shake: CameraShake

## Distance from the mech center to the foot edge it tips over, and the lift that keeps the body
## on top of the ground when it lies down, in meters.
@export var pivot_distance: float = 1.5
@export var lie_lift: float = 0.4
## Tip-over time in seconds (it speeds up as it goes).
@export var fall_time: float = 0.9
## Side steps before a fall: step count, time for each step, side speed (m/s), sway in degrees.
@export var step_count: int = 2
@export var step_time: float = 0.5
@export var step_speed: float = 2.4
@export var step_sway_deg: float = 5.0
## Roll speed in degrees per second (180 = 75% slower than 720).
@export var roll_speed_deg: float = 180.0
## Time on the ground before getting up, and the get-up time, in seconds.
@export var lie_time: float = 1.5
@export var get_up_time: float = 1.5
## One leg left: a boost stop faster than this part of the boost speed is a "full boost" (2 rolls).
@export_range(0.0, 1.0) var full_boost_ratio: float = 0.85
## One leg left: the fall after a boost leans this much toward the broken leg (0 = straight ahead).
@export var broken_side_lean: float = 0.6

var state: State = State.IDLE

var _time: float = 0.0
var _direction := Vector3.FORWARD
var _step_side := Vector3.ZERO
var _rolls: int = 0
var _get_up: bool = false
var _angle: float = 0.0
var _roll: float = 0.0
var _sway: float = 0.0
var _base := Transform3D.IDENTITY
var _was_boosting: bool = false


func _ready() -> void:
	# Before the Mech moves (0), so the side step speed is used this frame.
	process_physics_priority = -1


## Starts a fall toward direction (world, flat). steps: world side direction for the side steps
## (zero = no steps). rolls: full rolls after the fall. get_up: stand up at the end (alive).
func fall(direction: Vector3, steps: Vector3 = Vector3.ZERO, rolls: int = 0, get_up: bool = false) -> void:
	if state != State.IDLE:
		return
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_step_side = Vector3(steps.x, 0.0, steps.z).normalized()
	_rolls = rolls
	_get_up = get_up
	_base = visual.transform
	_angle = 0.0
	_roll = 0.0
	_sway = 0.0
	if not mech.is_wrecked:
		mech.start_fall()
	if animation != null:
		animation.process_mode = Node.PROCESS_MODE_DISABLED
	_set_state(State.STEPS if _step_side != Vector3.ZERO and step_count > 0 else State.FALL)


func is_down() -> bool:
	return state != State.IDLE


func _physics_process(delta: float) -> void:
	_watch_boost()
	if state == State.IDLE:
		return
	_time += delta
	match state:
		State.STEPS:
			var total := step_time * step_count
			mech.velocity.x = _step_side.x * step_speed
			mech.velocity.z = _step_side.z * step_speed
			# A small sway to the side with each step.
			_sway = sin(_time / step_time * PI) * deg_to_rad(step_sway_deg)
			if _time >= total:
				_sway = 0.0
				_set_state(State.FALL)
		State.FALL:
			var t := clampf(_time / fall_time, 0.0, 1.0)
			_angle = PI * 0.5 * t * t
			if t >= 1.0:
				landed.emit()
				if camera_shake != null:
					camera_shake.add_shake(0.5, 0.6)
				_set_state(State.ROLL if _rolls > 0 else State.LIE)
		State.ROLL:
			var total := TAU * _rolls
			_roll = minf(_time * deg_to_rad(roll_speed_deg), total)
			if _roll >= total:
				_roll = 0.0
				_set_state(State.LIE)
		State.LIE:
			if _get_up and not mech.is_wrecked and _time >= lie_time:
				_set_state(State.GET_UP)
		State.GET_UP:
			var t := smoothstep(0.0, 1.0, clampf(_time / get_up_time, 0.0, 1.0))
			_angle = PI * 0.5 * (1.0 - t)
			if t >= 1.0:
				_finish()
				return
	visual.transform = _get_transform() * _base


## Tip over a foot edge, lift onto the body surface, roll along the body, sway for the steps.
func _get_transform() -> Transform3D:
	var local := (mech.global_basis.inverse() * _direction)
	local.y = 0.0
	local = local.normalized() if local.length_squared() > 0.001 else Vector3.FORWARD
	var pivot := local * pivot_distance
	var axis := Vector3.UP.cross(local).normalized()
	var tip := Transform3D(Basis(axis, _angle), Vector3.ZERO)
	var result := Transform3D(Basis.IDENTITY, pivot) * tip * Transform3D(Basis.IDENTITY, -pivot)
	var lift := Vector3.UP * lie_lift * sin(_angle)
	result = Transform3D(Basis.IDENTITY, lift) * result
	if _roll != 0.0:
		var center := pivot + Vector3.UP * (pivot_distance + lie_lift)
		result = Transform3D(Basis.IDENTITY, center) * Transform3D(Basis(local, _roll), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -center) * result
	if _sway != 0.0:
		var side := mech.global_basis.inverse() * _step_side
		var sway_axis := Vector3.UP.cross(side.normalized()).normalized()
		result = Transform3D(Basis(sway_axis, _sway), Vector3.ZERO) * result
	return result


func _finish() -> void:
	visual.transform = _base
	state = State.IDLE
	mech.end_fall()
	if animation != null:
		animation.process_mode = Node.PROCESS_MODE_INHERIT
	finished.emit()


func _set_state(next: State) -> void:
	state = next
	_time = 0.0


## One leg left: the mech falls over when the boost stops.
func _watch_boost() -> void:
	var boosting := mech.is_boosting
	if _was_boosting and not boosting and mech.one_leg and not mech.is_wrecked and state == State.IDLE:
		var velocity := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
		var forward := velocity.normalized() if velocity.length() > 0.5 else -mech.global_basis.z
		var broken_side := mech.global_basis.x * (1.0 if mech.broken_leg_side > 0.0 else -1.0)
		var full := velocity.length() >= mech.get_boost_speed() * full_boost_ratio
		fall(forward + broken_side * broken_side_lean, Vector3.ZERO, 2 if full else 0, true)
	_was_boosting = boosting
