class_name ParticleRifleWeapon
extends GunWeapon
## A two-hand charged particle rifle (Beam Rifle 4, user request 2026-11-01). Hold the trigger to charge (charge_time
## for a full charge; the rifle stays at the low ready and the mech may move while it charges), release it to fire:
## the shot leaves on the release frame (user 2026-11-02: "remove this delay so when trigger is released, the
## projectile is released as well"; it no longer waits for the stop, the brace and the raise). The shot is one large
## particle projectile (scenes/weapons/particle_shot.tscn: a slow glowing projectile, not a beam) that starts at the
## muzzle and flies toward the aim point, also when the rifle is not raised. A part charge fires a smaller, weaker
## shot. After any shot the rifle cools down for 1 / data.fire_rate seconds (6 s since 2026-11-02: the old 3 s plus 3
## s more), so a full cycle is 3 s of charge and 6 s of cool down.
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
## A full shot pushes the mech back this far (m); a part charge pushes less.
@export var push_back_m: float = 1.0
@export_group("Aim return")
## After a shot the crosshair comes back by this part of the kick on its own (user request 2026-11-04: "add a small auto
## crosshair correction after shooting"); the player corrects the rest. 0 = no return.
@export_range(0.0, 1.0) var aim_return_share: float = 0.7
## Seconds in which the return is done (95% of it).
@export var aim_return_time: float = 0.45
## Seconds after the shot before the return starts (the kick rises in about 0.2 s, so it reaches nearly its full height first).
@export var aim_return_delay: float = 0.2
@export_group("")

## 0 to 1 while the trigger is held.
var charge: float = 0.0
## Always 0: a shot leaves at the release, so none waits (AiPilot reads it like BeamRifleWeapon.discharge_left:
## no new charge while it is above 0).
var discharge_left: float = 0.0

## Charge of the shot that left last.
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


## True while charging (WeaponController keeps it the active weapon).
func is_busy() -> bool:
	return trigger_held


## Never raised: the charge and the shot happen at the low ready (the default would raise it while the trigger is held).
func holds_raised() -> bool:
	return false


## The charge happens at the low ready, so the mech may walk while it charges (user 2026-11-01; the sniping stance
## of the two-hand rifles locks walking only while the rifle is raised: RMB).
func raise_on_trigger() -> bool:
	return false


func _update(delta: float) -> void:
	var lost := controller.mech.is_fallen or controller.mech.is_wrecked or not controller.holds(self)
	if lost:
		charge = 0.0
	elif trigger_held and can_use():
		charge = minf(charge + delta / maxf(charge_time, 0.01), 1.0)
	elif trigger_released() and charge > 0.0:
		# The shot leaves on the release frame.
		_shot_charge = charge
		charge = 0.0
		_fire()
	else:
		charge = 0.0
	_show()


func _fire() -> void:
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
	controller.mech.push_back(push_back_m * power)
	_muzzle_glow.flash()
	_after_shot()


## The kick of the shot, then the gentle automatic return of the crosshair (a part of the kick comes back).
func _after_shot() -> void:
	super()
	if aim_return_share > 0.0:
		controller.mech_aim.return_last_kick(aim_return_share, aim_return_time, aim_return_delay)


## Cool down left as a part of the full cool down (1 just after a shot, 0 when ready).
func cooling() -> float:
	return clampf(_cooldown * data.fire_rate, 0.0, 1.0) if data != null else 0.0


func _show() -> void:
	var count := _bars.size()
	var cool := cooling()
	var level := charge
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
	if charge > 0.0:
		return "CHARGE %s %d%%" % [_bar(charge), roundi(charge * 100.0)]
	if cooling() > 0.0:
		return "COOLING %s %.1f s" % [_bar(1.0 - cooling()), _cooldown]
	return "READY"
