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
## Playback speed. 1 = the clip timing.
@export_range(0.05, 4.0) var speed_scale: float = 1.0
## Blend into the clip, in seconds.
@export var blend_in: float = 0.1
## Blend out at the end, in seconds.
@export var blend_out: float = 0.25
## Fist attacks: true when the left fist throws this attack (the next swing of a combo needs that fist).
@export var left_arm: bool = false
## Combo: the swings that follow this one, in order. Each plays only when its input comes in time after
## the swing before hit a target. Empty = a single swing.
@export var follow_ups: Array[MeleeAttack] = []
## Distance between the two mech centers (m) where the strike lands. A target in the aim cone is
## approached until this distance (mechs collide at about 5.2 m).
@export var contact_distance: float = 6.0


## Play time, in seconds.
func get_length() -> float:
	return animation.length / speed_scale


## Travel length, in meters.
func get_distance() -> float:
	return travel.get_meta(&"travel_m", 0.0) if travel != null else 0.0


## Travel direction in model space (+Z forward, +X left).
func get_direction() -> Vector3:
	return travel.get_meta(&"travel_direction", Vector3.BACK) if travel != null else Vector3.BACK


## Start of the first strike window, in seconds of the animation (0 when there is none).
func get_strike_start() -> float:
	return strikes[0].x if strikes.size() > 0 else 0.0


## Middle of the first strike window, in seconds of the animation.
func get_strike_mid() -> float:
	return (strikes[0].x + strikes[0].y) * 0.5 if strikes.size() > 0 else 0.0


## Clip travel from time a to time b (seconds of the animation), in meters along the travel direction.
func get_travel_between(a: float, b: float) -> float:
	if travel == null:
		return 0.0
	var length := animation.length
	return (travel.sample(clampf(b / length, 0.0, 1.0)) - travel.sample(clampf(a / length, 0.0, 1.0))) * get_distance()
