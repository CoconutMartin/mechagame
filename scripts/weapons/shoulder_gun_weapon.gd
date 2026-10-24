class_name ShoulderGunWeapon
extends GunWeapon
## A gun on top of a shoulder (Shoulder Cannon, new mech; Q = left, E = right). It sits on the shoulder
## armor and turns with it (SkeletalArmRig moves the shoulder mount). Stop to fire: it fires only while
## the mech stands still on the ground; shots fly to the mech aim point.
## Brace (user request 2026-10-22): a key press arms the cannon. The mech stops and takes the brace stance
## (WeaponController.shoulder_brace, the lower stance of BracePose), and the shot goes out when the wind-up
## is done. The wind-up and hold times are on ShoulderBrace. A short tap still fires (the cannon stays armed).
## The two cannons share one brace, so both fire together when both keys are down.

## The mech must be slower than this (m/s) to fire.
@export var max_fire_speed: float = 0.5
## Each shot pushes the mech back this far (m; user request 2026-10-24). Both cannons at once: twice.
@export var push_back_m: float = 0.5

## True while a shot waits for the brace.
var armed: bool = false


## True while the shot waits for the brace (WeaponController keeps this cannon as the active weapon).
func is_busy() -> bool:
	return armed


## True when the cannon wants the mech to brace now.
func wants_brace() -> bool:
	return armed


func _update(_delta: float) -> void:
	var brace := controller.shoulder_brace
	if trigger_held and can_use():
		armed = true
	# The shot is off when the cannon cannot fire any more or the mech cannot stand still (it jumped,
	# fell, was staggered). A boost or a run on the ground ends for the shot (ShoulderBrace.can_cancel).
	if armed and (not can_use() or brace == null or not (brace.can_stop() or brace.can_cancel())):
		armed = false
	if armed and brace.is_set() and is_stopped():
		armed = false
		_fire()
		brace.shot()
		controller.mech.push_back(push_back_m)


## True while the mech stands still on the ground.
func is_stopped() -> bool:
	var mech := controller.mech
	return mech.is_on_floor() and mech.get_horizontal_speed() < max_fire_speed


func get_status_text() -> String:
	if reload_left <= 0.0 and armed:
		return "%s  BRACING" % super()
	if reload_left <= 0.0 and not is_stopped():
		return "%s  STOP TO FIRE" % super()
	return super()
