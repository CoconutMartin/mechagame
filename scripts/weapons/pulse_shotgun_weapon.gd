class_name PulseShotgunWeapon
extends GunWeapon
## A one-hand electric pulse shotgun (Shotgun 2, user request 2026-11-01). Each shot is a square electric pulse: a
## square grid of pellets (data.pellets, rounded to a square: 9 = 3 x 3) on a square pattern of data.spread_deg half
## angle, with one glowing square frame (PulseShot) that flies with them. The three emitter heads open fully at each
## shot and close to their neutral place after; the emitter ring and the arc between the heads flash blue.
## data.fire_rate 2 = two shots a second. Uses a magazine like the other guns (a one-hand gun is raised only when its
## kind is GUN).

const PELLET := preload("res://scenes/weapons/pulse_pellet.tscn")

## Head nodes (their origins on the hinges, the gun's bore at the Muzzle marker's x and y).
@export var head_paths: Array[NodePath] = []
## Degrees each head swings out at a shot, seconds to open, seconds to close again.
@export var open_deg: float = 32.0
@export var open_time: float = 0.06
@export var close_time: float = 0.3
## Meshes that flash blue at a shot (the emitter ring).
@export var glow_paths: Array[NodePath] = []
@export var glow_color: Color = Color(0.35, 0.65, 1.0)
## The electric arc ring between the heads: shown for arc_time after a shot.
@export var arc_path: NodePath
@export var arc_time: float = 0.14

var _heads: Array[Node3D] = []
var _rest: Array[Basis] = []
var _axes: Array[Vector3] = []
## Seconds since the last shot (large = closed).
var _since_shot: float = 100.0
var _glow := ShotGlow.new()
var _arc: Node3D


func _ready() -> void:
	var bore := _muzzle.position if _muzzle != null else Vector3.ZERO
	for path in head_paths:
		var node := get_node(path) as Node3D
		_heads.append(node)
		_rest.append(node.transform.basis)
		# The head's front moves out from the bore: turn about the tangent (forward x radial).
		var radial := Vector3(node.position.x - bore.x, node.position.y - bore.y, 0.0).normalized()
		_axes.append(Vector3.FORWARD.cross(radial).normalized())
	_glow.color = glow_color
	_glow.hold = 0.05
	_glow.fade = 0.25
	_glow.energy = 4.0
	add_child(_glow)
	var meshes: Array[MeshInstance3D] = []
	for path in glow_paths:
		meshes.append(get_node(path) as MeshInstance3D)
	_glow.setup(meshes)
	_arc = get_node_or_null(arc_path) as Node3D
	if _arc != null:
		_arc.visible = false


func _process(delta: float) -> void:
	_since_shot += delta
	var amount := 0.0
	if _since_shot < open_time:
		amount = _since_shot / open_time
	elif _since_shot < open_time + close_time:
		amount = 1.0 - (_since_shot - open_time) / close_time
	amount = smoothstep(0.0, 1.0, amount)
	for i in _heads.size():
		_heads[i].transform.basis = _rest[i].rotated(_axes[i], deg_to_rad(open_deg) * amount)
	if _arc != null:
		_arc.visible = _since_shot < arc_time
		if _arc.visible:
			_arc.rotation.z = randf() * TAU
			_arc.scale = Vector3.ONE * randf_range(0.95, 1.08)


## How far the heads are open now (0 = neutral, 1 = fully open).
func head_open_amount() -> float:
	if _since_shot < open_time:
		return smoothstep(0.0, 1.0, _since_shot / open_time)
	if _since_shot < open_time + close_time:
		return smoothstep(0.0, 1.0, 1.0 - (_since_shot - open_time) / close_time)
	return 0.0


func _fire() -> void:
	consume()
	var origin := _muzzle.global_position
	var aim := (controller.mech_aim.aim_point - origin).normalized()
	if aim.is_zero_approx():
		aim = -_muzzle.global_basis.z
	var side := aim.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(aim).normalized()
	var grid := maxi(roundi(sqrt(float(maxi(data.pellets, 1)))), 1)
	var shot := MechStability.new_shot_id()
	var spread := tan(deg_to_rad(data.spread_deg))
	var exclude := controller.mech.get_hit_exclude()
	for gx in grid:
		for gy in grid:
			var u := 0.0 if grid == 1 else lerpf(-1.0, 1.0, float(gx) / float(grid - 1))
			var v := 0.0 if grid == 1 else lerpf(-1.0, 1.0, float(gy) / float(grid - 1))
			var direction := (aim + (side * u + up * v) * spread).normalized()
			var pellet := PELLET.instantiate() as Bullet
			pellet.velocity = direction * data.projectile_speed
			pellet.exclude = exclude
			pellet.damage = data.damage
			pellet.weapon_data = data
			pellet.shot_id = shot
			pellet.lifetime = maxf(pellet.lifetime, data.range_m / maxf(data.projectile_speed, 1.0) + 0.5)
			controller.get_world().add_child(pellet)
			pellet.global_position = origin
			pellet.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	var look := PulseShot.new()
	look.velocity = aim * data.projectile_speed
	look.spread_deg = data.spread_deg
	look.range_m = data.range_m
	look.exclude = exclude
	controller.get_world().add_child(look)
	look.global_position = origin
	look.look_at(origin + aim, Vector3.UP if absf(aim.y) < 0.99 else Vector3.FORWARD)
	_since_shot = 0.0
	if _arc != null:
		_arc.visible = true
	_glow.flash()
	_after_shot()
