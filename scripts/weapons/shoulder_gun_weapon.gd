class_name ShoulderGunWeapon
extends GunWeapon
## A gun on top of a shoulder (Shoulder Cannon, new mech; Q = left, E = right). It sits on the shoulder
## armor and turns with it (SkeletalArmRig moves the shoulder mount). Stop to fire: it fires only while
## the mech stands still on the ground; shots fly to the mech aim point.

## The mech must be slower than this (m/s) to fire.
@export var max_fire_speed: float = 0.5


func _update(_delta: float) -> void:
	if trigger_held and can_use() and is_stopped():
		_fire()


## True while the mech stands still on the ground.
func is_stopped() -> bool:
	var mech := controller.mech
	return mech.is_on_floor() and mech.get_horizontal_speed() < max_fire_speed


func get_status_text() -> String:
	if reload_left <= 0.0 and not is_stopped():
		return "%s  STOP TO FIRE" % super()
	return super()
