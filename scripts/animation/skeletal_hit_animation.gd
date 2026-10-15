class_name SkeletalHitAnimation
extends SkeletonModifier3D
## Hit reactions (user request 2026-10-15): Mixamo clips retargeted onto Sanggigilid (HitClip,
## tools/godot/retarget_mixamo.gd) play when the mech takes damage. User rules:
##   The damage of one hit picks the clip (small, medium, large; thresholds in each HitClip). All
##   parts hit in the same frame count as one hit (a missile blast).
##   Full body: the clip has the whole body and the legs stop (the mech stands while it plays). A
##   skid or lunge keeps its slide (Mech ignores root motion then); the clip plays over it.
## A bigger hit restarts the reaction with its bigger clip. A hit of the same size or smaller does not
## restart it; after a clip it plays again only after the cooldown.
## The clip pose is scaled by the clip's strength and held inside the joint limits (user request
## 2026-10-15: the large hit bent and twisted the mech out of shape).
## The arms are not taken from the clips: they keep holding the weapon, and the arm rig moves the
## torso frame (weapons, shield) with the new torso, like the dodge clips.
## A dodge ends the reaction. On death the pose holds while SkeletalDeath topples the body.

@export var model: Node3D
@export var mech: Mech
@export var health: MechHealth
## Moves the torso frame (weapon, shield) with the body after the clip turned it.
@export var arm_rig: SkeletalArmRig
## Optional. No hit clip starts while a melee attack plays (user decision 2026-10-15: the attack
## keeps its step; stuns and knock-downs still end it).
@export var melee: SkeletalMeleeAnimation
## Smallest first.
@export var clips: Array[HitClip] = [
	preload("res://data/hits/small.tres"),
	preload("res://data/hits/medium.tres"),
	preload("res://data/hits/large.tres"),
]
## How far the clip can bend and twist each joint (the clip pose is held inside these limits).
@export var limits: JointLimits = preload("res://data/mechs/sanggigilid_joint_limits.tres")
## Strength of the flinch from the environment (walking through buildings, flying props and debris:
## hit kind &"environment"), 0 to 1 of a normal hit reaction (user request 2026-10-15: about 4%).
## These flinches do not stop the legs.
@export_range(0.0, 1.0) var environment_flinch: float = 0.04
## Seconds after a clip in which a hit of the same size or smaller plays no clip.
@export var cooldown: float = 0.5

## True while a clip plays.
var is_playing: bool = false
## The clip that plays now, or the last one (null before the first hit).
var clip: HitClip

## Clip time, in seconds of the animation.
var _time: float = 0.0
## Damage taken this frame.
var _pending: float = 0.0
## Environment damage taken this frame (a weak flinch, see environment_flinch).
var _pending_environment: float = 0.0
## True while the clip is an environment flinch.
var _environment_only: bool = false
var _cooldown_left: float = 0.0
## Weight when a dodge cut the clip; it fades out over the clip's blend_out.
var _cut_weight: float = 0.0
var _cut_left: float = 0.0
## True after death: the pose holds at this weight.
var _frozen: bool = false
var _frozen_weight: float = 0.0
## Clip -> [[track, type, bone name], ...].
var _tracks := {}


func _ready() -> void:
	if get_skeleton() == null:
		reparent.call_deferred(model.find_child("Skeleton3D", true, false), false)
	for each: HitClip in clips:
		var list := []
		for track in each.animation.get_track_count():
			var bone := String(each.animation.track_get_path(track).get_concatenated_subnames())
			if bone not in SkeletalDodgeAnimation.ARM_BONES:
				list.append([track, each.animation.track_get_type(track), bone])
		_tracks[each] = list
	health.damaged.connect(_on_damaged)


func _on_damaged(_key: String, amount: float) -> void:
	if health.last_hit_kind == &"environment":
		_pending_environment += amount
	else:
		_pending += amount


## The biggest clip for this damage (null when it is too small for every clip).
func pick(damage: float) -> HitClip:
	var chosen: HitClip = null
	for each in clips:
		if damage >= each.min_damage:
			chosen = each
	return chosen


func _physics_process(delta: float) -> void:
	if _frozen:
		return
	if mech.is_wrecked:
		_freeze()
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_cut_left = maxf(_cut_left - delta, 0.0)
	if is_playing and mech.dodge != null and mech.dodge.is_dodging:
		_cut()
	if _pending > 0.0:
		_try_start(pick(_pending), false)
	elif _pending_environment > 0.0:
		_try_start(pick(_pending_environment), true)
	_pending = 0.0
	_pending_environment = 0.0
	if not is_playing:
		return
	if mech.is_fallen:
		_end()
		return
	_time += delta * clip.speed_scale
	if _time >= clip.animation.length:
		_time = clip.animation.length
		_end()
		return
	# Full body: the legs stop (not for a flinch from the environment).
	if not _environment_only:
		mech.root_motion_active = true
		mech.root_motion_velocity = Vector3.ZERO


## environment: the damage came from the environment (a weak flinch; a real hit replaces it).
func _try_start(chosen: HitClip, environment: bool) -> void:
	if chosen == null or mech.is_fallen or not mech.is_on_floor():
		return
	if melee != null and melee.is_playing:
		return
	if mech.dodge != null and mech.dodge.is_dodging:
		return
	if environment and is_playing and not _environment_only:
		return
	var bigger := clip == null or clips.find(chosen) > clips.find(clip) or (_environment_only and not environment)
	if (is_playing or _cooldown_left > 0.0) and not bigger:
		return
	_environment_only = environment
	clip = chosen
	is_playing = true
	_time = 0.0
	_cut_left = 0.0


func _end() -> void:
	is_playing = false
	_cooldown_left = cooldown
	if not _environment_only:
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO


## A dodge started: the dodge owns the body and the root motion now.
func _cut() -> void:
	_cut_weight = _weight()
	_cut_left = clip.blend_out
	is_playing = false
	_cooldown_left = cooldown
	# A dodge clip sets its own root motion; the hop (no clip) needs it off.
	if mech.dodge == null or mech.dodge.animation == null or not mech.dodge.animation.is_playing:
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO


## Death: the pose holds (SkeletalDeath freezes the animation tree and topples the body).
func _freeze() -> void:
	_frozen_weight = _weight()
	_frozen = true
	if is_playing:
		mech.root_motion_active = false
		mech.root_motion_velocity = Vector3.ZERO


func _weight() -> float:
	if clip == null:
		return 0.0
	if _frozen:
		return _frozen_weight
	if not is_playing:
		return _cut_weight * _cut_left / maxf(clip.blend_out, 0.01)
	var seconds := _time / clip.speed_scale
	var left := (clip.animation.length - _time) / clip.speed_scale
	return clampf(seconds / maxf(clip.blend_in, 0.01), 0.0, 1.0) * clampf(left / maxf(clip.blend_out, 0.01), 0.0, 1.0)


func _process_modification_with_delta(_delta: float) -> void:
	var weight := smoothstep(0.0, 1.0, _weight()) * (environment_flinch if _environment_only else 1.0)
	if weight <= 0.0:
		return
	var skeleton := get_skeleton()
	var animation := clip.animation
	for entry: Array in _tracks[clip]:
		var bone := skeleton.find_bone(entry[2])
		if bone < 0:
			continue
		if entry[1] == Animation.TYPE_ROTATION_3D:
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			var rotation := rest.slerp(animation.rotation_track_interpolate(entry[0], _time), clip.strength)
			if limits != null:
				rotation = limits.clamp_rotation(entry[2], rest, rotation)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(rotation, weight))
		elif entry[1] == Animation.TYPE_POSITION_3D:
			var position := skeleton.get_bone_rest(bone).origin.lerp(animation.position_track_interpolate(entry[0], _time), clip.strength)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(position, weight))
	if arm_rig != null:
		arm_rig.refresh_torso()
