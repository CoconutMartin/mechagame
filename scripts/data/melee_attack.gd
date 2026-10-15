class_name MeleeAttack
extends Resource
## One melee attack (user request 2026-10-15): a clip retargeted onto Sanggigilid (Mixamo, mirrored
## with tools/godot/mirror_clip.gd, or keyframed) and its strikes. SkeletalMeleeAnimation plays it.

@export var animation: Animation
## Travel along the clip's axis (from the retarget tool; null = the mech stays in place).
@export var travel: Curve
## Strike windows, in seconds of the animation (x = start, y = end). During a window the weapon's
## strike point hits each target once.
@export var strikes: PackedVector2Array = PackedVector2Array([Vector2(0.4, 0.6)])
## Damage of each strike (one value per window).
@export var damage: PackedFloat32Array = PackedFloat32Array([100.0])
## Combo clips: the attack stops here (seconds of the animation) unless the next input came in time.
## 0 = no split.
@export var split_time: float = 0.0
## Playback speed. 1 = the clip timing.
@export_range(0.05, 4.0) var speed_scale: float = 1.0
## Blend into the clip, in seconds.
@export var blend_in: float = 0.1
## Blend out at the end (or at the split), in seconds.
@export var blend_out: float = 0.25


## Play time, in seconds.
func get_length() -> float:
	return animation.length / speed_scale


## Travel length, in meters.
func get_distance() -> float:
	return travel.get_meta(&"travel_m", 0.0) if travel != null else 0.0


## Travel direction in model space (+Z forward, +X left).
func get_direction() -> Vector3:
	return travel.get_meta(&"travel_direction", Vector3.BACK) if travel != null else Vector3.BACK
