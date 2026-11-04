class_name BackPackOutlets
extends Node
## Boost outlets on a back pack (Boost Pack, user request 2026-10-31: "during boost, the outlets on the fins should
## glow and expel wind"; Quad Booster and Jet Pack nozzles the same). The pack model has Outlet1..N nodes (the exhaust
## leaves along each node's +Y axis, out of the grille or nozzle) and OutletGlow1..N meshes (the recess plates).
## While the mech boosts, rises on the jump jets or hops in a dodge, each outlet shows:
##  - a rocket exhaust plume (BoosterPlume, user request 2026-11-02: "make the fire coming out of the boosters for all
##    backpacks with boosters realistic"), longer and brighter with the thrust, with flicker, and a warm light;
##  - a gust of wind (BoosterGust, user request 2026-11-02: "wind from boost pack should look like a gust of wind, not
##    bubbles"): thin pale streaks of air that stay behind in the world;
##  - dust kicked up from the ground behind the mech while it boosts on the ground (BoosterDust);
##  - heat in the nozzle metal (NozzleHeat, user request 2026-11-02: "boosters should also heat up"): dark, dull
##    red, orange with use, then it cools down.
## BackPackMount adds this node when the model has an Outlet1 node.

## How fast the thrust and the wind start (1 / seconds).
@export var ignite_speed: float = 8.0
## How fast the thrust and the wind stop (1 / seconds).
@export var fade_speed: float = 3.0
## Plume thrust while boosting on the ground (0 to 1).
@export var ground_thrust: float = 0.8
## Plume thrust in the air (air boost, jump jets rising, dodge hop).
@export var air_thrust: float = 1.0
## Thrust at the start of a dodge hop (a short burst).
@export var dodge_burst: float = 1.4
## How fast the plume grows (1 / seconds).
@export var plume_ignite_speed: float = 12.0
## How fast the plume dies down (1 / seconds).
@export var plume_fade_speed: float = 6.0
## Random change of the plume length each frame (0 to 1).
@export var flicker: float = 0.16
## Plume length at full thrust, in outlet radii (the radius comes from the OutletGlow plate).
@export var plume_length_per_radius: float = 18.0
## Panel flame length at full thrust (m; packs with BackPackPart.panel_flame).
@export var panel_flame_length: float = 2.0
## Light energy at full thrust (0 = no light).
@export var light_energy: float = 0.5
## Gust streaks per second per outlet at full boost.
@export var wind_rate: float = 16.0
## Gust speed out of the outlet (m/s).
@export var wind_speed: float = 16.0
## Spread of the gust cone (degrees).
@export var wind_spread_deg: float = 7.0
## How long a gust streak lasts (s).
@export var wind_life: float = 0.6
## Length and width of a gust streak (m).
@export var wind_streak_length: float = 2.6
@export var wind_streak_width: float = 0.1
## Gust color and peak opacity (mostly transparent).
@export var wind_color: Color = Color(0.9, 0.95, 1.0, 0.32)

var mech: Mech
## 0 = off, 1 = on: boosting, jump jets rising or a dodge hop.
var amount: float = 0.0
## Plume thrust now (0 to dodge_burst).
var thrust: float = 0.0

var _model: Node3D
var _winds: Array[CPUParticles3D] = []
## The fire per outlet: BoosterPlume, or BoosterPanelFlame for a panel pack (both have set_thrust).
var _plumes: Array[Node3D] = []
var _part: BackPackPart
var _heat: NozzleHeat
var _dust: BoosterDust
var _light: OmniLight3D


## Adds the outlets for a pack model (null when the model has no Outlet1 node).
static func attach(target: Mech, pack_model: Node3D, part: BackPackPart = null) -> BackPackOutlets:
	if target == null or pack_model == null or pack_model.find_child("Outlet1", true, false) == null:
		return null
	var outlets := BackPackOutlets.new()
	outlets.name = "BackPackOutlets"
	outlets.mech = target
	outlets._model = pack_model
	outlets._part = part
	target.add_child(outlets)
	return outlets


func _ready() -> void:
	var panel := _part != null and _part.panel_flame
	_heat = NozzleHeat.attach(_model, NozzleHeat.blue_ramp() if panel else null)
	_dust = BoosterDust.attach(self)
	var center := Vector3.ZERO
	var count := 0
	var i := 1
	while true:
		var outlet := _model.find_child("Outlet%d" % i, true, false) as Node3D
		if outlet == null:
			break
		var radius := _outlet_radius(i)
		_winds.append(BoosterGust.make(outlet, radius, wind_rate, wind_speed, wind_spread_deg, wind_life,
				wind_streak_length, wind_streak_width, wind_color))
		if panel:
			var plate := _model.find_child("OutletGlow%d" % i, true, false) as MeshInstance3D
			_plumes.append(BoosterPanelFlame.attach(outlet, plate, _part.flame_color, panel_flame_length))
		else:
			_plumes.append(BoosterPlume.attach(outlet, radius, radius * plume_length_per_radius))
		center += outlet.position + outlet.basis.y * radius * 4.0
		count += 1
		i += 1
	if light_energy > 0.0 and count > 0:
		_light = OmniLight3D.new()
		_light.name = "BoosterLight"
		_light.light_color = _part.flame_color if panel else Color(1.0, 0.55, 0.2)
		_light.omni_range = 6.0
		_light.shadow_enabled = false
		_light.position = center / count
		_light.visible = false
		_light.add_to_group(BoosterPlume.SKIN_SKIP)
		_model.add_child(_light)
	if mech.dodge != null:
		mech.dodge.dodge_started.connect(_on_dodge_started)
	_apply()


## Half the size of the OutletGlow plate: the size of the nozzle or grille (m).
func _outlet_radius(index: int) -> float:
	var plate := _model.find_child("OutletGlow%d" % index, true, false) as MeshInstance3D
	if plate == null:
		return 0.2
	var size := plate.get_aabb().size
	var sizes := [size.x, size.y, size.z]
	sizes.sort()
	# The middle size: a round plate has two equal sizes, a thin slit plate its width.
	return clampf(float(sizes[1]) * 0.5, 0.1, 0.4)


func _on_dodge_started() -> void:
	# No fire for a dodge step or roll (a dodge clip; user 2026-11-04: "remove boost fire when dodge stepping"); only
	# the hop (no clip) bursts.
	if mech.dodge != null and mech.dodge.is_rolling():
		return
	thrust = maxf(thrust, dodge_burst)


func _physics_process(delta: float) -> void:
	var visible_pack := is_instance_valid(_model) and _model.is_visible_in_tree() and not mech.is_wrecked
	var target := BoosterFlames.target_thrust(mech, mech.dodge, ground_thrust, air_thrust) if visible_pack else 0.0
	var on := 1.0 if target > 0.0 else 0.0
	amount = move_toward(amount, on, (ignite_speed if on > amount else fade_speed) * delta)
	thrust = move_toward(thrust, target, (plume_ignite_speed if target > thrust else plume_fade_speed) * delta)
	if _heat != null:
		_heat.update(delta, thrust)
	_dust.follow(mech, thrust)
	_apply()


func _process(_delta: float) -> void:
	for plume in _plumes:
		plume.call(&"set_thrust", thrust, randf_range(-flicker, flicker))
	if _light != null:
		_light.visible = thrust > 0.02
		_light.light_energy = light_energy * thrust * randf_range(0.85, 1.15)


func _apply() -> void:
	for wind in _winds:
		wind.emitting = amount > 0.2
		wind.speed_scale = 0.5 + 0.5 * amount


## Nozzle heat now, 0 to 1 (for tests).
func get_heat() -> float:
	return _heat.heat if _heat != null else 0.0


## The nozzle heat (for tests).
func get_nozzle_heat() -> NozzleHeat:
	return _heat


## The ground dust (for tests).
func get_dust() -> BoosterDust:
	return _dust


## The exhaust plumes, one per outlet (for tests).
func get_plumes() -> Array[Node3D]:
	return _plumes
