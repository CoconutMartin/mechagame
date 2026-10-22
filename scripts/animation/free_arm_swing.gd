class_name FreeArmSwing
extends Node
## An empty hand moves (user request 2026-10-15: "the empty left arm just hangs without movement").
## Mech adds it at runtime; it finds the WeaponController and SkeletalLocomotion of its mech.
## Clip arm swing (user request 2026-10-18; it replaces the whole-arm swing about the shoulder of the same
## day): a relaxed arm (a free or fist hand at its hang marker) takes the arm turns of the Mixamo clip
## "Slow Run - arm swing" (data/animations/arm_swing_run.res, arms only, made by
## tools/godot/retarget_mixamo.gd in arms mode). The clip is locked to the stride: clip time 0 is the left
## foot landing (SkeletalLocomotion phase 0), so the left arm swings forward with the right leg and the clip
## plays faster or slower with the steps. amount (0 standing, 1 at full_speed_share of the walk speed)
## blends the arm from the hang to the clip, so a slow walk swings less. SkeletalArmRig applies it after
## it solved the arm to the still hang marker.
## Heavy arm (user report 2026-10-22: "the left arm makes a pounding motion while walking, it bounces like it's
## not a mech's arm"): the arm no longer takes the clip's pose (a runner's bent elbow and kicking forearm). It
## keeps its hang pose and swings about it by a small share of the clip's turn away from its own mean
## (upper_arm_share, forearm_share, wrist_share), averaged over a part of the stride (smooth_window), so the
## swing is slow and even with no kick at the foot landings.
## Standing: the small idle sway about the shoulder (left_angle, right_angle) stays; it fades out as the
## clip fades in.

@export var mech: Mech
@export var locomotion: SkeletalLocomotion
@export var weapons: WeaponController
## Arm turns (tracks "MechRig/Skeleton3D:<bone>", local rotations under the torso), time 0 = the left
## foot lands, one stride long.
@export var clip: Animation = preload("res://data/animations/arm_swing_run.res")
## Ground speed, as a part of the walk speed, at which the clip arms are fully on (less speed: a smaller
## swing, nearer the hang).
@export var full_speed_share: float = 1.0
## Shift of the clip against the stride (part of a stride; + = the arms later).
@export var phase_shift: float = 0.0
## Extra shift of the right arm: the source clip's right arm swings forward about a quarter stride before
## its left foot lands (its left arm: with the right foot landing). 0.22 puts the right arm forward with
## the left leg (render check 2026-10-18).
@export var right_phase_shift: float = 0.22
## Idle sway while standing, in degrees about the shoulder, and its speed in cycles per second.
@export var idle_sway_deg: float = 1.2
@export var idle_sway_speed: float = 0.3
## How fast the clip amount follows the speed (per second).
@export var blend_speed: float = 4.0

@export_group("Heavy arm")
## Part of the clip's swing that each arm bone keeps (1 = the whole clip swing about its mean, 0 = none):
## upper arm (forward and back), forearm (elbow bend), wrist. The clip swings the upper arm 20 deg and bends
## the elbow 30 deg each way.
@export_range(0.0, 1.0) var upper_arm_share: float = 0.3
@export_range(0.0, 1.0) var forearm_share: float = 0.12
@export_range(0.0, 1.0) var wrist_share: float = 0.1
## The clip is averaged over this part of a stride on each side of now (0 = the raw clip): the quick kicks
## at the foot landings go, the swing is slow and even.
@export_range(0.0, 0.5) var smooth_window: float = 0.15
@export_range(1, 15) var smooth_samples: int = 7
@export_group("")

## How much of the clip the relaxed arms take now (0 = the hang, 1 = the clip).
var amount: float = 0.0
## Idle sway of each relaxed arm now (radians about the torso's right axis; forward is positive).
var left_angle: float = 0.0
var right_angle: float = 0.0

var _time: float = 0.0
## Bone name -> rotation track of the clip.
var _tracks: Dictionary = {}
## Bone name -> the clip's mean rotation over the stride (the swing is the turn away from it).
var _means: Dictionary = {}


func _ready() -> void:
	if mech == null:
		mech = get_parent() as Mech
	if mech == null:
		return
	if weapons == null:
		weapons = mech.find_child("WeaponController", true, false) as WeaponController
	if locomotion == null:
		for node in mech.find_children("*", "", true, false):
			if node is SkeletalLocomotion:
				locomotion = node as SkeletalLocomotion
				break
	if clip != null:
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				var bone := StringName(clip.track_get_path(track).get_concatenated_subnames())
				_tracks[bone] = track
				_means[bone] = _mean_rotation(track)


func _physics_process(delta: float) -> void:
	if mech == null:
		return
	_time += delta
	var walking := mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked
	var target := clampf(mech.get_horizontal_speed() / maxf(mech.walk_speed * full_speed_share, 0.1), 0.0, 1.0) \
			if walking else 0.0
	amount = move_toward(amount, target, blend_speed * delta)
	left_angle = _idle(0.0)
	right_angle = _idle(0.5)


## The local rotation of a bone of the right or left arm now: fallback (the hang pose) with the clip's heavy
## swing on top (the smoothed turn of the clip away from its mean, scaled by the bone's share), or fallback
## when the clip has no track for the bone.
func arm_rotation(bone: StringName, fallback: Quaternion, right: bool) -> Quaternion:
	if clip == null or not _tracks.has(bone):
		return fallback
	var swing := _swing(bone, clip_time(right))
	return Quaternion.IDENTITY.slerp(swing, _share(bone)) * fallback


## Clip time of an arm at the stride phase now (phase 0, the left foot landing, is clip time 0).
func clip_time(right: bool) -> float:
	var phase := locomotion.get_phase() if locomotion != null else 0.0
	var shift := phase_shift + (right_phase_shift if right else 0.0)
	return fposmod(phase - shift, 1.0) * clip.length


## One arm's idle sway (radians); offset (0 to 1) shifts it in time.
func _idle(offset: float) -> float:
	return deg_to_rad(sin(TAU * (_time * idle_sway_speed + offset)) * idle_sway_deg * (1.0 - amount))


## Share of the clip swing that a bone keeps (upper arm, forearm or wrist).
func _share(bone: StringName) -> float:
	if String(bone).begins_with("upper_arm"):
		return upper_arm_share
	if String(bone).begins_with("forearm"):
		return forearm_share
	return wrist_share


## The clip's turn away from its mean at a clip time, averaged over smooth_window of the stride around it.
func _swing(bone: StringName, time: float) -> Quaternion:
	var track: int = _tracks[bone]
	var mean: Quaternion = _means[bone]
	var count := maxi(smooth_samples, 1) if smooth_window > 0.0 else 1
	var sum := Vector4.ZERO
	for i in count:
		var offset := 0.0 if count == 1 else lerpf(-smooth_window, smooth_window, float(i) / float(count - 1))
		var at := fposmod(time / clip.length + offset, 1.0) * clip.length
		var turn := clip.rotation_track_interpolate(track, at) * mean.inverse()
		if turn.w < 0.0:
			turn = -turn
		sum += Vector4(turn.x, turn.y, turn.z, turn.w)
	return Quaternion(sum.x, sum.y, sum.z, sum.w).normalized()


## The mean rotation of a track over the whole clip (the rotations are averaged as 4D vectors; the clip's
## turns are small enough for that).
func _mean_rotation(track: int) -> Quaternion:
	var first := clip.rotation_track_interpolate(track, 0.0)
	var sum := Vector4.ZERO
	var steps := 48
	for i in steps:
		var q := clip.rotation_track_interpolate(track, clip.length * float(i) / float(steps))
		if q.dot(first) < 0.0:
			q = -q
		sum += Vector4(q.x, q.y, q.z, q.w)
	return Quaternion(sum.x, sum.y, sum.z, sum.w).normalized()
