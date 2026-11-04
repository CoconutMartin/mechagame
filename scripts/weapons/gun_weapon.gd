class_name GunWeapon
extends MechWeapon
## A solid gun (heavy rifle, SMG, shotgun). Fires `data.pellets` bullets per shot toward the mech aim
## point while the trigger is held and the weapon is raised. Uses ammo; reloads when empty (or with R).

const BULLET := preload("res://scenes/weapons/bullet.tscn")

## Semi-auto (WeaponData.semi_auto): true after a shot until the trigger is let go (AiPilot reads it to let go).
var needs_release: bool = false
## Semi-auto: a press waits here until the gun is raised and ready; letting go drops it (unless queue_tap).
var _shot_queued: bool = false
## WeaponData.queue_tap: a press waits for its shot (true from the press until a shot or the end of tap_queue_s).
var _tap_queued: bool = false
## Seconds a tap's queued shot is still left after the button went up.
var _tap_left: float = 0.0

## Seconds a quick tap's queued shot waits for the gun to be raised and ready after the button is let go
## (WeaponData.queue_tap). The raise takes about 0.3 s. Holding the button has no limit.
@export var tap_queue_s: float = 0.5

## A subclass with the muzzle elsewhere (on a moved model) sets it in _ready.
@onready var _muzzle: Node3D = get_node_or_null("Muzzle")
@onready var _flash: MuzzleFlash = get_node_or_null("Muzzle/MuzzleFlash")


## A tap queues its shot, so the weapon runs after WeaponController (priority 1) and can keep itself raised.
func setup(weapon_data: WeaponData, weapon_controller: WeaponController) -> void:
	super(weapon_data, weapon_controller)
	if data.queue_tap:
		process_physics_priority = 2


## True while a tap's shot waits for the raise (WeaponController keeps this gun the active weapon).
func is_busy() -> bool:
	return _tap_queued and data != null and data.queue_tap


func _update(delta: float) -> void:
	_update_tap_queue(delta)
	if data.semi_auto:
		_update_semi_auto()
		return
	if not (trigger_held or _tap_queued) or not can_use():
		return
	if controller.weapon_pose.aim_amount < 0.9:
		return  # Not raised yet.
	_tap_queued = false
	_fire()


## WeaponData.queue_tap: a press waits for its shot after the button is let go. While it waits the gun stays raised
## (WeaponController lowers it with the button; this runs after it and raises it again). The wait ends with the shot,
## after tap_queue_s, or when the mech goes down.
func _update_tap_queue(delta: float) -> void:
	if not data.queue_tap:
		_tap_queued = false
		return
	if trigger_pressed():
		_tap_queued = true
	if trigger_held:
		_tap_left = tap_queue_s
		return
	if not _tap_queued:
		return
	_tap_left -= delta
	if _tap_left <= 0.0 or controller.mech.is_fallen or controller.mech.is_wrecked:
		_tap_queued = false
		return
	if controller.weapon_pose != null:
		controller.weapon_pose.wants_raise = true


## One shot per press (WeaponData.semi_auto).
func _update_semi_auto() -> void:
	if not trigger_held:
		needs_release = false
		if not _tap_queued:
			_shot_queued = false
		if not _shot_queued:
			return
	if trigger_pressed():
		_shot_queued = true
	if not _shot_queued or not can_use() or controller.weapon_pose.aim_amount < 0.9:
		return
	_shot_queued = false
	_tap_queued = false
	needs_release = true
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
