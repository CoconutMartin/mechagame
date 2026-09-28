class_name FreeAim
extends Node
## Free aim with a dead zone (like the arm aim in ARMA or MechWarrior).
## The mech aim (blue ring) moves with the mouse inside a box around the camera crosshair.
## Only the mouse movement that pushes past the box edge turns the camera.
## Each shot kicks the mech aim up and a little to the side (muzzle climb) and makes it shake a
## little (jitter). The kick rises over a short time and the ring follows smoothly, so nothing snaps.
## The aim also shakes while the boosters fire.
## The camera does not move. The player pulls the aim back onto the target. No automatic return.

## Half width of the box (left and right of the crosshair), in degrees.
@export var box_half_yaw_deg: float = 4.0
## Half height of the box (above and below the crosshair), in degrees.
@export var box_half_pitch_deg: float = 3.0

## Optional. Kneeling steadies the aim.
@export var kneel: MechKneel
## Optional. A lifted shield makes the aim less steady.
@export var shield: MechShield
## Optional. The aim shakes while the boosters fire (boost, air boost, jump jets, dodge hop).
@export var boosters: BoosterFlames
## Aim shake at full booster thrust, in degrees.
@export var booster_jitter_deg: float = 0.7

@export_group("Recoil")
## Muzzle climb per shot, in degrees.
@export var recoil_up_deg: float = 2.0
## Largest random side kick per shot (left or right), in degrees.
@export var recoil_side_deg: float = 1.0
## How fast a kick rises (1 / seconds). 25 = most of the kick in about 0.1 s.
@export var recoil_rise_speed: float = 25.0
## Jitter added by each shot, in degrees. It fades out.
@export var jitter_per_shot_deg: float = 0.9
## Largest jitter, in degrees.
@export var max_jitter_deg: float = 1.2
## How fast the jitter fades (degrees per second).
@export var jitter_fade: float = 1.0
## How fast the jitter moves (waves per second).
@export var jitter_speed: float = 3.0
## Recoil and jitter while kneeling = normal x this value. 0.3 = 70% less.
@export var kneel_multiplier: float = 0.3
## Recoil and jitter with the shield up = normal x this value. 1.6 = 60% more.
@export var shield_multiplier: float = 1.6
@export_group("")

## How fast the ring follows the mouse and the kicks (1 / seconds). Lower = smoother, slower.
@export var follow_speed: float = 14.0

## Recoil multiplier from the arm (ArmPart.recoil_control) and mods. Set by MechStatApplier.
var recoil_multiplier: float = 1.0

## Control position of the mech aim from the camera crosshair, in degrees: x = yaw (positive =
## left), y = pitch (positive = up). The mouse and the kicks move it. Stays inside the box.
var offset: Vector2 = Vector2.ZERO
## Where the mech aim really points, in degrees (smoothed offset plus jitter). MechAim uses it.
var aim_offset: Vector2 = Vector2.ZERO

var _pending_kick: Vector2 = Vector2.ZERO
var _smoothed: Vector2 = Vector2.ZERO
var _jitter: float = 0.0
var _time: float = 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	# Before MechAim (4).
	process_physics_priority = 3
	_noise.frequency = 1.0


func _physics_process(delta: float) -> void:
	_time += delta * jitter_speed
	# The kick rises over a short time.
	var take := _pending_kick * (1.0 - exp(-recoil_rise_speed * delta))
	_pending_kick -= take
	offset = _clamp_to_box(offset + take)
	_jitter = maxf(_jitter - jitter_fade * delta, 0.0)
	# Noise values are mostly within +/- 0.5, so x2 gives about the full jitter size. The noise is
	# smooth by itself, so it goes on top of the smoothed ring.
	var amount := _jitter + _get_booster_jitter()
	var shake := Vector2(_noise.get_noise_2d(_time, 0.0), _noise.get_noise_2d(_time, 50.0)) * 2.0 * amount
	_smoothed = _smoothed.lerp(offset, 1.0 - exp(-follow_speed * delta))
	aim_offset = _smoothed + shake


## Moves the mech aim by a mouse movement (degrees, same signs as offset).
## Returns the part that went past the box edge. The camera turns by that part.
func take_motion(motion: Vector2) -> Vector2:
	var wanted := offset + motion
	offset = _clamp_to_box(wanted)
	return wanted - offset


## Recoil kick after a shot: up, plus a random side kick, and some jitter.
func kick() -> void:
	var scale := get_recoil_scale()
	_pending_kick += Vector2(randf_range(-recoil_side_deg, recoil_side_deg), recoil_up_deg) * scale
	_jitter = minf(_jitter + jitter_per_shot_deg * scale, max_jitter_deg * scale)


## Steady aim shake from the boosters, in degrees (with the stance multiplier).
func _get_booster_jitter() -> float:
	if boosters == null:
		return 0.0
	return booster_jitter_deg * minf(boosters.thrust, 1.0) * get_recoil_scale()


## Recoil and jitter multiplier from the stance: less while kneeling, more with the shield up.
func get_recoil_scale() -> float:
	var scale := recoil_multiplier
	if kneel != null:
		scale *= lerpf(1.0, kneel_multiplier, kneel.amount)
	if shield != null:
		scale *= lerpf(1.0, shield_multiplier, shield.amount)
	return scale


func _clamp_to_box(value: Vector2) -> Vector2:
	return Vector2(clampf(value.x, -box_half_yaw_deg, box_half_yaw_deg),
			clampf(value.y, -box_half_pitch_deg, box_half_pitch_deg))
