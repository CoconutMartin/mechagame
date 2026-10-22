extends Node
## Stop to fire for the shoulder (back slot) weapons (user request 2026-10-22). WeaponController makes one
## and calls step() every physics frame.
## A shoulder weapon on the ground asks the mech to stand still while it fires. The mech can do it when it is
## on the ground and not in a dodge, a jump, a fall, a stagger, a boost or a run (in the air and while
## boosting the weapons fire as before: the pods fire, the cannon cannot).
## Shoulder cannon: it arms when its key goes down, the brace amount rises over brace_time (the lower stance,
## BracePose), and the shot goes out when the brace is set and the mech stands still. The brace holds
## while the cannon fires (hold_time after each shot) and the stance recovers after that.
## Missile pods: they call stop() for the time of a volley (the mech does not walk while it launches).

## Seconds from the start of the brace to the first shot (the wind-up).
@export var brace_time: float = 0.4
## The brace holds this long after a shot, so the recoil lands on a set stance.
@export var hold_time: float = 0.6
## Seconds to stand up again after the brace ends.
@export var recover_time: float = 0.4
## Seconds the mech is told to stand still on each frame of a brace. It must be longer than a frame.
@export var stop_hold: float = 0.12

## The mech. WeaponController sets it.
var mech: Mech
## 0 = standing, 1 = full brace. BracePose reads it.
var amount: float = 0.0

var _hold_left: float = 0.0
var _stagger: SkeletalStaggerAnimation


## want: a shoulder cannon is armed (its key is down or its shot waits for the brace).
func step(delta: float, want: bool) -> void:
	_hold_left = maxf(_hold_left - delta, 0.0)
	var holding := (want or _hold_left > 0.0) and can_stop() and not _kneeling()
	if holding:
		mech.brace(stop_hold)
		amount = move_toward(amount, 1.0, delta / maxf(brace_time, 0.01))
	else:
		amount = move_toward(amount, 0.0, delta / maxf(recover_time, 0.01))


## True when the brace is set (a cannon may fire). A kneeling mech is set at once: it stands still already.
func is_set() -> bool:
	return amount >= 0.999 or _kneeling()


## A cannon fired: the brace holds for hold_time.
func shot() -> void:
	_hold_left = hold_time


## True when the mech can stand still for a shot now: on the ground, and not boosting, running, sliding,
## lunging, dodging, charging a jump, landing, down or staggered.
func can_stop() -> bool:
	if mech == null or mech.is_wrecked or mech.is_fallen or not mech.is_on_floor():
		return false
	if mech.is_boosting or mech.is_running or mech.is_skidding or mech.is_exiting_boost or mech.is_lunging \
			or mech.root_motion_active:
		return false
	if mech.dodge != null and mech.dodge.is_busy():
		return false
	if mech.jump_charge != null and mech.jump_charge.is_charging:
		return false
	if mech.landing_recovery != null and mech.landing_recovery.is_recovering():
		return false
	return not _is_staggered()


## A missile volley: the mech stands still for this many seconds, when it can (not in the air, not boosting).
func stop(seconds: float) -> void:
	if can_stop():
		mech.brace(seconds)


func _kneeling() -> bool:
	return mech != null and mech.kneel != null and mech.kneel.is_kneeling


func _is_staggered() -> bool:
	if _stagger == null or not is_instance_valid(_stagger):
		_stagger = mech.find_child("StaggerAnimation", true, false) as SkeletalStaggerAnimation
	return _stagger != null and _stagger.is_staggered()
