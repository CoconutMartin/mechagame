class_name SkeletalStaggerAnimation
extends SkeletonModifier3D
## Stuns and knock-downs (user request 2026-10-15): retargeted Mixamo clips (ActionClip). User rules:
##   Stun: 300 damage or more to the head and center torso in one hit (one frame), or a pile bunker
##   hit to a torso part: "Receive torso punch" (a stagger; the mech stays standing).
##   Knock-down: 500 damage or more in one hit, or a blast while the mech is in the air. The fall
##   comes from the hit direction: from the front (or not known) the mech falls on its back
##   ("Stunned"); from behind it falls face down (the fall of "Dying - central torso destroyed");
##   while kneeling it falls on its back ("Hit while kneeling, on back"). Then it gets up with the
##   matching clip ("Getting Up", 2 x speed).
## While a stun or knock-down plays the mech cannot move, fire, dodge or jump (Mech.start_fall; it
## stands still). The wreck moves along each clip's travel. Hits on a mech that is down play nothing.
## Runs before the hit animation (process priority): the hit clip sees Mech.is_fallen and stays out.
## A kneeling mech is not stunned (only knocked down).
## On death the pose holds; a mech that is down plays no death clip (SkeletalDeath).

@export var model: Node3D
@export var mech: Mech
@export var health: MechHealth
## Moves the torso frame (weapon, shield) with the body.
@export var arm_rig: SkeletalArmRig
@export_group("Clips")
@export var punch: ActionClip = preload("res://data/stagger/punch.tres")
@export var fall_back: ActionClip = preload("res://data/stagger/fall_back.tres")
@export var fall_forward: ActionClip = preload("res://data/stagger/fall_forward.tres")
@export var fall_kneeling: ActionClip = preload("res://data/stagger/fall_kneeling.tres")
@export var getup_back: ActionClip = preload("res://data/stagger/getup_back.tres")
@export var getup_face_down: ActionClip = preload("res://data/stagger/getup_face_down.tres")
@export_group("Rules")
## Damage to the head and center torso in one frame that stuns.
@export var stun_damage: float = 300.0
## Damage in one frame (all parts) that knocks the mech down.
@export var knock_damage: float = 500.0
## A knock-down hit from inside this angle around the mech's back (degrees) is "from behind".
@export var behind_angle_deg: float = 60.0

## True while the mech is on the ground (a knock-down fall or the get-up).
var is_down: bool = false

## Clips that play one after the other (the fall, then the get-up).
var _queue: Array[ActionClip] = []
var _clip: ActionClip
var _time: float = 0.0
## The clip before this one and its time, held while the new clip blends in.
var _from_clip: ActionClip
var _from_time: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _frozen: bool = false
## A knock-down from the kneel: MechKneel stands once the fall clip has the full body.
var _stand_after_blend: bool = false
## Damage this frame.
var _frame_total: float = 0.0
var _frame_core: float = 0.0
var _frame_punch: bool = false
var _frame_blast: bool = false
## Clip -> [[track, type, bone name], ...].
var _tracks := {}


func _ready() -> void:
	# Before the hit animation and the Mech: they read this frame's stagger.
	process_physics_priority = -2
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	for each: ActionClip in [punch, fall_back, fall_forward, fall_kneeling, getup_back, getup_face_down]:
		if each == null or _tracks.has(each):
			continue
		var list := []
		for track in each.animation.get_track_count():
			var bone := String(each.animation.track_get_path(track).get_concatenated_subnames())
			if bone not in SkeletalDodgeAnimation.ARM_BONES:
				list.append([track, each.animation.track_get_type(track), bone])
		_tracks[each] = list
	health.damaged.connect(_on_damaged)


## True while a stun or knock-down plays (the hit animation stays out).
func is_staggered() -> bool:
	return _clip != null and not _frozen


func _on_damaged(key: String, amount: float) -> void:
	_frame_total += amount
	if key == "Head" or key == "Torso C":
		_frame_core += amount
	if health.last_hit_kind == &"punch" and key.begins_with("Torso"):
		_frame_punch = true
	if health.last_hit_kind == &"blast":
		_frame_blast = true


func _physics_process(delta: float) -> void:
	if _frozen:
		return
	if mech.is_wrecked:
		_frozen = true
		_clear_frame()
		return
	_decide()
	if _clip == null:
		return
	var length := _clip.animation.length
	var before := _time
	_time = minf(_time + delta * _clip.speed_scale, length)
	if _clip.travel != null:
		var speed := (_clip.travel.sample(_time / length) - _clip.travel.sample(before / length)) * _clip.get_distance() / maxf(delta, 0.0001)
		# Mech._update_wreck takes the slide deceleration off before it moves: add it back.
		speed += mech.fallen_slide_deceleration * delta if speed > 0.0 else 0.0
		mech.velocity.x = _direction.x * speed
		mech.velocity.z = _direction.z * speed
	if _stand_after_blend and _blend_in() >= 1.0:
		_stand_after_blend = false
		mech.kneel.stand_now()
	if _time >= length:
		_next()


## Starts a stun or a knock-down from this frame's damage.
func _decide() -> void:
	var knock := _frame_total >= knock_damage or (_frame_blast and not mech.is_on_floor())
	var stun := _frame_core >= stun_damage or _frame_punch
	_clear_frame()
	if is_down or (not knock and not stun):
		return
	if knock:
		if mech.kneel != null and mech.kneel.is_kneeling:
			# The kneel ends once the fall clip has blended in (no pop to the standing pose).
			_stand_after_blend = true
			_start([fall_kneeling, getup_back], true)
		elif health.last_hit_from_behind(behind_angle_deg):
			_start([fall_forward, getup_face_down], true)
		else:
			_start([fall_back, getup_back], true)
	elif _clip == null and mech.is_on_floor() and not (mech.kneel != null and mech.kneel.is_kneeling):
		_start([punch], false)


func _clear_frame() -> void:
	_frame_total = 0.0
	_frame_core = 0.0
	_frame_punch = false
	_frame_blast = false


func _start(clips: Array[ActionClip], down: bool) -> void:
	_from_clip = _clip
	_from_time = _time
	_queue = clips.duplicate()
	is_down = down
	mech.start_fall()
	mech.velocity.x = 0.0
	mech.velocity.z = 0.0
	_play(_queue.pop_front())


func _play(clip: ActionClip) -> void:
	_clip = clip
	_time = 0.0
	# Model space (+Z forward, +X left) to the leg frame (-Z forward, +X right), as the dodge does.
	var model_direction := clip.get_direction()
	_direction = mech.global_basis * Vector3(-model_direction.x, 0.0, -model_direction.z)
	_direction.y = 0.0
	_direction = _direction.normalized()


## The clip ended: the next one blends in from its last pose, or the mech is free again.
func _next() -> void:
	if not _queue.is_empty():
		_from_clip = _clip
		_from_time = _time
		_play(_queue.pop_front())
		return
	_clip = null
	_from_clip = null
	is_down = false
	mech.end_fall()


## Weight of the clip over the pose before it (the held previous clip, or the normal pose).
func _blend_in() -> float:
	return clampf(_time / _clip.speed_scale / maxf(_clip.blend_in, 0.01), 0.0, 1.0)


## Weight of the clips over the normal pose (it fades at the end of the last clip).
func _weight() -> float:
	if _clip == null:
		return 0.0
	var weight := 1.0
	if _from_clip == null:
		weight = _blend_in()
	if _queue.is_empty() and _clip.blend_out > 0.0 and not _frozen:
		var left := (_clip.animation.length - _time) / _clip.speed_scale
		weight *= clampf(left / _clip.blend_out, 0.0, 1.0)
	return weight


func _process_modification_with_delta(_delta: float) -> void:
	var weight := smoothstep(0.0, 1.0, _weight())
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	var from_blend := 1.0 - smoothstep(0.0, 1.0, _blend_in()) if _from_clip != null else 0.0
	for entry: Array in _tracks[_clip]:
		var bone := skeleton.find_bone(entry[2])
		if bone < 0:
			continue
		if entry[1] == Animation.TYPE_ROTATION_3D:
			var rotation := _rotation(skeleton, bone, entry[2], _clip, entry[0], _time)
			if from_blend > 0.0:
				var from_track := _clip_track(_from_clip, entry[2], Animation.TYPE_ROTATION_3D)
				if from_track >= 0:
					rotation = rotation.slerp(_rotation(skeleton, bone, entry[2], _from_clip, from_track, _from_time), from_blend)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotation, weight))
		elif entry[1] == Animation.TYPE_POSITION_3D:
			var position := _position(skeleton, bone, _clip, entry[0], _time)
			if from_blend > 0.0:
				var from_track := _clip_track(_from_clip, entry[2], Animation.TYPE_POSITION_3D)
				if from_track >= 0:
					position = position.lerp(_position(skeleton, bone, _from_clip, from_track, _from_time), from_blend)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(position, weight))
	if arm_rig != null:
		arm_rig.refresh_torso()


func _rotation(skeleton: Skeleton3D, bone: int, bone_name: String, clip: ActionClip, track: int, time: float) -> Quaternion:
	var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var rotation := rest.slerp(clip.animation.rotation_track_interpolate(track, time), clip.strength)
	return clip.limits.clamp_rotation(bone_name, rest, rotation) if clip.limits != null else rotation


func _position(skeleton: Skeleton3D, bone: int, clip: ActionClip, track: int, time: float) -> Vector3:
	return skeleton.get_bone_rest(bone).origin.lerp(clip.animation.position_track_interpolate(track, time), clip.strength)


func _clip_track(clip: ActionClip, bone_name: String, type: int) -> int:
	for entry: Array in _tracks[clip]:
		if entry[2] == bone_name and entry[1] == type:
			return entry[0]
	return -1
