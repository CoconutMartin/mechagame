class_name SkeletalDodgeAnimation
extends SkeletonModifier3D
## Dodge animations (user requests 2026-10-13): Mixamo clips retargeted onto Sanggigilid
## (DodgeClip, tools/godot/retarget_mixamo.gd) play instead of the dodge hop. Which clip (user rule
## "speed decides"):
##   Forward: light = roll; medium = roll while running or boosting, else step forward; heavy = step.
##   Left / right: light and medium = roll while running or boosting, else side step; heavy = side step.
##   Back: step back for every weight.
## Runs after every other bone modifier, so the clip has the whole body. The clip plays in place; the
## mech moves along the clip's own travel curve (root motion), so the body and the ground speed
## match. The roll is a forward clip: for a side roll the body turns toward the roll and back.

@export var model: Node3D
@export var mech: Mech
@export var roll: DodgeClip = preload("res://data/dodges/roll.tres")
@export var step_forward: DodgeClip = preload("res://data/dodges/step_forward.tres")
@export var step_left: DodgeClip = preload("res://data/dodges/step_left.tres")
@export var step_right: DodgeClip = preload("res://data/dodges/step_right.tres")
@export var step_back: DodgeClip = preload("res://data/dodges/step_back.tres")
## Side roll: the body turns toward the roll during this part of the clip (0 to 1) and turns back
## during the last turn_back part.
@export var turn_in: float = 0.12
@export var turn_back: float = 0.25

## True while a clip plays.
var is_playing: bool = false
## The clip that plays now (null when none).
var clip: DodgeClip

var _time: float = 0.0
var _distance: float = 0.0
## World direction and body turn (radians, positive = left) of this dodge.
var _direction: Vector3 = Vector3.ZERO
var _turn: float = 0.0
## Clip -> [[track, type, bone name], ...].
var _tracks := {}
var _finished_callback: Callable


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	for each: DodgeClip in [roll, step_forward, step_left, step_right, step_back]:
		if each == null:
			continue
		var list := []
		for track in each.animation.get_track_count():
			var path := each.animation.track_get_path(track)
			list.append([track, each.animation.track_get_type(track), String(path.get_concatenated_subnames())])
		_tracks[each] = list


## The clip for this dodge (leg frame: -Z forward, +X right), or null for the hop.
func pick(local_direction: Vector3) -> DodgeClip:
	var weight := WeightClass.of_mech(mech)
	var fast := mech.is_boosting or mech.is_running
	if local_direction.z > 0.5:
		return step_back
	if local_direction.z < -0.5:
		if weight == WeightClass.Class.LIGHT or (weight == WeightClass.Class.MEDIUM and fast):
			return roll
		return step_forward
	if weight != WeightClass.Class.HEAVY and fast:
		return roll
	return step_left if local_direction.x < 0.0 else step_right


## Starts a clip. finished is called once when it ends.
func start(chosen: DodgeClip, local_direction: Vector3, from_boost: bool, finished: Callable) -> void:
	clip = chosen
	is_playing = true
	_time = 0.0
	_distance = clip.boost_distance if from_boost else clip.distance
	_direction = (mech.global_basis * local_direction).normalized()
	# Model space: the mech's left (-X in the leg frame) is +X, reached by turning +90 degrees.
	_turn = 0.0
	if clip.turn_to_direction and absf(local_direction.x) > 0.5:
		_turn = PI * 0.5 if local_direction.x < 0.0 else -PI * 0.5
	_finished_callback = finished


func _physics_process(delta: float) -> void:
	if not is_playing:
		return
	var length := clip.animation.length
	var before := _time
	_time = minf(_time + delta * clip.speed_scale, length)
	var moved := (clip.travel.sample(_time / length) - clip.travel.sample(before / length)) * _distance
	mech.root_motion_active = true
	mech.root_motion_velocity = _direction * (moved / maxf(delta, 0.0001))
	if _time >= length or mech.is_fallen or mech.is_wrecked:
		is_playing = false
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO
		if _finished_callback.is_valid():
			_finished_callback.call()


func _weight() -> float:
	if not is_playing:
		return 0.0
	var length := clip.animation.length
	return clampf(minf(_time / (clip.blend_in * clip.speed_scale), (length - _time) / (clip.blend_out * clip.speed_scale)), 0.0, 1.0)


func _process_modification_with_delta(_delta: float) -> void:
	var weight := smoothstep(0.0, 1.0, _weight())
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	var animation := clip.animation
	for entry: Array in _tracks[clip]:
		var bone := skeleton.find_bone(entry[2])
		if bone < 0:
			continue
		if entry[1] == Animation.TYPE_ROTATION_3D:
			var rotation := animation.rotation_track_interpolate(entry[0], _time)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotation, weight))
		elif entry[1] == Animation.TYPE_POSITION_3D:
			var position := animation.position_track_interpolate(entry[0], _time)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(position, weight))
	if _turn != 0.0:
		var progress := _time / animation.length
		var amount := smoothstep(0.0, turn_in, progress) * (1.0 - smoothstep(1.0 - turn_back, 1.0, progress))
		var root := skeleton.find_bone("root")
		var yaw := Quaternion(Vector3.UP, _turn * amount * weight)
		skeleton.set_bone_pose_rotation(root, yaw * skeleton.get_bone_pose_rotation(root))
		skeleton.set_bone_pose_position(root, yaw * skeleton.get_bone_pose_position(root))
