class_name AirClip
extends Resource
## One jump, fall or landing clip (user request 2026-10-15): a Mixamo clip retargeted onto Sanggigilid
## (tools/godot/retarget_mixamo.gd). SkeletalJumpPose plays it over the coded jump poses; AirClipBody
## puts the pelvis so the feet stand where the mech stands.

@export var animation: Animation
## Playback speed. 1 = the Mixamo timing.
@export_range(0.05, 4.0) var speed_scale: float = 1.0
## Seconds into the clip where the feet touch the ground (0 = the clip has no touchdown).
@export var contact_time: float = 0.0
## Jump clips: seconds into the clip at the deepest crouch (reached at full charge).
@export var crouch_time: float = 0.0
## Jump clips: seconds into the clip where the feet leave the ground (the end of the push).
@export var takeoff_time: float = 0.0
## Seconds into the clip where the pose holds: a fall holds there while the mech is in the air; a
## landing holds there until the recovery ends. 0 = the end of the clip.
@export var hold_time: float = 0.0
## A part of the clip that is left out (clip seconds cut_from to cut_to; equal = no cut). The times
## given to the clip are then play times with the cut taken out; the two sides cross-fade over
## cut_blend seconds on each side of the cut (AirClipBody.sample).
@export var cut_from: float = 0.0
@export var cut_to: float = 0.0
@export var cut_blend: float = 0.08
## Blend into the clip, in seconds.
@export var blend_in: float = 0.15
## Blend out of the clip, in seconds.
@export var blend_out: float = 0.2
## How far the feet hang above the mech's ground contact while the clip's own feet are high above its
## touchdown (0 = the soles always at the contact height, 1 = the clip's own height; the clip falls
## more than 8 m in 0.3 s, so this is small).
@export_range(0.0, 1.0) var lift_scale: float = 0.0


## The held frame in seconds (play time: the cut taken out).
func get_hold_time() -> float:
	var hold := hold_time if hold_time > 0.0 else animation.length
	if has_cut() and hold > cut_from:
		hold -= minf(hold, cut_to) - cut_from
	return hold


func has_cut() -> bool:
	return cut_to > cut_from
