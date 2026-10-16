class_name GunWeapon
extends MechWeapon
## A solid gun (heavy rifle, SMG, shotgun). Fires `data.pellets` bullets per shot toward the mech aim
## point while the trigger is held and the weapon is raised. Uses ammo; reloads when empty (or with R).

const BULLET := preload("res://scenes/weapons/bullet.tscn")

## A subclass with the muzzle elsewhere (on a moved model) sets it in _ready.
@onready var _muzzle: Node3D = get_node_or_null("Muzzle")
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
	var shot := MechStability.new_shot_id()
	for _i in maxi(data.pellets, 1):
		var direction := MechWeapon.spread_direction(aim, data.spread_deg)
		var bullet := BULLET.instantiate() as Bullet
		bullet.velocity = direction * data.projectile_speed
		bullet.exclude = controller.mech.get_hit_exclude()
		bullet.damage = data.damage
		bullet.weapon_data = data
		bullet.shot_id = shot
		# Long enough to reach the max range (the bullet ends there, Bullet.weapon_data).
		bullet.lifetime = maxf(bullet.lifetime, data.range_m / maxf(data.projectile_speed, 1.0) + 0.5)
		controller.get_world().add_child(bullet)
		bullet.global_position = origin
		bullet.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	if _flash != null:
		_flash.flash()
	_after_shot()
