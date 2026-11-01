class_name ParticleRifleWeapon
extends GunWeapon
## A two-hand charged particle rifle (Beam Rifle 4, user request 2026-11-01). Hold the trigger to charge (charge_time
## for a full charge; the rifle stays at the low ready and the mech may move while it charges), release it to fire: the mech stops and braces
## (WeaponController.shoulder_brace, like the Shoulder Cannon), then one large particle shot leaves the muzzle
## (scenes/weapons/particle_shot.tscn: a slow glowing projectile, not a beam). A part charge fires a smaller,
## weaker shot. After any shot the rifle cools down for 1 / data.fire_rate seconds (3 s), so a full cycle is 6 s.
## Light bars (bar_paths, body -> midsection -> barrel): they light one after another as the charge grows; at the
## shot all of them are fully lit whatever the charge, then they fade together over the cool down. No light =
## ready to fire.

const SHOT := preload("res://scenes/weapons/particle_shot.tscn")

## Seconds of holding the trigger for a full charge.
@export var charge_time: float = 3.0
## Damage of a shot with no charge, as a part of a full shot.
@export_range(0.0, 1.0) var min_power: float = 0.3
## Size of a shot with no charge, as a part of a full shot.
@export_range(0.1, 1.0) var min_shot_scale: float = 0.45
## Light bar meshes in the order they light: body, midsection, barrel.
@export var bar_paths: Array[NodePath] = []
@export var bar_color: Color = Color(1.0, 0.42, 0.02)
## Glow of a fully lit bar (for the bloom; the bars are unshaded, their color goes from dark to bar_color).
@export var bar_energy: float = 1.0
## Mesh that flashes at the shot (the muzzle ring), its color, and the seconds fully lit and fading.
@export var muzzle_glow_path: NodePath
@export var muzzle_glow_color: Color = Color(1.0, 0.38, 0.0)
@export var muzzle_glow_hold: float = 0.1
@export var muzzle_glow_fade: float = 0.6
## The mech must be slower than this (m/s) for the shot to leave.
@export var max_fire_speed: float = 0.5
## A full shot pushes the mech back this far (m); a part charge pushes less.
@export var push_back_m: float = 1.0

## 0 to 1 while the trigger is held.
var charge: float = 0.0
## True while a released shot waits for the brace.
var armed: bool = false
## 1 while a released shot waits for the brace, else 0 (AiPilot reads it like BeamRifleWeapon.discharge_left:
## no new charge while it is above 0).
var discharge_left: float = 0.0

## Charge of the shot that waits or left last.
var _shot_charge: float = 0.0
var _bars: Array[StandardMaterial3D] = []
## The bars' own (dark) color at rest.
var _bar_rest_color: Array[Color] = []
var _muzzle_glow := ShotGlow.new()


func _ready() -> void:
	for path in bar_paths:
		var material := ShotGlow.glow_material(get_node(path) as MeshInstance3D, bar_color)
		# Unshaded: the sun on a lit bar washed the amber out to peach (Godot screenshots 2026-11-01).
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bars.append(material)
		_bar_rest_color.append(material.albedo_color)
	_muzzle_glow.color = muzzle_glow_color
	_muzzle_glow.hold = muzzle_glow_hold
	_muzzle_glow.fade = muzzle_glow_fade
	add_child(_muzzle_glow)
	var meshes: Array[MeshInstance3D] = []
	if not muzzle_glow_path.is_empty():
		meshes.append(get_node(muzzle_glow_path) as MeshInstance3D)
	_muzzle_glow.setup(meshes)
	_show()


## AiPilot: this weapon fires on the trigger release, like the Beam Rifle.
func is_release_charge_weapon() -> bool:
	return true


## True while charging or while a shot waits (WeaponController keeps it the active weapon).
func is_busy() -> bool:
	return trigger_held or armed


## Raised only while a shot waits (the rifle comes up for the shot); the charge is at the low ready.
func holds_raised() -> bool:
	return armed


## The charge happens at the low ready, so the mech may walk while it charges (user 2026-11-01; the sniping stance
## of the two-hand rifles locks walking only while the rifle is raised: RMB, or the shot).
func raise_on_trigger() -> bool:
	return false


## A released shot asks the mech to stop and brace (WeaponController.shoulder_brace).
func wants_brace() -> bool:
	return armed


func _update(delta: float) -> void:
	var lost := controller.mech.is_fallen or controller.mech.is_wrecked or not controller.holds(self)
	if lost:
		charge = 0.0
		armed = false
	elif armed:
		# The shot waits until the brace is set, the mech stands still and the rifle is raised.
		var brace := controller.shoulder_brace
		if brace != null and brace.is_set() and is_stopped() and controller.weapon_pose.aim_amount >= 0.9:
			_fire()
	elif trigger_held and can_use():
		charge = minf(charge + delta / maxf(charge_time, 0.01), 1.0)
	elif trigger_released() and charge > 0.0:
		armed = true
		_shot_charge = charge
		charge = 0.0
	else:
		charge = 0.0
	discharge_left = 1.0 if armed else 0.0
	_show()


func _fire() -> void:
	armed = false
	consume()
	var power := lerpf(min_power, 1.0, _shot_charge)
	var origin := _muzzle.global_position
	var aim := (controller.mech_aim.aim_point - origin).normalized()
	if aim.is_zero_approx():
		aim = -_muzzle.global_basis.z
	var direction := MechWeapon.spread_direction(aim, data.spread_deg)
	var shot := SHOT.instantiate() as Bullet
	shot.velocity = direction * data.projectile_speed
	shot.exclude = controller.mech.get_hit_exclude()
	shot.damage = data.damage * power
	shot.weapon_data = data
	shot.shot_id = MechStability.new_shot_id()
	shot.lifetime = maxf(shot.lifetime, data.range_m / maxf(data.projectile_speed, 1.0) + 0.5)
	var size := lerpf(min_shot_scale, 1.0, _shot_charge)
	var visual := shot.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale = Vector3.ONE * size
	var tracer := shot.get_node_or_null("Tracer") as Node3D
	if tracer != null:
		tracer.scale = Vector3(size, size, tracer.scale.z)
	controller.get_world().add_child(shot)
	shot.global_position = origin
	shot.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	if controller.shoulder_brace != null:
		controller.shoulder_brace.shot()
	controller.mech.push_back(push_back_m * power)
	_muzzle_glow.flash()
	_after_shot()


## True while the mech stands still on the ground.
func is_stopped() -> bool:
	var mech := controller.mech
	return mech.is_on_floor() and mech.get_horizontal_speed() < max_fire_speed


## Cool down left as a part of the full cool down (1 just after a shot, 0 when ready).
func cooling() -> float:
	return clampf(_cooldown * data.fire_rate, 0.0, 1.0) if data != null else 0.0


func _show() -> void:
	var count := _bars.size()
	var cool := cooling()
	var level := charge if not armed else _shot_charge
	for i in count:
		var lit := 0.0
		if cool > 0.0:
			# After a shot: all bars lit, fading together over the cool down.
			lit = cool
		else:
			# Charging: one bar after another, body first.
			lit = clampf(level * count - i, 0.0, 1.0)
		_bars[i].emission_energy_multiplier = bar_energy * lit
		# The bar's own color goes from dark to amber (unshaded, so this is the color on screen).
		_bars[i].albedo_color = _bar_rest_color[i].lerp(bar_color, lit)


func get_status_text() -> String:
	if armed:
		return "BRACING  %d%%" % roundi(_shot_charge * 100.0)
	if charge > 0.0:
		return "CHARGE %s %d%%" % [_bar(charge), roundi(charge * 100.0)]
	if cooling() > 0.0:
		return "COOLING %s %.1f s" % [_bar(1.0 - cooling()), _cooldown]
	return "READY"
