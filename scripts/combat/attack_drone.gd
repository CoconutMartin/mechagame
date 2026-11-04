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
## burst, then hops about shift_hop (4.5 m, random direction and length, at most shift_max_s 0.5 s; user 2026-11-03) or glides to a new place (at least shift_distance_min from the old one, same flank, in range and in
## sight) and fires the next: 3 bursts = 3 position changes (user rule 2026-11-02, replaces "it does not move
## after the first shot"). It fires only while it sees the target and the port points at it. At max_flight_s,
## after its last move, or when the target is gone, it explodes; with the recall mod (return_home) the way home
## is its last move and DroneLauncher can launch it again. Shot down at 0 HP
## (layer 4, "hitboxes": weapons call on_hit; also while it flies home).
## Squad (user 2026-11-04): the drones of one launch start each burst together (DroneSquad) and so hop together.
## Way home (user 2026-11-04): it flies around the mech's body (a cylinder, DroneData.return_body_radius) to a stage
## point behind the dock along the pack's back normal, then straight in; the body is never crossed.

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
## True when the model is a copy of a pack drone (DroneData.unlimited): at the dock it is removed, the real one is
## on the pack.
var is_copy: bool = false
## The drones launched together (null = alone) and whether the squad no longer waits for this one.
var squad: DroneSquad
var sync_free: bool = false
## True when the FIRE phase is at the AIM step and the port is on the target (or the aim time ran out).
var aim_done: bool = false

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
## The dock's last place and speed on the way home (the dock moves with the mech).
var _dock_last: Vector3 = Vector3.INF
var _dock_velocity: Vector3 = Vector3.ZERO


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
	aim_done = false
	# A hard stop at the firing place (it may still fly fast when the approach time ran out).
	velocity *= data.shift_stop_keep


## The FIRE phase (user rule 2026-11-02): aim the port at the target, fire a burst, glide to a new place, again.
## Rounds leave only while the drone sees the target in range and the port points at it.
func _fire_phase(delta: float) -> void:
	_step_time += delta
	match step:
		Step.AIM:
			_hover(delta)
			aim_done = _aim_error_deg() <= data.aim_tolerance_deg or _step_time >= data.aim_max_s
			# The squad starts a burst together: wait for the others (a short time at most).
			if aim_done and (squad == null or squad.may_start_burst(self, bursts_fired, delta)):
				step = Step.BURST
				_step_time = 0.0
				_shot_wait = 0.0
				bursts_fired += 1
				sync_free = false
				aim_done = false
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


## For the squad: this drone's part in the barrier before burst number index (0-based).
func burst_state(index: int) -> DroneSquad.State:
	if phase == Phase.RETURN or sync_free or is_queued_for_deletion():
		return DroneSquad.State.PASSED
	if phase != Phase.FIRE:
		return DroneSquad.State.NOT_READY
	if bursts_fired > index:
		return DroneSquad.State.PASSED
	return DroneSquad.State.READY if step == Step.AIM and aim_done else DroneSquad.State.NOT_READY


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
	if data.shift_hop > 0.0:
		# A quick hop ends with a hard stop, so the drone does not coast past the new place.
		velocity *= data.shift_stop_keep
	if shifts_done >= data.bursts:
		_end_attack()
		return
	step = Step.AIM
	_step_time = 0.0
	aim_done = false


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


## Flies back to the dock (around buildings, under the ceiling, around the mech's body) and docks there. Lost when
## the dock is gone or the way takes longer than return_max_s. It stays a hit target on the way (same hit sphere).
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
	if not data.return_avoid_body:
		_nav.steer_to(home, maxf(distance / data.max_speed, 0.15), delta)
		_nav.move(delta)
		_pose(delta)
		return
	# The dock moves with the mech: the drone leads its aim by the dock's speed (a turning mech has a fast dock).
	if _dock_last.is_finite() and delta > 0.0:
		_dock_velocity = _dock_velocity.lerp((home - _dock_last) / delta, 0.5)
	_dock_last = home
	var back := dock_back()
	var behind := (global_position - home).dot(back)
	var lateral := ((global_position - home) - back * behind).length()
	# The last leg: inside the cone behind the dock, straight to the dock.
	var final_leg := behind > 0.3 and lateral <= data.return_cone_base + data.return_cone_slope * behind
	if final_leg:
		_fly_to(home, maxf(distance / data.max_speed, 0.15), delta, true)
		_nav.move(delta)
	else:
		var stage := _stage_point(home, back) + _dock_velocity * 0.15
		var waypoint := body_waypoint(global_position, stage)
		var waypoint_distance := global_position.distance_to(waypoint)
		var seconds := maxf(waypoint_distance / data.max_speed, 0.15) if waypoint.is_equal_approx(stage) \
				else waypoint_distance / data.max_speed
		if DroneNavigator.sweep(self, global_position, waypoint, data.hit_radius + data.skin, data.sight_mask) >= 1.0:
			_fly_to(waypoint, seconds, delta, waypoint.is_equal_approx(stage))
		else:
			_nav.steer_to(waypoint, seconds, delta)
		_nav.move(delta)
		_keep_off_body()
	_pose(delta)


## Speed toward point: there in about seconds, at most max_speed, plus the dock's speed when follow_dock.
func _fly_to(point: Vector3, seconds: float, delta: float, follow_dock: bool) -> void:
	var wanted := ((point - global_position) / maxf(seconds, 0.05)).limit_length(data.max_speed)
	if follow_dock:
		wanted += _dock_velocity
	velocity = velocity.lerp(wanted, clampf(delta * data.steer, 0.0, 1.0))


## The pack's back normal at the dock (world; the dock's +Z axis, the side away from the mech).
func dock_back() -> Vector3:
	if is_instance_valid(dock) and dock.is_inside_tree():
		return dock.global_basis.z.normalized()
	return launcher_mech.global_basis.z.normalized() if is_instance_valid(launcher_mech) else Vector3.BACK


## The point behind the dock the last leg starts from: return_stage_distance along the back normal, nearer when a
## wall is in the way.
func _stage_point(home: Vector3, back: Vector3) -> Vector3:
	var distance := data.return_stage_distance
	for i in 3:
		var stage := home + back * distance
		if DroneNavigator.clear(self, home, stage, data.sight_mask):
			return stage
		distance *= 0.6
	return home + back * distance


## The axis of the body cylinder (world, flat) and its radii: the clear radius (body + hit sphere) and the circle
## the drone flies on.
func _body_axis() -> Vector3:
	return launcher_mech.global_position if is_instance_valid(launcher_mech) else dock.global_position


func body_clear_radius() -> float:
	return data.return_body_radius + data.hit_radius


## Where to steer on the way to the stage point so the drone keeps off the body cylinder: the stage point itself
## when the line to it is clear of the cylinder, else a point on the circle around it, ahead in the shorter turn
## (a tangent point from far away, at least return_lookahead_deg ahead near it). The point changes each frame.
func body_waypoint(from: Vector3, stage: Vector3) -> Vector3:
	var center := _body_axis()
	var c := Vector2(center.x, center.z)
	var p := Vector2(from.x, from.z)
	var s := Vector2(stage.x, stage.z)
	var clear_radius := body_clear_radius()
	if _segment_distance(c, p, s) >= clear_radius + 0.05:
		return stage
	var orbit := clear_radius + data.return_orbit_margin
	var dist := maxf(p.distance_to(c), 0.01)
	var from_angle := (p - c).angle()
	var stage_angle := (s - c).angle()
	var turn := angle_difference(from_angle, stage_angle)
	var ahead := maxf(acos(clampf(orbit / dist, 0.0, 1.0)), deg_to_rad(data.return_lookahead_deg))
	var angle := stage_angle
	var share := 1.0
	if absf(turn) > ahead:
		angle = from_angle + signf(turn) * ahead
		share = ahead / absf(turn)
	var on_circle := c + Vector2.from_angle(angle) * orbit
	return Vector3(on_circle.x, lerpf(from.y, stage.y, share), on_circle.y)


## Shortest distance from point c to the segment a -> b (flat).
static func _segment_distance(c: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.0001:
		return a.distance_to(c)
	var t := clampf((c - a).dot(ab) / length_squared, 0.0, 1.0)
	return (a + ab * t).distance_to(c)


## Hard guard: the drone's center is never inside the body cylinder outside the last leg (a detour around a
## building, a turn of the mech can push it in).
func _keep_off_body() -> void:
	var center := _body_axis()
	var flat := Vector2(global_position.x - center.x, global_position.z - center.z)
	var clear_radius := body_clear_radius()
	if flat.length() >= clear_radius or global_position.y > center.y + 11.0 or global_position.y < center.y - 2.0:
		return
	var out := flat.normalized() if flat.length() > 0.01 else Vector2.from_angle(atan2(dock_back().z, dock_back().x))
	var pushed := Vector2(center.x, center.z) + out * clear_radius
	global_position = Vector3(pushed.x, global_position.y, pushed.y)
	var into := velocity.x * out.x + velocity.z * out.y
	if into < 0.0:
		velocity.x -= out.x * into
		velocity.z -= out.y * into


## Puts the model back on the pack (its place before the launch) and removes the flying body. A copy (unlimited
## pack) is removed; the real drone model is on the pack.
func _dock() -> void:
	if not is_instance_valid(_model):
		_explode()
		return
	if is_copy:
		_model.queue_free()
	else:
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


## A quick hop after a burst (user 2026-11-04: 4.5 m, "more random placements"): a random direction in the plane
## across the line of sight (any angle: sideways, up, down, diagonals) with some random forward or back part, a random
## length from shift_hop_min to shift_hop_max, with a clear path, under the ceiling, the target in sight and in range,
## and not back onto an earlier burst place. After shift_hop_tries random tries it tries half hops. False when none works.
func _pick_hop() -> bool:
	var to := _target_point - global_position
	var forward := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(forward).normalized()
	var tries: Array[Vector3] = []
	for i in data.shift_hop_tries:
		var angle := randf() * TAU
		var direction := side * cos(angle) + up * sin(angle) \
				+ forward * randf_range(-data.shift_hop_depth, data.shift_hop_depth)
		tries.append(direction.normalized() * randf_range(data.shift_hop_min, data.shift_hop_max))
	for i in data.shift_hop_tries:
		var angle := randf() * TAU
		tries.append((side * cos(angle) + up * sin(angle)) * data.shift_hop_min * 0.5)
	for offset in tries:
		var place := global_position + offset
		# Not back onto an earlier burst place.
		if DroneNavigator._near_any(place - _target_point, _used, data.shift_hop * 0.5):
			continue
		# Under the ceiling (an up hop over it would be cut short).
		if place.y > _nav.ceiling_at(place) - data.hit_radius - data.skin:
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
