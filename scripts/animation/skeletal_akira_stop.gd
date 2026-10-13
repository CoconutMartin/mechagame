class_name SkeletalAkiraStop
extends Node
## Plays the Blender action biped_run_stop_akira (user request 2026-10-13) at the end of a run or boost
## stop with no move key held: the right leg swings out and plants, both feet skid while the body turns
## 90 degrees right, two pivot steps turn it back, three small steps forward, then Idle.
## During the slide (frames 0 to 30) the animation follows the skid: it reaches frame 30 when the mech
## has slid to a stop (Mech.akira_skid). After that it plays in real time and the mech moves with the
## animation's own steps (Mech.root_motion_velocity, step_speeds), so the planted feet stay put.
## A move, boost or jump key stops it (it blends out). SkidBodyTurn stays off while it plays.

@export var mech: Mech
@export var locomotion: SkeletalLocomotion
## Animation time (s) where the slide ends (the slide_end marker).
@export var slide_end_time: float = 1.0
## Body speed of the animation's steps (m/s) by its time (s), measured from the planted feet:
## pairs of (time, speed). It is 0 before the steps.
@export var step_speeds: PackedVector2Array = PackedVector2Array([
		Vector2(1.70, 0.0), Vector2(1.83, 3.75), Vector2(1.93, 3.9), Vector2(2.57, 3.9),
		Vector2(2.63, 3.2), Vector2(2.80, 1.35), Vector2(3.00, 0.0)])
## Footstep times in the animation (s; markers footstep_*): each shakes the camera like a step.
@export var footstep_times: PackedFloat32Array = PackedFloat32Array([0.267, 1.333, 1.667, 1.933, 2.267, 2.6, 2.933])
## Blend in at the start and out at the end or on a key (seconds).
@export var blend_in: float = 0.15
@export var blend_out: float = 0.3

var _active: bool = false
var _time: float = 0.0
var _weight: float = 0.0
var _length: float = 0.0
var _direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	# After the Mech moved this frame (its skid and speed are up to date).
	process_physics_priority = 3
	var player := locomotion.tree.get_node(locomotion.tree.anim_player) as AnimationPlayer
	if player.has_animation(locomotion.stop_animation):
		_length = player.get_animation(locomotion.stop_animation).length


func _physics_process(delta: float) -> void:
	if _length <= 0.0:
		return
	if not _active and mech.akira_skid and mech.is_skidding:
		_active = true
		_time = 0.0
		var flat := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
		_direction = flat.normalized() if flat.length() > 0.1 else -mech.global_basis.z
	if _active:
		_step(delta)
	var target := 0.0
	if _active:
		target = 1.0 if _time < _length - blend_out else (_length - _time) / blend_out
	_weight = move_toward(_weight, target, delta / (blend_in if target > _weight else blend_out))
	mech.akira_playing = _weight > 0.0
	locomotion.stop_weight = smoothstep(0.0, 1.0, _weight)
	locomotion.stop_time = _time


func _step(delta: float) -> void:
	var input := mech.input
	var wants := input.move_direction.length_squared() > 0.01 or input.boost_held or input.jump_held
	if wants or not mech.is_on_floor() or mech.is_fallen or mech.is_wrecked \
			or (mech.is_skidding and not mech.akira_skid):
		_stop()
		return
	var before := _time
	if mech.is_skidding:
		# The slide part follows the skid; it never runs ahead of real time.
		_time = clampf(maxf(_time, mech.get_skid_progress() * slide_end_time), 0.0, minf(before + delta * 3.0, slide_end_time))
	else:
		_time = minf(maxf(_time, slide_end_time) + delta, _length)
		mech.root_motion_active = true
		mech.root_motion_velocity = _direction * _speed_at(_time)
	for t in footstep_times:
		if t > before and t <= _time:
			locomotion.footstep.emit(0.7)
	if _time >= _length:
		_stop()


func _stop() -> void:
	_active = false
	mech.root_motion_active = false
	mech.root_motion_velocity = Vector3.ZERO
	mech.akira_skid = false


func _speed_at(time: float) -> float:
	if step_speeds.is_empty() or time <= step_speeds[0].x:
		return 0.0
	for i in range(1, step_speeds.size()):
		if time <= step_speeds[i].x:
			var a := step_speeds[i - 1]
			var b := step_speeds[i]
			return lerpf(a.y, b.y, (time - a.x) / maxf(b.x - a.x, 0.0001))
	return step_speeds[step_speeds.size() - 1].y
