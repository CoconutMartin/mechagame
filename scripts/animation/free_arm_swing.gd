class_name FreeArmSwing
extends Node
## An empty hand moves (user request 2026-10-15: "the empty left arm just hangs without movement").
## Mech adds it at runtime; it finds the WeaponController and SkeletalLocomotion of its mech.
## Stride swing (user request 2026-10-24: "arms currently dead hang ... swing back and forth, both from the
## shoulder and the elbow joint, smoothen the animation"; it replaces the clip swing of 2026-10-18 and the
## heavy arm shares of 2026-10-22): a relaxed arm (a free or fist hand at its hang marker) swings about its
## hang pose by a sine locked to the stride phase (SkeletalLocomotion: phase 0 = the left foot lands). The arm
## is opposite to its leg: when the left foot is forward the left arm is back and the right arm is forward.
## The shoulder swings the whole arm forward and back; the elbow bends more on the forward swing (the forearm
## comes up toward level) and opens on the back swing (the forearm hangs down), a little behind the shoulder
## (elbow_lag), as in the user's drawing of 2026-10-24; while moving the forearm also rides a little higher
## (elbow_raise_deg; user request 2026-10-24: "swing the forearm and hands a bit higher"). A sine has no kicks, so the arm is smooth;
## the size grows with the ground speed (walk, run, boost). SkeletalArmRig applies swing() after it solved
## the arm to the still hang marker. A one-hand gun arm uses a small share of it (WeaponPose.gun_sway).
## Standing: the small idle sway about the shoulder (left_angle, right_angle) stays; it fades out as the
## stride swing fades in.

@export var mech: Mech
@export var locomotion: SkeletalLocomotion
@export var weapons: WeaponController
## Shoulder swing each way from the hang pose (degrees) at the walk speed, and at fast_speed_share of the
## walk speed (the run and the boost).
@export var shoulder_swing_deg: float = 14.0
@export var shoulder_swing_fast_deg: float = 22.0
## Elbow bend range (degrees, from the most open to the most bent) at the walk speed and at the fast speed.
## 36 / 40 since 2026-10-24 (was 18 / 30).
@export var elbow_bend_deg: float = 36.0
@export var elbow_bend_fast_deg: float = 40.0
## Extra mean elbow bend while moving (degrees, forearm up) at the walk speed and at the fast speed: the
## forearm is about level at the front of the walk swing.
@export var elbow_raise_deg: float = 10.0
@export var elbow_raise_fast_deg: float = 12.0
## Ground speed as a part of the walk speed where the fast sizes are full (the boost is 1.5).
@export var fast_speed_share: float = 1.5
## The elbow trails the shoulder by this part of a stride (the forearm follows the upper arm).
@export_range(0.0, 0.5) var elbow_lag: float = 0.08
## Shift of both arms against the stride (part of a stride; + = the arms later).
@export var phase_shift: float = 0.0
## Idle sway while standing, in degrees about the shoulder, and its speed in cycles per second.
@export var idle_sway_deg: float = 1.2
@export var idle_sway_speed: float = 0.3
## How fast the swing amount follows the speed (per second).
@export var blend_speed: float = 4.0

## How much of the stride swing the relaxed arms take now (0 = the hang, 1 = the walk-speed swing).
var amount: float = 0.0
## Ground speed now as a part of the walk speed (0 when not walking on the ground).
var speed_share: float = 0.0
## Idle sway of each relaxed arm now (radians about the torso's right axis; forward is positive).
var left_angle: float = 0.0
var right_angle: float = 0.0

var _time: float = 0.0


func _ready() -> void:
	if mech == null:
		mech = get_parent() as Mech
	if mech == null:
		return
	if weapons == null:
		weapons = mech.find_child("WeaponController", true, false) as WeaponController
	if locomotion == null:
		for node in mech.find_children("*", "", true, false):
			if node is SkeletalLocomotion:
				locomotion = node as SkeletalLocomotion
				break


func _physics_process(delta: float) -> void:
	if mech == null:
		return
	_time += delta
	var walking := mech.is_on_floor() and not mech.is_fallen and not mech.is_wrecked
	speed_share = mech.get_horizontal_speed() / maxf(mech.walk_speed, 0.1) if walking else 0.0
	amount = move_toward(amount, clampf(speed_share, 0.0, 1.0), blend_speed * delta)
	left_angle = _idle(0.0)
	right_angle = _idle(0.5)


## The swing of an arm now, in radians (forward is positive, about the torso's right axis): x = the shoulder
## (the whole arm), y = the elbow (extra bend; forward and up). Zero when the arm is not swinging.
func swing(right: bool) -> Vector2:
	if amount <= 0.0 or locomotion == null:
		return Vector2.ZERO
	var fast := smoothstep(1.0, maxf(fast_speed_share, 1.01), speed_share)
	var shoulder := deg_to_rad(lerpf(shoulder_swing_deg, shoulder_swing_fast_deg, fast)) * amount
	var bend := deg_to_rad(lerpf(elbow_bend_deg, elbow_bend_fast_deg, fast)) * amount
	var raise := deg_to_rad(lerpf(elbow_raise_deg, elbow_raise_fast_deg, fast)) * amount
	# Phase 0: the left foot lands, so the right arm is forward and the left arm back.
	var arm_phase := locomotion.get_phase() - phase_shift
	var side := 1.0 if right else -1.0
	var forward := side * cos(TAU * arm_phase)
	var elbow_forward := side * cos(TAU * (arm_phase - elbow_lag))
	# More bend while the arm is forward, less while it is back, about the hang bend plus the raise.
	return Vector2(shoulder * forward, raise + 0.5 * bend * elbow_forward)


## One arm's idle sway (radians); offset (0 to 1) shifts it in time.
func _idle(offset: float) -> float:
	return deg_to_rad(sin(TAU * (_time * idle_sway_speed + offset)) * idle_sway_deg * (1.0 - amount))
