class_name AttackDrone
extends AnimatableBody3D
## One flying attack drone (user design 2026-10-31; values in DroneData). DroneLauncher takes a drone model node
## (Drone<n>) off the back pack and gives it to launch. The drone pops out of its dock, flies to a place on its
## flank of the target (flank -1 or 1: a launched pair takes both flanks, a pincer), then fires bursts at the
## target's lock point from its hub (DroneMuzzle<n>), moving to a new semi-random place on the same flank after
## each burst. At max_flight_s, or when the target is gone after the approach, it explodes. Shot down at 0 HP
## (layer 4, "hitboxes": weapons call on_hit).

signal finished(drone: AttackDrone)

enum Phase { LAUNCH, APPROACH, ATTACK }

const BULLET := preload("res://scenes/weapons/bullet.tscn")
const EXPLOSION := preload("res://scenes/effects/explosion.tscn")

var data: DroneData
var target: Node3D
## The mech that launched it (its bullets do not hit that mech).
var launcher_mech: Mech
## -1 = the left flank of the target (seen from the launching mech), 1 = the right flank.
var flank: float = 1.0
var hp: float = 0.0
var phase: Phase = Phase.LAUNCH
## Seconds since the launch.
var age: float = 0.0
## Bursts fired so far.
var bursts_fired: int = 0
## The place the drone flies to now.
var goal: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Bullets fired so far.
var shots_fired: int = 0
## True when weapons destroyed it (false: its flight ended).
var shot_down: bool = false

var _model: Node3D
var _spin: Node3D
var _muzzle: Node3D
var _phase_time: float = 0.0
var _shot_wait: float = 0.0
var _last_target_point: Vector3 = Vector3.ZERO
var _exclude: Array[RID] = []
## The burst whose move has started (a new place once per burst).
var _moved_cycle: int = 0
## The target point the goal was last moved with.
var _follow_from: Vector3 = Vector3.INF


## Makes a flying drone from model (a Drone<n> node on the pack) in world. side: -1 = the model's outer face
## (and hub) is at its -X, 1 = at +X.
static func launch(world: Node, model: Node3D, side: float, mech: Mech, aim_target: Node3D, pincer_flank: float,
		drone_data: DroneData) -> AttackDrone:
	var drone := AttackDrone.new()
	drone.name = "AttackDrone"
	drone.data = drone_data
	drone.target = aim_target
	drone.launcher_mech = mech
	drone.flank = pincer_flank
	drone.hp = drone_data.hp
	drone.collision_layer = PartHitbox.LAYER
	drone.collision_mask = 0
	drone.sync_to_physics = false
	drone.add_to_group(&"attack_drones")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = drone_data.hit_radius
	shape.shape = sphere
	drone.add_child(shape)
	world.add_child(drone)
	var start := model.global_transform
	drone.global_position = start.origin
	# The spinner turns the disc about its axis; the body faces its -Z at the target, the hub on -Z.
	drone._spin = Node3D.new()
	drone._spin.name = "Spin"
	drone.add_child(drone._spin)
	model.reparent(drone._spin, false)
	model.transform = Transform3D(Basis(Vector3.UP, side * PI / 2.0), Vector3.ZERO)
	drone._model = model
	drone._muzzle = model.find_child("DroneMuzzle*", true, false) as Node3D
	drone.global_basis = Basis.looking_at(start.basis.x.normalized() * side, Vector3.UP)
	drone.velocity = start.basis.x.normalized() * side * drone_data.launch_speed + Vector3.UP * 4.0
	if mech != null:
		drone.velocity += mech.velocity
		drone._exclude = mech.get_hit_exclude()
	drone._exclude.append(drone.get_rid())
	drone._last_target_point = drone._target_point()
	return drone


func _physics_process(delta: float) -> void:
	age += delta
	_phase_time += delta
	if age >= data.max_flight_s:
		_explode()
		return
	if is_instance_valid(target) and target.is_inside_tree():
		_last_target_point = _target_point()
	elif phase == Phase.ATTACK:
		_explode()
		return
	match phase:
		Phase.LAUNCH:
			velocity = velocity.lerp(Vector3.ZERO, clampf(delta * 2.0, 0.0, 1.0))
			if _phase_time >= data.launch_time:
				_set_phase(Phase.APPROACH)
				goal = _flank_place(Vector3.INF)
		Phase.APPROACH:
			goal = _follow(goal)
			_steer_to(goal, maxf(data.approach_time - age, 0.15), delta)
			if age >= data.approach_time:
				_set_phase(Phase.ATTACK)
		Phase.ATTACK:
			_attack(delta)
	global_position += velocity * delta
	_face(delta)


func _attack(delta: float) -> void:
	var cycle := int(_phase_time / maxf(data.cycle_time, 0.05))
	if cycle >= data.bursts:
		_explode()
		return
	if cycle + 1 > bursts_fired:
		bursts_fired = cycle + 1
		_shot_wait = 0.0
	var in_cycle := fmod(_phase_time, data.cycle_time)
	goal = _follow(goal)
	if in_cycle < data.burst_time:
		# Fire and hold the place.
		_steer_to(goal, 0.3, delta)
		_shot_wait -= delta
		while _shot_wait <= 0.0:
			_fire()
			_shot_wait += 1.0 / maxf(data.gun.fire_rate, 0.1)
		return
	# Then move to a new place on the same flank.
	if _moved_cycle != bursts_fired:
		_moved_cycle = bursts_fired
		goal = _flank_place(goal)
	_steer_to(goal, maxf(data.cycle_time - in_cycle, 0.15), delta)


func _set_phase(next: Phase) -> void:
	phase = next
	_phase_time = 0.0


## Moves the goal with the target (the place is kept relative to the target).
func _follow(place: Vector3) -> Vector3:
	if not is_instance_valid(target):
		return place
	var now := _target_point()
	var moved := now - _follow_from
	_follow_from = now
	return place + moved



## Speed toward place so the drone gets there in about seconds (no faster than max_speed).
func _steer_to(place: Vector3, seconds: float, delta: float) -> void:
	var wanted := (place - global_position) / maxf(seconds, 0.05)
	wanted = wanted.limit_length(data.max_speed)
	velocity = velocity.lerp(wanted, clampf(delta * data.steer, 0.0, 1.0))


## A semi-random place on the drone's flank of the target, at least min_move_m from last (Vector3.INF = none).
func _flank_place(last: Vector3) -> Vector3:
	var center := _last_target_point
	_follow_from = center
	var from := launcher_mech.global_position if is_instance_valid(launcher_mech) else global_position
	var back := from - center
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var best := center
	for i in 6:
		# Turning back (target -> mech) about up by a positive angle goes to the mech's right: flank 1 = right.
		var angle := deg_to_rad(randf_range(data.flank_angle_min, data.flank_angle_max)) * flank
		var place := center + back.rotated(Vector3.UP, angle) * randf_range(data.attack_distance_min,
				data.attack_distance_max) + Vector3.UP * randf_range(data.height_min, data.height_max)
		best = place
		if not last.is_finite() or place.distance_to(last) >= data.min_move_m:
			break
	return best


func _target_point() -> Vector3:
	return target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position


## The hub faces the target (the flight direction during the launch); the disc spins about its axis.
func _face(delta: float) -> void:
	var look := (_last_target_point - global_position) if phase != Phase.LAUNCH else velocity
	if look.length() > 0.1:
		var wanted := Basis.looking_at(look.normalized(), Vector3.UP if absf(look.normalized().y) < 0.99 else Vector3.BACK)
		global_basis = global_basis.slerp(wanted, clampf(delta * 10.0, 0.0, 1.0)).orthonormalized()
	_spin.rotate_object_local(Vector3.FORWARD, deg_to_rad(data.spin_deg_per_s) * delta)


func _fire() -> void:
	var gun := data.gun
	var origin := _muzzle.global_position if _muzzle != null else global_position
	var aim := (_last_target_point - origin).normalized()
	var direction := MechWeapon.spread_direction(aim, gun.spread_deg)
	var bullet := BULLET.instantiate() as Bullet
	bullet.velocity = direction * gun.projectile_speed
	bullet.exclude = _exclude
	bullet.damage = gun.damage
	bullet.weapon_data = gun
	bullet.shot_id = MechStability.new_shot_id()
	bullet.lifetime = maxf(bullet.lifetime, gun.range_m / maxf(gun.projectile_speed, 1.0) + 0.5)
	get_parent().add_child(bullet)
	bullet.global_position = origin
	bullet.look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	shots_fired += 1



## A hit from any weapon (bullets, beams, blasts, melee).
func on_hit(damage: float, _from: Vector3 = Vector3.INF, _kind: StringName = &"") -> void:
	if hp <= 0.0:
		return
	hp -= damage
	if hp <= 0.0:
		shot_down = true
		_explode()



func _explode() -> void:
	if is_queued_for_deletion():
		return
	var effect := EXPLOSION.instantiate() as Explosion
	effect.flash_size = data.explosion_size
	get_parent().add_child(effect)
	effect.global_position = global_position
	finished.emit(self)
	queue_free()
