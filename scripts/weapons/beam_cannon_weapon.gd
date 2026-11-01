class_name BeamCannonWeapon
extends GunWeapon
## A two-hand charged beam cannon (Beam Rifle 3, user request 2026-11-01: "shoots like a PPC from MechWarrior").
## While the trigger is held, the rifle is raised and it is ready, it charges for charge_time, then fires one
## heavy energy bolt (scenes/weapons/ppc_bolt.tscn) from the barrel. The shot cannot be stopped once the charge
## starts (only a knock-down, a drop or a lost arm stop it). Then it cools down for 1 / data.fire_rate seconds.
## The barrel rings light one after another while it cools down and are all bright orange when it is ready; the
## two prong tips at the muzzle glow red at each shot. No heat (heat_per_use 0).

const BOLT := preload("res://scenes/weapons/ppc_bolt.tscn")

## Seconds from the trigger to the shot.
@export var charge_time: float = 0.3
## Barrel ring meshes, back to front.
@export var ring_paths: Array[NodePath] = []
## Prong tip meshes that glow red at a shot.
@export var prong_paths: Array[NodePath] = []
@export var ring_color: Color = Color(1.0, 0.45, 0.05)
## Ring glow when ready. While it cools down the rings light one by one at ring_cooling_part of it.
@export var ring_energy: float = 3.0
@export_range(0.0, 1.0) var ring_cooling_part: float = 0.3
## Ring glow during the charge, x ring_energy.
@export var ring_charge_boost: float = 1.6
## Red glow of the prongs at a shot: strength, seconds fully lit, seconds to fade.
@export var prong_energy: float = 5.0
@export var prong_hold: float = 0.2
@export var prong_fade: float = 0.6

## Seconds left in the charge. Below 0 = not charging.
var charge_left: float = -1.0

var _rings: Array[StandardMaterial3D] = []
var _prongs := ShotGlow.new()


func _ready() -> void:
	for path in ring_paths:
		_rings.append(ShotGlow.glow_material(get_node(path) as MeshInstance3D, ring_color))
	_prongs.energy = prong_energy
	_prongs.hold = prong_hold
	_prongs.fade = prong_fade
	add_child(_prongs)
	var prongs: Array[MeshInstance3D] = []
	for path in prong_paths:
		prongs.append(get_node(path) as MeshInstance3D)
	_prongs.setup(prongs)
	_show()


## True while charging (WeaponController keeps it active and raised).
func is_busy() -> bool:
	return charge_left >= 0.0


func _update(delta: float) -> void:
	var lost := controller.mech.is_fallen or controller.mech.is_wrecked or not controller.holds(self)
	if charge_left >= 0.0:
		if lost:
			charge_left = -1.0
		else:
			charge_left -= delta
			if charge_left <= 0.0:
				charge_left = -1.0
				_fire()
				_prongs.flash()
	elif not lost and trigger_held and can_use() and controller.weapon_pose.aim_amount >= 0.9:
		charge_left = charge_time
	_show()


func _fire() -> void:
	consume()
	var origin := _muzzle.global_position
	var aim := (controller.mech_aim.aim_point - origin).normalized()
	if aim.is_zero_approx():
		aim = -_muzzle.global_basis.z
	var direction := MechWeapon.spread_direction(aim, data.spread_deg)
	var bolt := BOLT.instantiate() as Bullet
	bolt.velocity = direction * data.projectile_speed
	bolt.exclude = controller.mech.get_hit_exclude()
	bolt.damage = data.damage
	bolt.weapon_data = data
	bolt.shot_id = MechStability.new_shot_id()
	bolt.lifetime = maxf(bolt.lifetime, data.range_m / maxf(data.projectile_speed, 1.0) + 0.5)
	controller.get_world().add_child(bolt)
	bolt.global_position = origin
	bolt.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	_after_shot()


## Ready part: 0 just after a shot, 1 when it can fire again.
func readiness() -> float:
	return clampf(1.0 - _cooldown * data.fire_rate, 0.0, 1.0) if data != null else 1.0


func _show() -> void:
	var ready_part := readiness()
	var count := _rings.size()
	for i in count:
		var energy := 0.0
		if charge_left >= 0.0:
			energy = ring_energy * ring_charge_boost
		elif ready_part >= 1.0:
			energy = ring_energy
		else:
			# One ring after another, back to front, while it cools down.
			energy = ring_energy * ring_cooling_part * clampf(ready_part * count - i, 0.0, 1.0)
		_rings[i].emission_energy_multiplier = energy


## A charge stops when the weapon is turned off or leaves the scene (a broken arm, a drop).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_EXIT_TREE:
		charge_left = -1.0


func get_status_text() -> String:
	if charge_left >= 0.0:
		return "CHARGING"
	var ready_part := readiness()
	if ready_part < 1.0:
		return "COOLING %s %.1f s" % [_bar(ready_part), _cooldown]
	return "READY"

