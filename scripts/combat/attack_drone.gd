class_name AttackDrone
extends AnimatableBody3D
## One flying attack drone (user design 2026-10-31; values in DroneData). DroneLauncher takes a drone model node
## (Drone<n>) off the back pack and gives it to launch. The drone pops out of its dock and flies to a firing place
## on its flank of the target (flank -1 or 1: a launched pair takes both flanks, a pincer). A firing place is
## within the gun range of the target's lock point, sees it and is at most 45 degrees below it (a mech on a roof
## above the ceiling too); when the target goes behind cover, the drone seeks
## a new place (the other flank only when its own has none); a place it finds no way to is dropped too. It flies at
## most 12.5 m over the ground, over low buildings and around tall ones, and never touches them (DroneNavigator).
## Saucer (user 2026-11-02): the disc flies level (its axis vertical) with a slight bank into its speed, a hover
## bob on the model only and a slow spin about the vertical axis. Its barrel is the port in the rim
## (DroneMuzzle<n>): when the drone attacks, the body turns so the port faces the target. At the place it fires a
## burst, then hops shift_hop (1 m, at most shift_max_s 0.5 s; user 2026-11-03) or glides to a new place (at least shift_distance_min from the old one, same flank, in range and in
## sight) and fires the next: 3 bursts = 3 position changes (user rule 2026-11-02, replaces "it does not move
## after the first shot"). It fires only while it sees the target and the port points at it. At max_flight_s,
## after its last move, or when the target is gone, it explodes; with the recall mod (return_home) the way home
## is its last move and DroneLauncher can launch it again. Shot down at 0 HP
## (layer 4, "hitboxes": weapons call on_hit).

signal finished(drone: AttackDrone)
## A returning drone (recall mod) is back on its dock; model is on the pack again.
signal docked(drone: AttackDrone, model: Node3D)

enum Phase { LAUNCH, APPROACH, FIRE, RETURN }
## Steps of the FIRE phase: AIM (the port turns to the target), BURST (rounds), SHIFT (glide to a new place).
enum Step { AIM, BURST, SHIFT }

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
## Position changes done so far (a move after a burst counts when the drone is at its new place).
var shifts_done: int = 0
## What the drone does in the FIRE phase.
var step: Step = Step.AIM
## The firing place the drone flies to (relative places follow the target until the fire starts).
var goal: Vector3 = Vector3.ZERO
## True when goal is a firing place that sees the target.
var has_place: bool = false
var velocity: Vector3 = Vector3.ZERO
## Bullets fired so far.
var shots_fired: int = 0
## True when weapons destroyed it (false: its flight ended).
var shot_down: bool = false
## Recall mod: after its attack it flies back to dock (a DroneDock<n> node on the pack) instead of exploding, and
## puts its model back under home_parent at home_transform.
var return_home: bool = false
var dock: Node3D
var home_parent: Node3D
var home_transform: Transform3D = Transform3D.IDENTITY
## Seconds of the way back.
var return_time: float = 0.0

var _spin: Node3D
var _muzzle: Node3D
var _phase_time: float = 0.0
var _step_time: float = 0.0
## Heading of the body (rotation about up; -Z forward), the spin of the disc on top of it, the lean (degrees, x and
## z of the lean direction), the phase of the hover bob and the side of the pack the drone came from.
var _yaw: float = 0.0
var _spin_angle: float = 0.0
var _lean: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0
var _side: float = 1.0
## The model's rotation on the pack, relative to the body at the launch (the pop out turns it flat).
var _dock_quat: Quaternion = Quaternion.IDENTITY
var _shot_wait: float = 0.0
var _target_point: Vector3 = Vector3.ZERO
## Goal minus the target point (the place moves with the target until the fire starts).
var _goal_offset: Vector3 = Vector3.ZERO
var _recheck_left: float = 0.0
var _nav: DroneNavigator
## Places (relative to the target) the drone found no way to; it does not pick them again.
var _avoid: PackedVector3Array = PackedVector3Array()
## Places (relative to the target) the drone fired a burst from; a new place is away from all of them.
var _used: PackedVector3Array = PackedVector3Array()
var _model: Node3D


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
	# The body only turns about up (heading) and leans; the spinner on it turns the disc about up. The model lies
	# flat in the spinner: its X axis (the disc axis) is up and its port (-Z) is the spinner's forward.
	drone._spin = Node3D.new()
	drone._spin.name = "Spin"
	drone.add_child(drone._spin)
	model.reparent(drone._spin, false)
	drone._model = model
	drone._muzzle = model.find_child("DroneMuzzle*", true, false) as Node3D
	drone._side = side
	var out := start.basis.x.normalized() * side
	drone._yaw = atan2(-out.x, -out.z)
	drone._bob_phase = randf() * TAU
	drone.global_basis = Basis(Vector3.UP, drone._yaw)
	drone._dock_quat = Quaternion((drone.global_basis.inverse() * start.basis).orthonormalized())
	drone._pose_model()
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
	if phase == Phase.RETURN:
		_return(delta)
		return
	if age >= data.max_flight_s:
		_end_attack()
		return
	if is_instance_valid(target) and target.is_inside_tree() and target.is_in_group(&"lockable"):
		_target_point = _read_target_point()
	elif phase != Phase.LAUNCH:
		_end_attack()
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
	_nav.move(delta)
	_pose(delta)


func _approach(delta: float) -> void:
	_steer_to_place(delta, maxf(data.approach_time - age, 0.15))
	# Fire from here when the place is reached (or the drone is already in range and sees the target).
	var close := global_position.distance_to(goal) < data.arrive_distance
	if (close or age >= data.approach_time) and _can_shoot_from(global_position):
		_start_fire()


## Steers to the firing place (it moves with the target). The target may go behind cover: the place is checked now
## and then, and a new one is sought when it is lost or when there is no way to it. seconds: the time constant of
## the glide (the drone is there in about this time on a clear way).
func _steer_to_place(delta: float, seconds: float) -> void:
	goal = _target_point + _goal_offset
	_recheck_left -= delta
	if _recheck_left <= 0.0:
		_recheck_left = data.recheck_time
		if not has_place or not DroneNavigator.sees(self, goal, _target_point):
			_pick_place()
			goal = _target_point + _goal_offset
	_nav.steer_to(goal, seconds, delta)
	# No way to the place (shut in under the ceiling): drop it and seek another.
	if _nav.blocked_time >= data.unreachable_time:
		_avoid.append(_goal_offset)
		_nav.blocked_time = 0.0
		_pick_place()
		goal = _target_point + _goal_offset


## A firing place: within the gun range and in sight of the target point (DroneData).
func _can_shoot_from(place: Vector3) -> bool:
	return place.distance_to(_target_point) <= data.gun.range_m - 0.5 \
			and DroneNavigator.tilt_ok(data, place, _target_point) and DroneNavigator.sees(self, place, _target_point)


func _start_fire() -> void:
	_set_phase(Phase.FIRE)
	step = Step.AIM
	_step_time = 0.0
	fire_start_age = age
	bursts_fired = 0
	shifts_done = 0


## The FIRE phase (user rule 2026-11-02): aim the port at the target, fire a burst, glide to a new place, again.
## Rounds leave only while the drone sees the target in range and the port points at it.
func _fire_phase(delta: float) -> void:
	_step_time += delta
	match step:
		Step.AIM:
			_hover(delta)
			if _aim_error_deg() <= data.aim_tolerance_deg or _step_time >= data.aim_max_s:
				step = Step.BURST
				_step_time = 0.0
				_shot_wait = 0.0
				bursts_fired += 1
				_used.append(global_position - _target_point)
		Step.BURST:
			_hover(delta)
			_shot_wait -= delta
			while _shot_wait <= 0.0 and _step_time < data.burst_time:
				_shot_wait += 1.0 / maxf(data.gun.fire_rate, 0.1)
				if _can_shoot_from(global_position) and _aim_error_deg() <= data.aim_tolerance_deg:
					_fire()
			if _step_time >= data.burst_time:
				_end_burst()
		Step.SHIFT:
			_shift(delta)


## The drone brakes (the glide ends smoothly) while it aims and fires.
func _hover(delta: float) -> void:
	velocity = velocity.lerp(Vector3.ZERO, clampf(delta * data.steer, 0.0, 1.0))


## After a burst the drone moves. With the recall mod the way home after the last burst is that move.
func _end_burst() -> void:
	if bursts_fired >= data.bursts and return_home and _can_dock():
		shifts_done += 1
		_end_attack()
		return
	step = Step.SHIFT
	_step_time = 0.0
	_recheck_left = data.recheck_time
	_pick_shift_place()


## Glides to the new place; the next burst (or the end of the attack after the last move) starts there.
func _shift(delta: float) -> void:
	_steer_to_place(delta, data.shift_pace)
	if global_position.distance_to(goal) >= data.shift_arrive and _step_time < data.shift_max_s:
		return
	shifts_done += 1
	if shifts_done >= data.bursts:
		_end_attack()
		return
	step = Step.AIM
	_step_time = 0.0


## The attack is over: back to the dock (recall mod), or it explodes.
func _end_attack() -> void:
	if return_home and _can_dock():
		_set_phase(Phase.RETURN)
		return_time = 0.0
		return
	_explode()


func _can_dock() -> bool:
	return is_instance_valid(dock) and dock.is_visible_in_tree() and is_instance_valid(home_parent) \
			and is_instance_valid(launcher_mech) and not launcher_mech.is_wrecked


## Flies back to the dock (around buildings, under the ceiling) and docks there. Lost when the dock is gone or the
## way takes longer than return_max_s.
func _return(delta: float) -> void:
	return_time += delta
	if not _can_dock() or return_time > data.return_max_s:
		_explode()
		return
	var home := dock.global_position
	var distance := global_position.distance_to(home)
	if distance <= data.dock_distance:
		_dock()
		return
	_nav.steer_to(home, maxf(distance / data.max_speed, 0.15), delta)
	_nav.move(delta)
	_pose(delta)


## Puts the model back on the pack (its place before the launch) and removes the flying body.
func _dock() -> void:
	if not is_instance_valid(_model):
		_explode()
		return
	_model.reparent(home_parent, false)
	_model.transform = home_transform
	docked.emit(self, _model)
	finished.emit(self)
	queue_free()


func _set_phase(next: Phase) -> void:
	phase = next
	_phase_time = 0.0


## Picks a firing place on the drone's flank (or the other flank when its own has none). Keeps the old goal when
## no place is found (it looks again at the next check).
func _pick_place() -> void:
	var from := launcher_mech.global_position if is_instance_valid(launcher_mech) else global_position
	var place := DroneNavigator.find_place(self, data, _target_point, from, flank, global_position, _avoid)
	has_place = place.is_finite()
	if has_place:
		_goal_offset = place - _target_point
	elif _goal_offset == Vector3.ZERO:
		_goal_offset = (global_position - _target_point).normalized() * data.attack_distance_max


## Picks the next firing place of the same flank, at least shift_distance_min from where the drone is. When there is
## none, the drone keeps its place.
func _pick_shift_place() -> void:
	if data.shift_hop > 0.0 and _pick_hop():
		return
	var from := launcher_mech.global_position if is_instance_valid(launcher_mech) else global_position
	var place := DroneNavigator.find_place(self, data, _target_point, from, flank, global_position, _avoid,
			global_position, data.shift_distance_min, _used)
	has_place = place.is_finite()
	_goal_offset = (place if has_place else global_position) - _target_point
	goal = _target_point + _goal_offset


## A quick hop of shift_hop to one side, up or down (in random order), with a clear path and the target still in
## sight. False when none works.
func _pick_hop() -> bool:
	var to := _target_point - global_position
	to.y = 0.0
	var side := to.normalized().cross(Vector3.UP) if to.length() > 0.1 else Vector3.RIGHT
	var choices: Array[Vector3] = [side, -side, Vector3.UP, Vector3.DOWN, (side + Vector3.UP).normalized(),
			(-side + Vector3.UP).normalized()]
	choices.shuffle()
	for direction in choices:
		var place := global_position + direction * data.shift_hop
		# Not back onto an earlier burst place.
		if DroneNavigator._near_any(place - _target_point, _used, data.shift_hop * 0.5):
			continue
		if DroneNavigator.clear(self, global_position, place, data.sight_mask) and _can_shoot_from(place):
			has_place = true
			_goal_offset = place - _target_point
			goal = place
			return true
	return false


func _read_target_point() -> Vector3:
	return target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position


## Degrees between the port's heading and the target (level; the port does not tilt up to aim).
func _aim_error_deg() -> float:
	var port := -_spin.global_basis.z
	var to := _target_point - global_position
	port.y = 0.0
	to.y = 0.0
	if port.length() < 0.01 or to.length() < 0.1:
		return 0.0
	return rad_to_deg(port.angle_to(to))


## The saucer pose: the body turns about up toward where it flies (the target while it attacks) and leans into its
## speed; the disc spins slowly about up until the drone attacks, then the spin returns to zero so the port faces
## the target; the model hovers up and down.
func _pose(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	var turn := 1.0 - exp(-data.turn_rate * delta)
	if phase == Phase.FIRE:
		var to := _target_point - global_position
		if Vector2(to.x, to.z).length() > 0.5:
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), turn)
		_spin_angle = lerp_angle(_spin_angle, 0.0, turn)
	else:
		if flat.length() > 1.0:
			_yaw = lerp_angle(_yaw, atan2(-flat.x, -flat.y), turn)
		_spin_angle = wrapf(_spin_angle + deg_to_rad(data.spin_deg_per_s) * delta, -PI, PI)
	var lean_wanted := (flat * (data.max_bank_deg / maxf(data.bank_full_speed, 0.1))).limit_length(data.max_bank_deg)
	_lean = _lean.lerp(lean_wanted, 1.0 - exp(-data.bank_smooth * delta))
	var tilt := Basis.IDENTITY
	if _lean.length() > 0.01:
		# Up leans toward the lean direction: a turn about (up x direction).
		tilt = Basis(Vector3.UP.cross(Vector3(_lean.x, 0.0, _lean.y)).normalized(), deg_to_rad(_lean.length()))
	global_basis = tilt * Basis(Vector3.UP, _yaw)
	_spin.rotation = Vector3(0.0, _spin_angle, 0.0)
	_pose_model()


## The model in the spinner: flat (its X axis up, the port forward) with the hover bob. The pop out turns it from
## its way on the pack to flat; the way home turns it back to its dock pose.
func _pose_model() -> void:
	if not is_instance_valid(_model):
		return
	var flat_q := Quaternion(Basis(Vector3.BACK, _side * PI / 2.0))
	var k := 1.0
	var q := flat_q
	if phase == Phase.LAUNCH:
		k = smoothstep(0.0, 1.0, _phase_time / maxf(data.launch_time, 0.05))
		q = _dock_quat.slerp(flat_q, k)
	elif phase == Phase.RETURN and is_instance_valid(home_parent) and is_instance_valid(dock):
		var distance := global_position.distance_to(dock.global_position)
		k = clampf((distance - data.dock_distance) / 3.0, 0.0, 1.0)
		var home_world := (home_parent.global_basis * home_transform.basis).orthonormalized()
		var home_q := Quaternion((_spin.global_basis.inverse() * home_world).orthonormalized())
		q = home_q.slerp(flat_q, k)
	_model.basis = Basis(q)
	_model.position = Vector3(0.0, sin(age * TAU * data.bob_hz + _bob_phase) * data.bob_height * k, 0.0)


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
