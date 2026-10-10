class_name SkeletalMoves
extends Node
## Plays the run start and the run stops of a rigged mech (SkeletalMoveClip) over SkeletalLocomotion,
## and moves the mech at the body speed made for each animation, so the planted feet stay on the ground.
## Run start: Shift + a move key from a standstill. At its end the run cycle and the boost carry on.
## Stops: the ground boost ends with no W held (Mech.boost_exit_style ANIMATION). A held = Akira slide to
## the left, D held = Akira slide to the right, neither = run stop. Each stop starts from the run on one
## foot, so the mech runs on until that foot lands (each plain stop exists for both feet), for up to
## max_wait seconds. After the slide a move key ends the stop, except the side key that chose it.

@export var mech: Mech
@export var input: MechInput
@export var locomotion: SkeletalLocomotion
## Optional. The hips keep their turn during a stop.
@export var hip_turn: SkeletalHipTurn
@export var run_start: SkeletalMoveClip
## Plain run stops (one for each foot). The first one whose foot comes next plays.
@export var run_stops: Array[SkeletalMoveClip] = []
@export var akira_left: SkeletalMoveClip
@export var akira_right: SkeletalMoveClip
## Run start only below this ground speed (m/s).
@export var start_max_speed: float = 1.0
## Frames in one run cycle (the stride phase 0 to 1 of SkeletalLocomotion).
@export var run_cycle_frames: float = 30.0
## A side key (A / D) counts as held above this input value.
@export_range(0.0, 1.0) var side_input: float = 0.5
## Longest run-on (seconds) while a stop waits for its foot. Then it starts from its first frame.
@export var max_wait: float = 0.35
## Blend-in time (seconds) of a stop that did not wait for its foot.
@export var forced_blend_in: float = 0.3

## The clip that plays now (null = none).
var clip: SkeletalMoveClip
## Frame of the clip now.
var frame: float = 0.0

var _rate: float = 1.0
var _direction: Vector3 = Vector3.ZERO
var _waiting: Array[SkeletalMoveClip] = []
var _shown: SkeletalMoveClip
var _shown_time: float = 0.0
var _weight: float = 0.0
var _waited: float = 0.0
var _side: float = 0.0
var _blend_in: float = 0.15


func _ready() -> void:
	# After MechInput (-10), before the Mech (0): the Mech moves at this frame's clip speed.
	process_physics_priority = -5
	mech.boost_exit_step.connect(_on_boost_exit)


func _physics_process(delta: float) -> void:
	if clip == null and _waiting.is_empty() and _can_start():
		_play(run_start, 0.0, mech.get_boost_speed())
	if not _waiting.is_empty():
		_update_waiting(delta)
	if clip != null:
		_update_clip(delta)
	if _shown != null:
		var blend := _blend_in if clip != null else _shown.blend_out
		var target := 1.0 if clip != null else 0.0
		_weight = move_toward(_weight, target, delta / maxf(blend, 0.01))
		locomotion.set_action(_shown.animation, _shown_time, _weight)
		if _weight <= 0.0:
			_shown = null


func _blocked() -> bool:
	return not mech.is_on_floor() or mech.is_wrecked or mech.is_fallen or mech.is_bracing \
			or mech.is_lunging or mech.dodge.is_busy() or mech.kneel.is_kneeling \
			or mech.jump_charge.is_charging


func _has_move() -> bool:
	return input.move_direction.length_squared() > 0.01


## A move key that is not backward (the run start runs forward or to the side).
func _forward_move() -> bool:
	if not _has_move():
		return false
	var local := mech.global_basis.inverse() * input.move_direction
	return local.z < 0.17


## A move key other than the side key held since the stop started.
func _new_move() -> bool:
	if not _has_move():
		return false
	var side_only := absf(input.turn_input) > side_input and not input.forward_held \
			and absf((mech.global_basis.inverse() * input.move_direction).z) < 0.3
	return not (side_only and signf(input.turn_input) == _side)


func _can_start() -> bool:
	return run_start != null and input.boost_held and _forward_move() and mech.can_boost \
			and mech.get_horizontal_speed() < start_max_speed and not _blocked() \
			and not mech.landing_recovery.is_recovering()


func _on_boost_exit() -> void:
	if clip != null or not _waiting.is_empty() or input.forward_held:
		return
	if hip_turn != null and hip_turn.is_backward:
		return
	_waiting.clear()
	_waited = 0.0
	_side = 0.0
	if input.turn_input > side_input and akira_left != null:
		_waiting.append(akira_left)
		_side = 1.0
	elif input.turn_input < -side_input and akira_right != null:
		_waiting.append(akira_right)
		_side = -1.0
	else:
		_waiting.append_array(run_stops)
	if _waiting.is_empty():
		return
	var velocity := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	_direction = velocity.normalized()
	_hold(velocity)


## Runs on at the exit speed until a waiting stop's foot lands, then starts it there.
func _update_waiting(delta: float) -> void:
	if _blocked():
		_waiting.clear()
		_release()
		return
	var phase := locomotion.get_phase()
	for stop in _waiting:
		var late := fposmod(phase - stop.start_phase, 1.0) * run_cycle_frames
		if late <= stop.start_window:
			_waiting.clear()
			_play(stop, late, mech.get_horizontal_speed())
			return
	_waited += delta
	if _waited >= max_wait:
		var stop: SkeletalMoveClip = _waiting[0]
		_waiting.clear()
		_play(stop, 0.0, mech.get_horizontal_speed())
		_blend_in = forced_blend_in


func _play(next: SkeletalMoveClip, start_frame: float, speed: float) -> void:
	clip = next
	frame = start_frame
	_rate = speed / clip.made_for_speed
	_blend_in = clip.blend_in
	if clip.ends_in_run:
		_direction = input.move_direction.normalized()
	_shown = clip
	if hip_turn != null:
		hip_turn.hold = clip.hold_hips


func _update_clip(delta: float) -> void:
	var cancel := _blocked()
	if clip.ends_in_run:
		cancel = cancel or not input.boost_held or not _forward_move()
		if not cancel:
			_direction = input.move_direction.normalized()
	elif clip.cancel_frame >= 0.0 and frame >= clip.cancel_frame and _new_move():
		cancel = true
	if cancel:
		_finish(false)
		return
	var before := frame
	frame += delta * clip.fps * _rate
	var speed := clip.get_body_speed(frame) * _rate
	for step in clip.footstep_frames:
		if before < step and frame >= step:
			locomotion.footstep.emit(clampf(speed / mech.walk_speed, 0.4, 1.0))
	_shown_time = minf(frame, clip.get_frame_count()) / clip.fps
	if frame >= clip.get_frame_count():
		_finish(true)
		return
	_hold(_direction * speed)


func _finish(done: bool) -> void:
	if done and clip.ends_in_run:
		# The last frame of the run start is the first frame of the run cycle.
		locomotion.sync_to(0.0)
	clip = null
	_release()


func _hold(velocity: Vector3) -> void:
	mech.motion_override = velocity
	mech.motion_override_active = true
	mech.boost_blocked = true
	if hip_turn != null and clip == null:
		hip_turn.hold = true


func _release() -> void:
	mech.motion_override_active = false
	mech.boost_blocked = false
	if hip_turn != null:
		hip_turn.hold = false
