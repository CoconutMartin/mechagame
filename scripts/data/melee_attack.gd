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
## Fist attacks: true when the left fist throws this attack (the swing needs that fist).
@export var left_arm: bool = false
## Plain fist combo: the plain punches (no move key) that follow this straight punch in a chain, in
## order (the arms alternate). Since 2026-10-18 any attack chains into any other (SkeletalMeleeAnimation);
## a plain press in a chain plays the follow-up for its place and arm. Empty = none.
@export var follow_ups: Array[MeleeAttack] = []
## Distance between the two mech centers (m) where the strike lands. A target in the aim cone is
## approached until this distance (mechs collide at about 5.2 m).
@export var contact_distance: float = 6.0
## Stagger points of this swing as swing 1 or 2 of a chain (user decision 2026-10-18: the hammer swings
## give 25, a flinch, no knock-down; Baton swings 15, user choice 2026-10-18). The S attack and the last
## swing of a full chain use the weapon's points (WeaponData.stagger_points). Below 0 = always the
## weapon's points.
@export var chain_stagger_points: float = -1.0
## During the attack the mech moves no closer than this to another mech (center to center, m), so wide
## swings do not reach into it (user rule 2026-10-15: mechs collide, no clipping). 0 = only the bodies
## collide (about 5.2 m).
@export var keep_away_distance: float = 6.0
## Share of the clip's air height kept (user request 2026-10-30, Pile Bunker clip 3: "reduce liftoff by 80%"): when
## both soles are off the ground the body comes down so they keep this share of their height. 1 = the clip as is.
@export_range(0.0, 1.0) var air_share: float = 1.0
## Share of the clip's crouch kept ("temper the landing by 80%"): when the body sits lower than the standing pose
## (the pose under the clip) it rises by the rest, and the legs bend less so the feet on the ground stay there.
@export_range(0.0, 1.0) var crouch_share: float = 1.0


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
