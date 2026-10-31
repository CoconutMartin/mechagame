class_name AttackDrone
extends AnimatableBody3D
## One flying attack drone (user design 2026-10-31; values in DroneData). DroneLauncher takes a drone model node
## (Drone<n>) off the back pack and gives it to launch. The drone pops out of its dock and flies to a firing place
## on its flank of the target (flank -1 or 1: a launched pair takes both flanks, a pincer). A firing place is
## within the gun range of the target's lock point and sees it; when the target goes behind cover, the drone seeks
## a new place (the other flank only when its own has none). It flies around buildings: over them when the way is
## blocked, and it never passes through them (DroneNavigator). At the place it stops and fires its bursts from its
## hub (DroneMuzzle<n>); from the first shot it does not move again (user rule). It fires only while it sees the
## target. At max_flight_s, after its last burst, or when the target is gone, it explodes. Shot down at 0 HP
## (layer 4, "hitboxes": weapons call on_hit).

signal finished(drone: AttackDrone)

enum Phase { LAUNCH, APPROACH, FIRE }

const BULLET := preload("res://scenes/weapons/bullet.tscn")
const EXPLOSION := preload("res://scenes/effects/explosion.tscn")

var data: DroneData
var target: Node3D
## The mech that launched it (its weapons do not hit that mech or its drones).
var launcher_mech: Mech
## -1 = the left flank of the target (seen from the launching mech), 1 = the right flank.
var flank: float = 1.0
var hp: float = 0.0
var phase: Phase = Phase.LAUNCH
## Seconds since the launch.
var age: float = 0.0
## Age at the first shot (-1 = not yet).
var fire_start_age: float = -1.0
## Bursts started so far.
var bursts_fired: int = 0
## The firing place the drone flies to (relative places follow the target until the fire starts).
var goal: Vector3 = Vector3.ZERO
## True when goal is a firing place that sees the target.
var has_place: bool = false
var velocity: Vector3 = Vector3.ZERO
## Bullets fired so far.
var shots_fired: int = 0
## True when weapons destroyed it (false: its flight ended).
var shot_down: bool = false

var _spin: Node3D
var _muzzle: Node3D
var _phase_time: float = 0.0
var _shot_wait: float = 0.0
var _target_point: Vector3 = Vector3.ZERO
## Goal minus the target point (the place moves with the target until the fire starts).
var _goal_offset: Vector3 = Vector3.ZERO
var _recheck_left: float = 0.0
var _nav: DroneNavigator


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
	drone._muzzle = model.find_child("DroneMuzzle*", true, false) as Node3D
	var out := start.basis.x.normalized() * side
	drone.global_basis = Basis.looking_at(out, Vector3.UP)
	drone.velocity = out * drone_data.launch_speed + Vector3.UP * 4.0
	if mech != null:
		drone.velocity += mech.velocity
	drone._nav = DroneNavigator.new(drone, drone_data)
	drone._target_point = drone._read_target_point()
	return drone


## Collision objects this drone's bullets must not hit: the launching mech, its hitboxes and its drones.
func _exclude() -> Array[RID]:
	var rids: Array[RID] = []
	if is_instance_valid(launcher_mech):
		rids = launcher_mech.get_hit_exclude()
	rids.append(get_rid())
	return rids


func _physics_process(delta: float) -> void:
	age += delta
	_phase_time += delta
	if age >= data.max_flight_s:
		_explode()
		return
	if is_instance_valid(target) and target.is_inside_tree() and target.is_in_group(&"lockable"):
		_target_point = _read_target_point()
	elif phase != Phase.LAUNCH:
		_explode()
		return
	match phase:
		Phase.LAUNCH:
			velocity = velocity.lerp(Vector3.ZERO, clampf(delta * 2.0, 0.0, 1.0))
			if _phase_time >= data.launch_time:
				_set_phase(Phase.APPROACH)
				_pick_place()
				_recheck_left = data.recheck_time
		Phase.APPROACH:
			_approach(delta)
		Phase.FIRE:
			_fire_phase(delta)
	if phase != Phase.FIRE:
		_nav.move(delta)
	_face(delta)


func _approach(delta: float) -> void:
	goal = _target_point + _goal_offset
	# The target may go behind cover: check the place now and then, and seek a new one when it is lost.
	_recheck_left -= delta
	if _recheck_left <= 0.0:
		_recheck_left = data.recheck_time
		if not has_place or not DroneNavigator.sees(self, goal, _target_point):
			_pick_place()
			goal = _target_point + _goal_offset
	var time_left := maxf(data.approach_time - age, 0.15)
	_nav.steer_to(goal, time_left, delta)
	# Fire from here when the place is reached (or the drone is already in range and sees the target).
	var close := global_position.distance_to(goal) < data.arrive_distance
	if (close or age >= data.approach_time) and _can_shoot_from(global_position):
		_start_fire()


## A firing place: within the gun range and in sight of the target point (DroneData).
func _can_shoot_from(place: Vector3) -> bool:
	return place.distance_to(_target_point) <= data.gun.range_m - 0.5 and DroneNavigator.sees(self, place, _target_point)


func _start_fire() -> void:
	_set_phase(Phase.FIRE)
	velocity = Vector3.ZERO
	fire_start_age = age
	bursts_fired = 0


## From the first shot the drone holds its place (user rule): a burst every cycle_time, rounds only while it sees
## the target in range.
func _fire_phase(delta: float) -> void:
	var cycle := int(_phase_time / maxf(data.cycle_time, 0.05))
	if cycle >= data.bursts:
		_explode()
		return
	if cycle + 1 > bursts_fired:
		bursts_fired = cycle + 1
		_shot_wait = 0.0
	if fmod(_phase_time, data.cycle_time) >= data.burst_time:
		return
	_shot_wait -= delta
	while _shot_wait <= 0.0:
		_shot_wait += 1.0 / maxf(data.gun.fire_rate, 0.1)
		if _can_shoot_from(global_position):
			_fire()


func _set_phase(next: Phase) -> void:
	phase = next
	_phase_time = 0.0


## Picks a firing place on the drone's flank (or the other flank when its own has none). Keeps the old goal when
## no place is found (it looks again at the next check).
func _pick_place() -> void:
	var from := launcher_mech.global_position if is_instance_valid(launcher_mech) else global_position
	var place := DroneNavigator.find_place(self, data, _target_point, from, flank, global_position)
	has_place = place.is_finite()
	if has_place:
		_goal_offset = place - _target_point
	elif _goal_offset == Vector3.ZERO:
		_goal_offset = (global_position - _target_point).normalized() * data.attack_distance_max


func _read_target_point() -> Vector3:
	return target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position


## The hub faces the target (the flight direction during the launch); the disc spins about its axis.
func _face(delta: float) -> void:
	var look := (_target_point - global_position) if phase != Phase.LAUNCH else velocity
	if look.length() > 0.1:
		var dir := look.normalized()
		var wanted := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK)
		global_basis = global_basis.slerp(wanted, clampf(delta * 10.0, 0.0, 1.0)).orthonormalized()
	_spin.rotate_object_local(Vector3.FORWARD, deg_to_rad(data.spin_deg_per_s) * delta)


func _fire() -> void:
	var gun := data.gun
	var origin := _muzzle.global_position if _muzzle != null else global_position
	var aim := (_target_point - origin).normalized()
	var direction := MechWeapon.spread_direction(aim, gun.spread_deg)
	var bullet := BULLET.instantiate() as Bullet
	bullet.velocity = direction * gun.projectile_speed
	bullet.exclude = _exclude()
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
