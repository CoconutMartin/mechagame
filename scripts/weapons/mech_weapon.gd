class_name MechWeapon
extends Node3D
## Base script on a weapon model's root node. WeaponController gives it the data and a trigger.
## Solid guns and missile pods use ammo: a magazine, then a reload.
## Beam weapons (beam rifle, blade) use heat: each use adds heat_per_use (full = 100). At full heat
## the weapon overheats and works again only when it has cooled down to zero (the "reload").

signal fired

var data: WeaponData
var controller: WeaponController
var trigger_held: bool = false
var ammo: int = 0
## Rounds left in the reserve besides the loaded magazine (user decision 2026-10-31: finite ammo, the pack is the
## reserve). -1 = unlimited. A reload fills the magazine from it; when it is 0, a reload takes a canister from the back pack.
var reserve_ammo: int = -1
## Seconds left in the reload. 0 = not reloading.
var reload_left: float = 0.0
## 0 to 100.
var heat: float = 0.0
var overheated: bool = false
## HP of the weapon part while the weapon is not on a mech (user rule 2026-10-17: a dropped weapon keeps its
## damage, and the next hand that takes it gets that HP). -1 = full (WeaponData.hp).
var part_hp: float = -1.0

var _cooldown: float = 0.0
var _was_held: bool = false


## True while the weapon still works after its button is released (subclasses override).
func is_busy() -> bool:
	return false


## True for melee weapons (blade, pile bunker): they work together with the other weapons.
func is_melee() -> bool:
	return false


func setup(weapon_data: WeaponData, weapon_controller: WeaponController) -> void:
	data = weapon_data
	controller = weapon_controller
	ammo = data.magazine
	reserve_ammo = data.reserve_magazines * data.magazine if data.reserve_magazines >= 0 else -1


## A new hand takes the weapon (it was picked up from the ground): it talks to this controller from now
## on. Ammo, reserve, heat and HP stay.
func rebind(new_controller: WeaponController) -> void:
	controller = new_controller


func uses_heat() -> bool:
	return data.kind == WeaponData.Kind.BEAM_RIFLE or data.kind == WeaponData.Kind.BLADE


## WeaponController calls this every physics frame.
func set_trigger(held: bool) -> void:
	_was_held = trigger_held
	trigger_held = held


## True on the frame the trigger went down.
func trigger_pressed() -> bool:
	return trigger_held and not _was_held


## True on the frame the trigger went up.
func trigger_released() -> bool:
	return _was_held and not trigger_held


func _physics_process(delta: float) -> void:
	if data == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if uses_heat():
		heat = maxf(heat - (data.overheat_cooling if overheated else data.heat_cooling) * delta, 0.0)
		if overheated and heat <= 0.0:
			overheated = false
	elif reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			reload_left = 0.0
			fill_magazine()
	_update(delta)


## Subclasses do their work here.
func _update(_delta: float) -> void:
	pass


## True when the weapon can be used now (fire rate, ammo, heat).
func can_use() -> bool:
	if _cooldown > 0.0:
		return false
	if uses_heat():
		return not overheated
	return reload_left <= 0.0 and ammo > 0


## Uses one shot: starts the fire rate wait, and uses ammo or adds heat.
func consume(count: int = 1) -> void:
	_cooldown = 1.0 / maxf(data.fire_rate, 0.01)
	if uses_heat():
		heat = minf(heat + data.heat_per_use * count, 100.0)
		if heat >= 100.0:
			overheated = true
	else:
		ammo = maxi(ammo - count, 0)
		if ammo <= 0:
			start_reload()


## Starts a reload when the magazine is not full and rounds are at hand (the reserve, or a canister from the back pack).
## No rounds = no reload: the weapon is empty.
func start_reload() -> void:
	if reload_left <= 0.0 and ammo < data.magazine and has_reload_rounds():
		reload_left = data.reload_time


## True when the reserve holds rounds (or is unlimited). With an empty reserve it takes one canister from the back pack
## (one canister = one full magazine in the reserve); false when there is no canister.
func has_reload_rounds() -> bool:
	if uses_heat() or reserve_ammo != 0:
		return true
	if controller == null or not BackPackMount.take_canister(controller.mech, data):
		return false
	reserve_ammo = data.magazine
	return true


## Moves rounds from the reserve to the magazine, up to a full magazine. Returns the count moved.
func fill_magazine() -> int:
	var need := data.magazine - ammo
	var moved := need if reserve_ammo < 0 else mini(need, reserve_ammo)
	ammo += moved
	if reserve_ammo >= 0:
		reserve_ammo -= moved
	return moved


## True when the weapon has no rounds and no reload runs (ammo weapons only).
func is_empty() -> bool:
	return not uses_heat() and ammo <= 0 and reserve_ammo == 0 and reload_left <= 0.0


## Weapon pose between rest and aim. The blade overrides it for its swing.
func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	return rest.interpolate_with(aim, t)


## Recoil on the aim and the camera, then the fired signal.
func _after_shot() -> void:
	controller.mech_aim.kick_aim(data.recoil_up_deg, data.recoil_side_deg)
	if controller.camera_shake != null:
		controller.camera_shake.add_shake(data.shake_trauma, data.shake_kick)
	fired.emit()


## One line for the HUD.
func get_status_text() -> String:
	if uses_heat():
		if overheated:
			return "OVERHEAT %s" % _bar(heat / 100.0)
		return "Heat %s %d%%" % [_bar(heat / 100.0), roundi(heat)]
	if reload_left > 0.0:
		return "RELOAD %s" % _bar(1.0 - reload_left / data.reload_time)
	return ammo_text()


## "ammo / magazine  [reserve]", or "EMPTY".
func ammo_text() -> String:
	if is_empty():
		return "EMPTY"
	if reserve_ammo < 0:
		return "%d / %d" % [ammo, data.magazine]
	return "%d / %d  [%d]" % [ammo, data.magazine, reserve_ammo]


func _bar(fraction: float) -> String:
	var filled := clampi(roundi(fraction * 10.0), 0, 10)
	return "[" + "#".repeat(filled) + "-".repeat(10 - filled) + "]"


## Random direction inside a cone around a direction.
static func spread_direction(direction: Vector3, spread_deg: float) -> Vector3:
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(direction).normalized()
	var angle := deg_to_rad(spread_deg) * sqrt(randf())
	var turn := randf() * TAU
	return (direction + (side * cos(turn) + up * sin(turn)) * tan(angle)).normalized()
