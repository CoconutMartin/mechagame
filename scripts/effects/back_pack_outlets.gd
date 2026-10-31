class_name BackPackOutlets
extends Node
## Boost outlets on a back pack (Boost Pack, user request 2026-10-31: "during boost, the outlets on the fins should
## glow and expel wind"). The pack model has Outlet1..N nodes (the wind leaves along each node's +Y axis, out of
## the grille) and OutletGlow1..N meshes (the grille recess plates). While the mech boosts, the plates glow and
## each outlet blows a stream of pale air puffs that stay behind in the world. BackPackMount adds this node when
## the model has an Outlet1 node.

## Glow color of the outlet plates at full boost (added over the plate).
@export var glow_color: Color = Color(1.0, 0.5, 0.15)
## Glow strength at full boost (0 to 1, the alpha of the added color).
@export var glow_strength: float = 0.9
## How fast the glow and wind start (1 / seconds).
@export var ignite_speed: float = 8.0
## How fast the glow and wind stop (1 / seconds).
@export var fade_speed: float = 3.0
## Wind puffs per second per outlet at full boost.
@export var wind_rate: float = 30.0
## Wind speed out of the grille (m/s).
@export var wind_speed: float = 14.0
## Spread of the wind cone (degrees).
@export var wind_spread_deg: float = 12.0
## How long a wind puff lasts (s).
@export var wind_life: float = 0.45
## Wind puff size at the grille and at the end of its life (m).
@export var wind_size_start: float = 0.35
@export var wind_size_end: float = 1.4
## Wind puff color and opacity at the start (it fades out over its life).
@export var wind_color: Color = Color(0.85, 0.9, 1.0, 0.35)

var mech: Mech
## 0 = off, 1 = full boost.
var amount: float = 0.0

var _model: Node3D
var _glow_material: StandardMaterial3D
var _winds: Array[CPUParticles3D] = []
static var _dot: GradientTexture2D


## Adds the outlets for a pack model (null when the model has no Outlet1 node).
static func attach(target: Mech, pack_model: Node3D) -> BackPackOutlets:
	if target == null or pack_model == null or pack_model.find_child("Outlet1", true, false) == null:
		return null
	var outlets := BackPackOutlets.new()
	outlets.name = "BackPackOutlets"
	outlets.mech = target
	outlets._model = pack_model
	target.add_child(outlets)
	return outlets


func _ready() -> void:
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.albedo_color = Color(glow_color, 0.0)
	var i := 1
	while true:
		var outlet := _model.find_child("Outlet%d" % i, true, false) as Node3D
		if outlet == null:
			break
		var glow := _model.find_child("OutletGlow%d" % i, true, false) as MeshInstance3D
		if glow != null:
			glow.material_overlay = _glow_material
		_winds.append(_make_wind(outlet))
		i += 1
	_apply()


func _make_wind(outlet: Node3D) -> CPUParticles3D:
	var wind := CPUParticles3D.new()
	wind.name = "Wind"
	wind.emitting = false
	wind.local_coords = false
	wind.amount = maxi(int(ceil(wind_rate * wind_life)) + 2, 4)
	wind.lifetime = wind_life
	wind.direction = Vector3.UP
	wind.spread = wind_spread_deg
	wind.gravity = Vector3.ZERO
	wind.initial_velocity_min = wind_speed * 0.8
	wind.initial_velocity_max = wind_speed * 1.2
	wind.damping_min = wind_speed * 0.8
	wind.damping_max = wind_speed * 1.2
	wind.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wind.emission_sphere_radius = 0.12
	wind.scale_amount_min = 1.0
	wind.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.max_value = maxf(wind_size_end / maxf(wind_size_start, 0.01), 1.0)
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, curve.max_value))
	wind.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, wind_color)
	ramp.set_color(1, Color(wind_color, 0.0))
	wind.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * wind_size_start
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	quad.material = material
	wind.mesh = quad
	outlet.add_child(wind)
	return wind


## A round soft dot texture for the wind puffs (made once).
static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		_dot = GradientTexture2D.new()
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		_dot.gradient = g
		_dot.width = 32
		_dot.height = 32
	return _dot


func _physics_process(delta: float) -> void:
	var on := is_instance_valid(_model) and _model.is_visible_in_tree() and mech.is_boosting and not mech.is_wrecked
	var target := 1.0 if on else 0.0
	amount = move_toward(amount, target, (ignite_speed if target > amount else fade_speed) * delta)
	_apply()


func _apply() -> void:
	_glow_material.albedo_color = Color(glow_color, glow_strength * amount)
	for wind in _winds:
		wind.emitting = amount > 0.2
		wind.speed_scale = 0.5 + 0.5 * amount
