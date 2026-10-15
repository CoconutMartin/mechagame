class_name ActionClip
extends Resource
## One stagger, knock-down or get-up animation (user request 2026-10-15): a Mixamo clip retargeted
## onto Sanggigilid (tools/godot/retarget_mixamo.gd). SkeletalStaggerAnimation plays it.

@export var animation: Animation
## Travel along the clip's axis (from the retarget tool; null = the mech stays in place).
@export var travel: Curve
## Playback speed. 1 = the Mixamo timing.
@export_range(0.05, 4.0) var speed_scale: float = 1.0
## How much of the clip's bend and turn plays: 1 = all of the Mixamo motion.
@export_range(0.0, 1.0) var strength: float = 1.0
## How far the clip can bend and twist each joint (null = no limits).
@export var limits: JointLimits
## Blend into the clip from the pose before it, in seconds.
@export var blend_in: float = 0.15
## Blend out of the clip at its end, in seconds (0 = the next clip or the held pose takes over).
@export var blend_out: float = 0.0


## Play time, in seconds.
func get_length() -> float:
	return animation.length / speed_scale


## Travel length, in meters.
func get_distance() -> float:
	return travel.get_meta(&"travel_m", 0.0) if travel != null else 0.0


## Travel direction in model space (+Z forward, +X left).
func get_direction() -> Vector3:
	return travel.get_meta(&"travel_direction", Vector3.BACK) if travel != null else Vector3.BACK
