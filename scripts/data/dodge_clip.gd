class_name DodgeClip
extends Resource
## One dodge animation (user request 2026-10-13): a Mixamo clip retargeted onto Sanggigilid
## (tools/godot/retarget_mixamo.gd), its travel curve and how it plays. SkeletalDodgeAnimation plays it.

@export var animation: Animation
## Travel along the clip's axis, 0 to 1 over 0 to 1 of the time (from the retarget tool).
@export var travel: Curve
## Playback speed. 1 = the Mixamo timing.
@export var speed_scale: float = 1.0
## Dodge length, in meters.
@export var distance: float = 12.0
## Dodge length when the dodge starts while boosting, in meters.
@export var boost_distance: float = 18.0
## True for a forward-only clip (the roll) used for side dodges too: the body turns toward the dodge
## at the start and back at the end.
@export var turn_to_direction: bool = false
## Blend into the clip, in seconds of clip time.
@export var blend_in: float = 0.12
## After the clip: the mech slides on (its speed fades with this time constant, in seconds) while the
## body blends from the clip's last pose back to the normal pose over settle_time seconds.
@export var slide_time: float = 0.35
@export var settle_time: float = 0.8


## Play time, in seconds.
func get_length() -> float:
	return animation.length / speed_scale
