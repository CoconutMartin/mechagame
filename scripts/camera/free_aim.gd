class_name FreeAim
extends Node
## The mech aim (blue ring) around the camera crosshair. With the box size 0 (the default since
## 2026-10-10, user request) it is a standard crosshair: the mouse turns the camera. The ring has
## momentum: a turn drags it behind, then it swings back past the center and settles. It also sways
## slowly, more while the mech moves. With a box (size above 0) it is a dead zone: the ring moves
## inside the box and only the mouse movement past the edge turns the camera (like ARMA).
## Each shot kicks the aim up and a little to the side (muzzle climb) and makes it shake a
## little (jitter). The kick rises over a short time, so nothing snaps. With no box the kick turns
## the camera; with a box it moves the ring. The player pulls the aim back. No automatic return.
## The aim also shakes while the boosters fire.
## Unsteady (a two-hand weapon held in one hand, set by WeaponController): the ring follows on a
## soft spring (it swings past and comes back), sways slowly, and the recoil is bigger.

## Half width of the dead zone box (left and right of the crosshair), in degrees. 0 = no dead zone.
@export var box_half_yaw_deg: float = 0.0
## Half height of the dead zone box (above and below the crosshair), in degrees. 0 = no dead zone.
@export var box_half_pitch_deg: float = 0.0

## Optional. The mech, for the sway while moving.
@export var mech: Mech

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

@export_group("Momentum and Sway")
## A camera turn drags the ring behind by this part of the turn (0.25 = a 4 degree turn drags it 1 degree).
@export var momentum: float = 0.25
## Largest drag, in degrees.
@export var max_momentum_deg: float = 3.0
## Ring spring speed back to the center (swings per second). Lower = heavier.
@export var momentum_frequency: float = 1.8
## Ring spring damping. Lower = more swing past the center (1 = no swing).
@export_range(0.05, 1.0) var momentum_damping: float = 0.45
## Slow sway while standing, in degrees.
@export var sway_deg: float = 0.2
## Sway added at walking speed, in degrees (more when faster, up to 1.5 times this).
@export var move_sway_deg: float = 0.5
## How fast the sway moves (waves per second).
@export var sway_speed: float = 0.35
@export_group("")

@export_group("Unsteady (one hand)")
## Ring spring speed when unsteady, in swings per second. Lower = heavier, slower swing.
@export var unsteady_frequency: float = 1.6
## Ring spring damping when unsteady. Lower = more swing past the target (1 = no swing).
@export var unsteady_damping: float = 0.3
## Slow sway of the ring when unsteady, in degrees.
@export var unsteady_sway_deg: float = 0.9
## How fast the sway moves (waves per second).
@export var unsteady_sway_speed: float = 0.45
## Recoil and jitter when unsteady = normal x this value.
@export var unsteady_recoil_multiplier: float = 1.6
@export_group("")

## 0 = steady, 1 = unsteady (a two-hand weapon in one hand). Set by WeaponController.
var unsteady: float = 0.0

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
var _spring_x := AimSpring.new(0.0)
var _spring_y := AimSpring.new(0.0)
var _sway_time: float = 0.0
var _drag_x := AimSpring.new(0.0)
var _drag_y := AimSpring.new(0.0)
var _drag_time: float = 0.0
## Recoil that turns the camera (no box), degrees. The camera rig takes it each frame.
var _camera_kick: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Before MechAim (4).
	process_physics_priority = 3
	_noise.frequency = 1.0


func _physics_process(delta: float) -> void:
	_time += delta * jitter_speed
	# The kick rises over a short time.
	var take := _pending_kick * (1.0 - exp(-recoil_rise_speed * delta))
	_pending_kick -= take
	if _has_box():
		offset = _clamp_to_box(offset + take)
	else:
		_camera_kick += take
	_jitter = maxf(_jitter - jitter_fade * delta, 0.0)
	# Noise values are mostly within +/- 0.5, so x2 gives about the full jitter size. The noise is
	# smooth by itself, so it goes on top of the smoothed ring.
	var amount := _jitter + _get_booster_jitter()
	var shake := Vector2(_noise.get_noise_2d(_time, 0.0), _noise.get_noise_2d(_time, 50.0)) * 2.0 * amount
	shake += _get_drag(delta)
	_smoothed = _smoothed.lerp(offset, 1.0 - exp(-follow_speed * delta))
	if unsteady <= 0.0:
		_spring_x = AimSpring.new(_smoothed.x)
		_spring_y = AimSpring.new(_smoothed.y)
		aim_offset = _smoothed + shake
		return
	# Heavy one-hand hold: a soft spring that swings past the target, plus a slow sway.
	var limit := deg_to_rad(maxf(box_half_yaw_deg, box_half_pitch_deg) * 2.0)
	_spring_x.update(deg_to_rad(offset.x), unsteady_frequency, unsteady_damping, limit, delta)
	_spring_y.update(deg_to_rad(offset.y), unsteady_frequency, unsteady_damping, limit, delta)
	_sway_time += delta * unsteady_sway_speed
	var sway := Vector2(_noise.get_noise_2d(_sway_time, 100.0), _noise.get_noise_2d(_sway_time, 150.0)) * 2.0 * unsteady_sway_deg
	var swing := Vector2(rad_to_deg(_spring_x.value), rad_to_deg(_spring_y.value))
	aim_offset = _smoothed.lerp(swing + sway, unsteady) + shake


## Moves the mech aim by a mouse movement (degrees, same signs as offset).
## Returns the part that went past the box edge. The camera turns by that part.
func take_motion(motion: Vector2) -> Vector2:
	var wanted := offset + motion
	offset = _clamp_to_box(wanted)
	var turn := wanted - offset
	# Momentum: the ring stays behind the turn for a moment.
	var limit := max_momentum_deg
	_drag_x.value = clampf(_drag_x.value - turn.x * momentum, -limit, limit)
	_drag_y.value = clampf(_drag_y.value - turn.y * momentum, -limit, limit)
	return turn


## Recoil that turns the camera since the last call (degrees, same signs as offset). The camera rig
## calls it each frame. Zero with a dead zone box (the kick moves the ring there).
func take_camera_kick() -> Vector2:
	var kick_now := _camera_kick
	_camera_kick = Vector2.ZERO
	return kick_now


## Recoil kick after a shot: up, plus a random side kick, and some jitter.
## up_deg and side_deg < 0 use recoil_up_deg and recoil_side_deg (the weapon data gives its own).
## jitter_scale multiplies the jitter of this shot (a charged beam shakes more).
func kick(up_deg: float = -1.0, side_deg: float = -1.0, jitter_scale: float = 1.0) -> void:
	var scale := get_recoil_scale()
	var up := up_deg if up_deg >= 0.0 else recoil_up_deg
	var side := side_deg if side_deg >= 0.0 else recoil_side_deg
	_pending_kick += Vector2(randf_range(-side, side), up) * scale
	_jitter = minf(_jitter + jitter_per_shot_deg * scale * jitter_scale, max_jitter_deg * scale * maxf(jitter_scale, 1.0))


## Steady aim shake from the boosters, in degrees (with the stance multiplier).
func _get_booster_jitter() -> float:
	if boosters == null:
		return 0.0
	return booster_jitter_deg * minf(boosters.thrust, 1.0) * get_recoil_scale()


## Recoil and jitter multiplier from the stance: less while kneeling, more with the shield up.
func get_recoil_scale() -> float:
	var scale := recoil_multiplier * lerpf(1.0, unsteady_recoil_multiplier, unsteady)
	if kneel != null:
		scale *= lerpf(1.0, kneel_multiplier, kneel.amount)
	if shield != null:
		scale *= lerpf(1.0, shield_multiplier, shield.amount)
	return scale


## Ring drag from the momentum spring plus the sway, in degrees.
func _get_drag(delta: float) -> Vector2:
	var limit := max_momentum_deg * 2.0
	_drag_x.update(0.0, momentum_frequency, momentum_damping, limit, delta)
	_drag_y.update(0.0, momentum_frequency, momentum_damping, limit, delta)
	var size := sway_deg
	if mech != null and mech.walk_speed > 0.0:
		size += move_sway_deg * clampf(mech.get_horizontal_speed() / mech.walk_speed, 0.0, 1.5)
	if kneel != null:
		size *= lerpf(1.0, kneel_multiplier, kneel.amount)
	_drag_time += delta * sway_speed
	var sway := Vector2(_noise.get_noise_2d(_drag_time, 200.0), _noise.get_noise_2d(_drag_time, 250.0)) * 2.0 * size
	return Vector2(_drag_x.value, _drag_y.value) + sway


func _has_box() -> bool:
	return box_half_yaw_deg > 0.0 or box_half_pitch_deg > 0.0


func _clamp_to_box(value: Vector2) -> Vector2:
	return Vector2(clampf(value.x, -box_half_yaw_deg, box_half_yaw_deg),
			clampf(value.y, -box_half_pitch_deg, box_half_pitch_deg))
