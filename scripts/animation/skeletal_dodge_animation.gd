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
## After the clip the mech slides on (its speed fades, dust from the feet) while the body blends back
## from the clip's last pose over the clip's settle time (user request 2026-10-13: no abrupt end).
## A move key hands the mech back to the player from release_at of the clip on (user request
## 2026-10-13: no wait for the neutral pose): the dodge ends, the mech walks on from its dodge speed
## and the body blends from the clip into the walk over release_fade.
## Shield dash (user request 2026-10-16): with the Hex Shield (WeaponData.blocks_dodge) MechDodge plays
## shield_dash ("Shield_Dash" of models/ual/UAL2_Standard_RM.glb, tools/godot/retarget_mixamo.gd UAL mode)
## instead of a dodge. It always goes forward. ShieldBash can stop it with halt() when the shield hits a mech.
## The arms are not taken from the clips: they keep holding the weapon, and the arm rig moves the
## torso frame (weapons, shield) with the new torso (user request 2026-10-13: no floating weapon).

@export var model: Node3D
@export var mech: Mech
## Moves the torso frame (weapon, shield) with the body after the clip turned it.
@export var arm_rig: SkeletalArmRig
@export var roll: DodgeClip = preload("res://data/dodges/roll.tres")
@export var step_forward: DodgeClip = preload("res://data/dodges/step_forward.tres")
@export var step_left: DodgeClip = preload("res://data/dodges/step_left.tres")
@export var step_right: DodgeClip = preload("res://data/dodges/step_right.tres")
@export var step_back: DodgeClip = preload("res://data/dodges/step_back.tres")
## Hex Shield dash (MechDodge picks it when the shield blocks the dodge).
@export var shield_dash: DodgeClip = preload("res://data/dodges/shield_dash.tres")
## Side roll: the body turns toward the roll during this part of the clip (0 to 1) and turns back
## during the last turn_back part.
@export var turn_in: float = 0.12
@export var turn_back: float = 0.25
## A move key ends the dodge from this part of the clip on (0 to 1; the slide after the clip too).
@export_range(0.0, 1.0) var release_at: float = 0.7
## Seconds for the body to blend from the clip into the walk after a move key ended the dodge.
@export var release_fade: float = 0.35
## From this part of the clip on (0 to 1), a held move key in the dodge direction keeps the dodge at the
## walk speed or faster, so the slow end of a clip (step back) does not dip below the walk it hands over to.
@export_range(0.0, 1.0) var walk_floor_at: float = 0.5

## Bones the clips do not move: the arms keep holding the weapon.
const ARM_BONES: Array[String] = ["upper_arm_L", "forearm_L", "hand_L", "upper_arm_R", "forearm_R", "hand_R"]

## True while a clip plays or the mech settles after it.
var is_playing: bool = false
## The clip that plays now (null when none).
var clip: DodgeClip

var _time: float = 0.0
## Seconds since the clip ended (the slide and settle).
var _after: float = 0.0
## Ground speed kept from the clip (m/s): it fades slower than the clip's own speed.
var _momentum: float = 0.0
## True after halt(): the clip goes on but the mech no longer moves.
var _halted: bool = false
var _distance: float = 0.0
## World direction and body turn (radians, positive = left) of this dodge.
var _direction: Vector3 = Vector3.ZERO
var _turn: float = 0.0
## Clip -> [[track, type, bone name], ...].
var _tracks := {}
var _finished_callback: Callable
## After a move key ended the dodge: the clip pose fades out while the mech walks.
var _fading: bool = false
var _fade_from: float = 0.0
var _fade_left: float = 0.0


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	for each: DodgeClip in [roll, step_forward, step_left, step_right, step_back, shield_dash]:
		if each == null:
			continue
		var list := []
		for track in each.animation.get_track_count():
			var path := each.animation.track_get_path(track)
			var bone := String(path.get_concatenated_subnames())
			if bone not in ARM_BONES:
				list.append([track, each.animation.track_get_type(track), bone])
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


## Starts a clip. finished is called once when it ends. speed_factor scales the dodge length and so
## its ground speed (the clip timing stays; 0.5 = half the speed, for a heavily compromised leg).
func start(chosen: DodgeClip, local_direction: Vector3, from_boost: bool, finished: Callable,
		speed_factor: float = 1.0) -> void:
	clip = chosen
	is_playing = true
	_fading = false
	_time = 0.0
	_after = 0.0
	_momentum = 0.0
	_halted = false
	_distance = (clip.boost_distance if from_boost else clip.distance) * speed_factor
	_direction = (mech.global_basis * local_direction).normalized()
	# Model space: the mech's left (-X in the leg frame) is +X, reached by turning +90 degrees.
	_turn = 0.0
	if clip.turn_to_direction and absf(local_direction.x) > 0.5:
		_turn = PI * 0.5 if local_direction.x < 0.0 else -PI * 0.5
	_finished_callback = finished


## True while the shield dash clip plays or the mech settles after it.
func is_shield_dash() -> bool:
	return is_playing and clip != null and clip == shield_dash


## Ground speed of the dodge now, in m/s.
func get_speed() -> float:
	return 0.0 if _halted else _momentum


## Stops the mech at once (the shield bash hit a mech). The clip and its settle go on.
func halt() -> void:
	_halted = true
	_momentum = 0.0
	mech.root_motion_velocity = Vector3.ZERO


## True while the mech slides on after the clip (the feet throw dust).
func is_sliding() -> bool:
	return is_playing and _after > 0.0 and _momentum > 2.0


func _physics_process(delta: float) -> void:
	if _fading:
		_time = minf(_time + delta * clip.speed_scale, clip.animation.length)
		_fade_left = maxf(_fade_left - delta, 0.0)
		_fading = _fade_left > 0.0
		return
	if not is_playing:
		return
	if _wants_release():
		_release()
		return
	var length := clip.animation.length
	var clip_speed := 0.0
	if _time < length:
		var before := _time
		_time = minf(_time + delta * clip.speed_scale, length)
		clip_speed = (clip.travel.sample(_time / length) - clip.travel.sample(before / length)) * _distance / maxf(delta, 0.0001)
	else:
		_after += delta
	# The mech keeps its speed: the clip can slow down faster than the momentum fades.
	_momentum = maxf(clip_speed, _momentum * exp(-delta / maxf(clip.slide_time, 0.01)))
	_momentum = maxf(_momentum, _get_walk_floor())
	if _halted:
		_momentum = 0.0
	mech.root_motion_active = true
	mech.root_motion_velocity = _direction * _momentum
	if _after >= clip.settle_time or mech.is_fallen or mech.is_wrecked:
		is_playing = false
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO
		if _finished_callback.is_valid():
			_finished_callback.call()


## Walk speed of a held move key that points the way of the dodge, after walk_floor_at of the clip (else 0).
func _get_walk_floor() -> float:
	if _halted or _time < clip.animation.length * walk_floor_at:
		return 0.0
	var wish := mech.input.move_direction
	if wish.length_squared() < 0.01 or wish.normalized().dot(_direction) < 0.5:
		return 0.0
	return mech.get_key_walk_speed()


## A move key after release_at of the clip, while the mech can walk.
func _wants_release() -> bool:
	return mech.input.move_direction.length_squared() > 0.01 and _time >= clip.animation.length * release_at \
			and mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked


## Ends the dodge for the walk: the mech keeps its dodge speed (Mech walks on from it) and the body
## blends out of the clip over release_fade.
func _release() -> void:
	_fade_from = _weight()
	_fade_left = release_fade
	_fading = release_fade > 0.0
	is_playing = false
	mech.root_motion_active = false
	if _finished_callback.is_valid():
		_finished_callback.call()


func _weight() -> float:
	if _fading:
		return _fade_from * _fade_left / maxf(release_fade, 0.01)
	if not is_playing:
		return 0.0
	var blend_in := clampf(_time / (clip.blend_in * clip.speed_scale), 0.0, 1.0)
	return blend_in * (1.0 - _after / maxf(clip.settle_time, 0.01))


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
		amount *= 1.0 - smoothstep(0.0, 1.0, _after / maxf(clip.settle_time, 0.01))
		if _fading:
			amount *= _fade_left / maxf(release_fade, 0.01)
		var root := skeleton.find_bone("root")
		var yaw := Quaternion(Vector3.UP, _turn * amount * weight)
		skeleton.set_bone_pose_rotation(root, yaw * skeleton.get_bone_pose_rotation(root))
		skeleton.set_bone_pose_position(root, yaw * skeleton.get_bone_pose_position(root))
	if arm_rig != null:
		arm_rig.refresh_torso()
