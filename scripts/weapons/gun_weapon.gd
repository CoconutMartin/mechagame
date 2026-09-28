class_name GunWeapon
extends MechWeapon
## A solid gun (heavy rifle). Fires bullets toward the mech aim point while the trigger is held and
## the weapon is raised. Uses ammo; reloads when empty (or with R).

const BULLET := preload("res://scenes/weapons/bullet.tscn")

@onready var _muzzle: Node3D = $Muzzle
@onready var _flash: MuzzleFlash = get_node_or_null("Muzzle/MuzzleFlash")


func _update(_delta: float) -> void:
	if not trigger_held or not can_use():
		return
	if controller.weapon_pose.aim_amount < 0.9:
		return  # Not raised yet.
	_fire()


func _fire() -> void:
	consume()
	var origin := _muzzle.global_position
	var aim := (controller.mech_aim.aim_point - origin).normalized()
	if aim.is_zero_approx():
		aim = -_muzzle.global_basis.z
	var direction := MechWeapon.spread_direction(aim, data.spread_deg)
	var bullet := BULLET.instantiate() as Bullet
	bullet.velocity = direction * data.projectile_speed
	bullet.exclude = [controller.mech.get_rid()]
	controller.get_world().add_child(bullet)
	bullet.global_position = origin
	bullet.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	if _flash != null:
		_flash.flash()
	_after_shot()
