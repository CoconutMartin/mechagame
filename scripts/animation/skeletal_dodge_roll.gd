class_name SkeletalDodgeRoll
extends SkeletonModifier3D
## Dodge roll for light and medium mechs (user request 2026-10-13): a forward or side dodge plays a
## roll retargeted from Mixamo "Stand To Roll" (tools/godot/retarget_mixamo.gd) instead of the hop.
## The back dodge keeps the hop. Runs after every other bone modifier, so the roll has the whole body.
## The roll plays in place; the mech moves along the animation's own travel curve (root motion), so
## the body and the ground speed match. A side roll turns the body toward the roll at the start and
## back at the end.

@export var model: Node3D
@export var mech: Mech
@export var animation: Animation = preload("res://data/animations/dodge_roll.res")
## Forward travel of the animation, 0 to 1 over its time (from the retarget tool).
@export var travel: Curve = preload("res://data/animations/dodge_roll_travel.tres")
## Playback speed. 1 = the Mixamo timing (2.37 s).
@export var speed_scale: float = 1.3
## Roll length, in meters.
@export var distance: float = 15.0
## Roll length for a roll that starts while boosting, in meters.
@export var boost_distance: float = 22.0
## Blend into and out of the roll, in seconds of roll time.
@export var blend_in: float = 0.12
@export var blend_out: float = 0.35
## Side roll: the body turns toward the roll during this part of the roll (0 to 1) and turns back
## during the last turn_back part.
@export var turn_in: float = 0.12
@export var turn_back: float = 0.25

## True while the roll plays.
var is_rolling: bool = false

var _time: float = 0.0
var _distance: float = 0.0
## World direction and body turn (radians, positive = left) of this roll.
var _direction: Vector3 = Vector3.ZERO
var _turn: float = 0.0
var _tracks: Array = []
var _finished_callback: Callable


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		_tracks.append([track, animation.track_get_type(track), String(path.get_concatenated_subnames())])


## True when this mech may roll in this dodge direction (leg frame: -Z forward, +X right).
func can_roll(local_direction: Vector3) -> bool:
	return local_direction.z < 0.5 and WeightClass.of_mech(mech) != WeightClass.Class.HEAVY


## Starts the roll. finished is called once when it ends.
func start(local_direction: Vector3, from_boost: bool, finished: Callable) -> void:
	is_rolling = true
	_time = 0.0
	_distance = boost_distance if from_boost else distance
	_direction = (mech.global_basis * local_direction).normalized()
	# Model space: the mech's left (-X in the leg frame) is +X, reached by turning +90 degrees.
	_turn = 0.0
	if absf(local_direction.x) > 0.5:
		_turn = PI * 0.5 if local_direction.x < 0.0 else -PI * 0.5
	_finished_callback = finished


func get_length() -> float:
	return animation.length / speed_scale


func _physics_process(delta: float) -> void:
	if not is_rolling:
		return
	var before := _time
	_time = minf(_time + delta * speed_scale, animation.length)
	var moved := (travel.sample(_time / animation.length) - travel.sample(before / animation.length)) * _distance
	mech.root_motion_active = true
	mech.root_motion_velocity = _direction * (moved / maxf(delta, 0.0001))
	if _time >= animation.length or mech.is_fallen or mech.is_wrecked:
		is_rolling = false
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO
		if _finished_callback.is_valid():
			_finished_callback.call()


func _weight() -> float:
	if not is_rolling:
		return 0.0
	var length := animation.length
	return clampf(minf(_time / (blend_in * speed_scale), (length - _time) / (blend_out * speed_scale)), 0.0, 1.0)


func _process_modification_with_delta(_delta: float) -> void:
	var weight := smoothstep(0.0, 1.0, _weight())
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	for entry: Array in _tracks:
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
