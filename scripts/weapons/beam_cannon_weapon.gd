class_name BeamCannonWeapon
extends GunWeapon
## A two-hand charged beam cannon (Beam Rifle 3, user request 2026-11-01: "shoots like a PPC from MechWarrior").
## While the trigger is held, the rifle is raised and it is ready, it charges for charge_time, then fires one
## heavy energy bolt (scenes/weapons/ppc_bolt.tscn) from the barrel. The shot cannot be stopped once the charge
## starts (only a knock-down, a drop or a lost arm stop it). Then it cools down for 1 / data.fire_rate seconds.
## The barrel rings are grey at rest; during the charge they all light up to bright orange (fully lit at the shot),
## then fade (user 2026-11-01: "All rings glow when fully charged, greyish at rest"; glow_when_ready keeps them lit
## while it is ready). User 2026-11-02: the rings light one after another from the back ring to the front ring and then
## the prong tips (orange) during the charge, not together; after the shot the glow fades over ring_fade (1 s) and
## the cannon cannot fire until the fade ends. The prong tips flash red at each shot. No heat (heat_per_use 0).

const BOLT := preload("res://scenes/weapons/ppc_bolt.tscn")

## Seconds from the trigger to the shot.
@export var charge_time: float = 0.3
## Meshes that glow with the charge: the barrel rings (back to front) and the rails along the open barrel.
@export var ring_paths: Array[NodePath] = []
## Prong tip meshes that glow red at a shot.
@export var prong_paths: Array[NodePath] = []
## The first sequence_count entries of ring_paths (the rings, back to front) light one after another during the
## charge, then the prong tips; the others (the rails) rise with the charge. 0 = all together (the first look).
@export var sequence_count: int = 0
@export var ring_color: Color = Color(1.0, 0.28, 0.0)
## Ring glow when fully charged.
@export var ring_energy: float = 2.0
## Seconds the glow takes to fade after the shot. No new shot starts before it ends (user 2026-11-02).
@export var ring_fade: float = 1.0
## True: the rings stay lit while the rifle is ready to fire (after the cool down).
@export var glow_when_ready: bool = false
## Red glow of the prongs at a shot: strength, seconds fully lit, seconds to fade.
@export var prong_energy: float = 5.0
@export var prong_hold: float = 0.2
@export var prong_fade: float = 0.6

## Seconds left in the charge. Below 0 = not charging.
var charge_left: float = -1.0

var _rings: Array[StandardMaterial3D] = []
## Seconds since the last shot.
var _since_shot: float = 100.0
var _prongs := ShotGlow.new()


func _ready() -> void:
	for path in ring_paths:
		_rings.append(ShotGlow.glow_material(get_node(path) as MeshInstance3D, ring_color))
	_prongs.energy = prong_energy
	_prongs.hold = prong_hold
	_prongs.fade = prong_fade
	_prongs.base_color = ring_color
	_prongs.base_energy = ring_energy
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
	_since_shot += delta
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
				_since_shot = 0.0
	elif not lost and trigger_held and can_use() and _since_shot >= ring_fade and controller.weapon_pose.aim_amount >= 0.9:
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
	# level: the overall glow (charge progress, then the fade after the shot, or lit while ready).
	var level := 0.0
	var progress := 0.0
	var charging := charge_left >= 0.0
	if charging:
		progress = 1.0 - charge_left / maxf(charge_time, 0.01)
		level = progress
	elif _since_shot < ring_fade:
		level = 1.0 - _since_shot / maxf(ring_fade, 0.01)
	elif glow_when_ready and readiness() >= 1.0:
		level = 1.0
	var in_sequence := mini(sequence_count, _rings.size()) if sequence_count > 0 else 0
	# Rings back to front, then the prong tips: a wave over the charge (stage i is lit when the wave passed it).
	var wave := progress * (in_sequence + 1)
	var tip_level := level
	for i in _rings.size():
		var ring_level := level
		if charging and i < in_sequence:
			ring_level = clampf(wave - i, 0.0, 1.0)
		_rings[i].emission_energy_multiplier = ring_energy * ring_level
	if charging and in_sequence > 0:
		tip_level = clampf(wave - in_sequence, 0.0, 1.0)
	_prongs.set_base(tip_level)


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

