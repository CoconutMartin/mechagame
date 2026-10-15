class_name DeathClip
extends Resource
## One death animation (user request 2026-10-15): a Mixamo clip retargeted onto Sanggigilid
## (tools/godot/retarget_mixamo.gd) and its travel curve. SkeletalDeathAnimation plays it in place of the
## tree fall.

@export var animation: Animation
## Travel along the clip's axis, 0 to 1 over 0 to 1 of the time (from the retarget tool; metadata
## travel_direction in model space, +Z forward, +X left, and travel_m).
@export var travel: Curve
## Playback speed. 1 = the Mixamo timing.
@export_range(0.05, 4.0) var speed_scale: float = 1.0
## How much of the clip's bend and turn plays: 1 = all of the Mixamo motion.
@export_range(0.0, 1.0) var strength: float = 1.0
## Blend from the pose at death into the clip, in seconds.
@export var blend_in: float = 0.15


## Play time, in seconds.
func get_length() -> float:
	return animation.length / speed_scale


## Travel length, in meters.
func get_distance() -> float:
	return travel.get_meta(&"travel_m", 0.0) if travel != null else 0.0


## Travel direction in model space (+Z forward, +X left).
func get_direction() -> Vector3:
	return travel.get_meta(&"travel_direction", Vector3.BACK) if travel != null else Vector3.BACK
