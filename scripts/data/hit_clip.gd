class_name HitClip
extends Resource
## One hit reaction (user request 2026-10-15): a Mixamo clip retargeted onto Sanggigilid
## (tools/godot/retarget_mixamo.gd) and the damage that plays it. SkeletalHitAnimation plays it.

@export var animation: Animation
## Damage of one hit (all parts hit in the same frame added up) that plays this clip, or more.
## User thresholds (2026-10-15): small up to 75, medium 76 to 150, large 151 and more.
@export var min_damage: float = 76.0
## How much of the clip's bend and turn plays: 1 = all of the Mixamo motion, 0.5 = half way from
## the rest pose (the pelvis height change too).
@export_range(0.0, 1.0) var strength: float = 1.0
## Playback speed. 1 = the Mixamo timing.
@export_range(0.05, 4.0) var speed_scale: float = 1.0
## Blend into the clip, in seconds.
@export var blend_in: float = 0.08
## Blend out of the clip at its end, in seconds.
@export var blend_out: float = 0.25


## Play time, in seconds.
func get_length() -> float:
	return animation.length / speed_scale
