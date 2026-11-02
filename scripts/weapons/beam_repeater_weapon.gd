class_name BeamRepeaterWeapon
extends GunWeapon
## A two-hand rapid-fire beam rifle (Beam Rifle 2, user choice 2026-11-01: rapid shots, no charge). While the
## trigger is held and the rifle is raised, it fires short beam bolts at data.fire_rate per second, from the
## middle barrel (Muzzle; user request 2026-11-01), or from muzzle_paths in turn when set. A bolt hits at once along the aim (no travel time) up to data.range_m. Each bolt adds heat
## (data.heat_per_use); at full heat the rifle overheats and fires again when it has cooled to zero.
## The glow meshes (the two rail bores) flash red at each shot (user request 2026-11-01).
## Beam Rifle 4 uses it as a sniper beam (user choice 2026-11-01): one heavy beam per shot, a long wait between
## shots (data.fire_rate), no heat (data.heat_per_use 0: the HUD shows READY or COOLING), the muzzle ring flashing
## orange.
## Heat glow (user 2026-11-02: the black ribbed coil on the barrel "should turn bright red when it reaches max heat
## levels"): heat_glow_paths meshes (the six barrel fins) go from dark at no heat, through a dull deep red, to bright red
## at full heat and overheat, and cool back down with the heat.
## It is a GunWeapon, so the drop, the dual-gun rules and the AI treat it like a gun.

const BEAM := preload("res://scenes/effects/beam_shot.tscn")
const IMPACT := preload("res://scenes/effects/impact_spark.tscn")
const MARK := preload("res://scenes/effects/bullet_mark.tscn")

## Layers a bolt hits: 1 world, 3 props, 4 hitboxes.
@export_flags_3d_physics var collision_mask: int = 29
## Muzzles that fire in turn, one bolt each. Empty = the Muzzle marker.
@export var muzzle_paths: Array[NodePath] = []
## Meshes that flash at each shot, their color, and the seconds fully lit and fading. Many shots in a row keep
## the glow up with a short hold and fade.
@export var glow_paths: Array[NodePath] = []
@export var glow_color: Color = Color(1.0, 0.08, 0.04)
@export var glow_hold: float = 0.05
@export var glow_fade: float = 0.3
## Meshes that glow with the heat (Beam Rifle 2: the ribbed coil on the barrel, Model/Fin0..5). Empty = none.
@export var heat_glow_paths: Array[NodePath] = []
## Glow color at the lowest visible heat (dull, deep red) and at full heat (bright red).
@export var heat_color_low: Color = Color(0.45, 0.02, 0.0)
@export var heat_color_high: Color = Color(1.0, 0.04, 0.02)
## Glow strength at full heat. Kept low: strong emission washes out to yellow or peach in Godot.
@export var heat_energy_max: float = 2.2
## Curve of the glow strength over the heat (0 to 1): 1 = linear, above 1 = dim until the heat is high.
@export_range(0.5, 4.0) var heat_energy_power: float = 1.6
## Color curve over the heat: 1 = linear, below 1 = the bright red comes sooner.
@export_range(0.5, 4.0) var heat_color_power: float = 1.3
## Thickness of a bolt's beam, in meters.
@export var bolt_width: float = 0.25
## Seconds a bolt's beam takes to fade.
@export var bolt_fade: float = 0.12
## Seconds between scorch marks on walls and the ground.
@export var mark_interval: float = 0.25

var _muzzles: Array[Node3D] = []
var _next_muzzle: int = 0
var _last_mark: float = 0.0
var _glow := ShotGlow.new()
var _heat_glow: Array[StandardMaterial3D] = []
var _heat_rest: Array[Color] = []


func _ready() -> void:
	for path in muzzle_paths:
		var muzzle := get_node_or_null(path) as Node3D
		if muzzle != null:
			_muzzles.append(muzzle)
	if _muzzles.is_empty() and _muzzle != null:
		_muzzles.append(_muzzle)
	_glow.color = glow_color
	_glow.hold = glow_hold
	_glow.fade = glow_fade
	add_child(_glow)
	var meshes: Array[MeshInstance3D] = []
	for path in glow_paths:
		meshes.append(get_node(path) as MeshInstance3D)
	_glow.setup(meshes)
	for path in heat_glow_paths:
		var material := ShotGlow.glow_material(get_node(path) as MeshInstance3D, heat_color_low)
		_heat_glow.append(material)
		_heat_rest.append(material.albedo_color)
	_show_heat()


func _update(delta: float) -> void:
	super._update(delta)
	_show_heat()


## The heat glow level now, 0 (cold) to 1 (full heat).
func heat_level() -> float:
	return clampf(heat / 100.0, 0.0, 1.0) if data != null and uses_heat() else 0.0


func _show_heat() -> void:
	if _heat_glow.is_empty():
		return
	var level := heat_level()
	var color := heat_color_low.lerp(heat_color_high, pow(level, heat_color_power))
	var energy := heat_energy_max * pow(level, heat_energy_power)
	for i in _heat_glow.size():
		var material := _heat_glow[i]
		material.emission = color
		material.emission_energy_multiplier = energy
		# The surface itself turns deep red too, so the sun does not wash the glow out to grey.
		material.albedo_color = _heat_rest[i].lerp(color * 0.35, level)


func _fire() -> void:
	consume()
	var muzzle := _muzzles[_next_muzzle % _muzzles.size()]
	_next_muzzle += 1
	var origin := muzzle.global_position
	var aim := (controller.mech_aim.aim_point - origin).normalized()
	if aim.is_zero_approx():
		aim = -muzzle.global_basis.z
	var direction := MechWeapon.spread_direction(aim, data.spread_deg)
	var end := origin + direction * data.range_m
	var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask, controller.mech.get_hit_exclude())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
		_impact(hit.position, hit.normal, hit.collider, data.damage * data.damage_factor(origin.distance_to(end)), origin)
	var beam := BEAM.instantiate() as BeamShot
	beam.width = bolt_width
	beam.duration = bolt_fade
	controller.get_world().add_child(beam)
	beam.show_beam(origin, end)
	_glow.flash()
	_after_shot()


func _impact(point: Vector3, normal: Vector3, body: Object, damage: float, origin: Vector3) -> void:
	var effect := IMPACT.instantiate() as Node3D
	controller.get_world().add_child(effect)
	effect.global_position = point
	effect.look_at(point + normal, Vector3.UP if absf(normal.y) < 0.99 else Vector3.FORWARD)
	if body != null and body.has_method(&"on_hit"):
		body.on_hit(damage, origin)
		if data.stagger_points > 0.0:
			MechStability.hit_body(body, data.stagger_points, MechStability.new_shot_id(), data.stagger_cap_per_shot,
					origin, data.stagger_hold_s)
	if body is Mech or body is TargetDummy or body is PartHitbox:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_mark < mark_interval:
		return
	_last_mark = now
	var mark := MARK.instantiate() as Node3D
	controller.get_world().add_child(mark)
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	mark.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point)


func get_status_text() -> String:
	if data == null or data.heat_per_use > 0.0:
		return super.get_status_text()
	# No heat: the wait between shots is the cool down.
	if _cooldown > 0.0:
		return "COOLING %s %.1f s" % [_bar(1.0 - _cooldown * data.fire_rate), _cooldown]
	return "READY"
