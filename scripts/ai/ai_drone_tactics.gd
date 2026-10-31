class_name AIDroneTactics
extends Node
## Attack drones for an AI pilot (user rule 2026-10-31: "AI can use drones, shoot drones if efficient, try to take
## cover if it cannot shoot down drones"). AIPilot makes it and calls it every physics frame.
##   Launch: with a drone pack (DroneLauncher), when it has seen its target for the lock time, the target is in
##   lock range and in sight, and its last drones are gone (or wait_between_launches has passed).
##   Threat: enemy drones that fly at this mech. It shoots the nearest one when that is efficient: its right weapon
##   is a gun with rounds, the drone is in its range and in sight, and the gun kills it in kill_time_max seconds
##   (counting the chance its spread hits the small drone: a heavy rifle or an auto cannon does, an SMG or a
##   shotgun does not).
##   Else it takes cover: it walks (boosts when far) to the nearest place close by that the drones cannot see.
##   It keeps cover until the drones are gone. With no cover near it goes on with its fight.

## Seconds between launches (random in this range); the next pair also waits for the last ones to be gone.
@export var wait_between_launches_min: float = 3.0
@export var wait_between_launches_max: float = 6.0
## Drones farther than this from the mech are no threat yet (m).
@export var threat_range: float = 70.0
## Shooting a drone is efficient when the gun kills it in this many seconds (its damage per second, no misses).
@export var kill_time_max: float = 1.5
## It fires at a drone when the torso points within this angle of it (degrees).
@export var fire_angle_deg: float = 8.0
## Cover search: distances from the mech (m) and directions per distance.
@export var cover_distances: PackedFloat32Array = PackedFloat32Array([8.0, 14.0, 20.0, 28.0, 36.0])
@export var cover_directions: int = 12
## Seconds between cover searches.
@export var cover_check_time: float = 0.5
## Boost to the cover when it is farther than this (m).
@export var cover_boost_distance: float = 18.0
## It counts as in cover this close to the cover place (m).
@export var cover_arrive: float = 3.0
## Layers that hide the mech from a drone (1 = world, 5 = buildings).
@export_flags_3d_physics var sight_mask: int = 17

enum Mode { NONE, SHOOT, COVER }

var mech: Mech
var input: MechInput
var mech_aim: MechAim
var weapons: WeaponController
## What it does about enemy drones now.
var mode: Mode = Mode.NONE
## The drone it shoots (SHOOT) and the cover place (COVER, Vector3.INF = none found).
var drone_target: AttackDrone
var cover: Vector3 = Vector3.INF
## Drones it launched so far.
var launched: int = 0

var _lock_seen: float = 0.0
var _launch_wait: float = 0.0
var _cover_left: float = 0.0


func setup(owner_mech: Mech, mech_input: MechInput, aim: MechAim, controller: WeaponController) -> void:
	mech = owner_mech
	input = mech_input
	mech_aim = aim
	weapons = controller
	_launch_wait = randf_range(0.0, wait_between_launches_min)


## Launches drones at target when it can (call every physics frame).
func update_launch(target: Node3D, sees: bool, delta: float) -> void:
	_launch_wait = maxf(_launch_wait - delta, 0.0)
	var launcher := DroneLauncher.find(mech)
	if launcher == null or launcher.docked_count() == 0 or target == null:
		_lock_seen = 0.0
		return
	var in_range := mech.global_position.distance_to(target.global_position) <= launcher.data.lock_range_m
	_lock_seen = _lock_seen + delta if sees and in_range else 0.0
	if _lock_seen < launcher.data.lock_time or _launch_wait > 0.0 or not launcher.flying.is_empty():
		return
	var count := launcher.launch(target)
	if count > 0:
		launched += count
		_lock_seen = 0.0
		_launch_wait = randf_range(wait_between_launches_min, wait_between_launches_max)


## Handles enemy drones. Returns true when it took over the moves and the fire this frame.
func drive(delta: float) -> bool:
	var threats := _threats()
	if threats.is_empty():
		mode = Mode.NONE
		drone_target = null
		cover = Vector3.INF
		_cover_left = 0.0
		return false
	drone_target = _efficient_drone(threats)
	if drone_target != null:
		mode = Mode.SHOOT
		_shoot(drone_target)
		return true
	# No cover near: it goes on with its fight (it does not stand still while the drones attack).
	if not _take_cover(threats, delta):
		mode = Mode.NONE
		return false
	mode = Mode.COVER
	return true


## Enemy drones that fly at this mech, near enough to matter.
func _threats() -> Array[AttackDrone]:
	var list: Array[AttackDrone] = []
	for node in get_tree().get_nodes_in_group(&"attack_drones"):
		var drone := node as AttackDrone
		if drone == null or drone.is_queued_for_deletion() or drone.target != mech or drone.launcher_mech == mech:
			continue
		if drone.global_position.distance_to(mech.global_position) <= threat_range:
			list.append(drone)
	return list


## The nearest drone its gun kills fast enough, in range and in sight; null when shooting is not efficient.
func _efficient_drone(threats: Array[AttackDrone]) -> AttackDrone:
	var gun := weapons.right_weapon if weapons != null else null
	# Judged from the gun and its rounds (a shot cooldown does not count: it holds SHOOT between shots).
	if not (gun is GunWeapon) or gun.data == null or gun.is_empty():
		return null
	var best: AttackDrone = null
	var best_distance := INF
	var origin := mech_aim.aim_origin.global_position
	for drone in threats:
		var distance := origin.distance_to(drone.global_position)
		if distance > gun.data.range_m or distance >= best_distance:
			continue
		if kill_time(gun.data, drone, distance) > kill_time_max:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, drone.global_position, sight_mask)
		if not mech.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = drone
		best_distance = distance
	return best


## Seconds a gun needs to shoot down drone at distance: the first shot at once, then one shot per 1 / fire_rate.
## Each pellet hits by the chance that the spread cone at that distance puts it in the drone's hit sphere.
static func kill_time(data: WeaponData, drone: AttackDrone, distance: float) -> float:
	var cone := maxf(distance * tan(deg_to_rad(data.spread_deg)), 0.001)
	var hit_chance := minf(pow(drone.data.hit_radius / cone, 2.0), 1.0)
	var per_shot := data.damage * data.damage_factor(distance) * maxf(data.pellets, 1) * hit_chance
	if per_shot <= 0.0:
		return INF
	var shots := ceilf(drone.hp / per_shot)
	return (shots - 1.0) / maxf(data.fire_rate, 0.01)


## Turns to the drone (leading a moving one) and fires when the torso points at it.
func _shoot(drone: AttackDrone) -> void:
	var gun := weapons.right_weapon
	var flight := drone.global_position.distance_to(mech_aim.aim_origin.global_position) \
			/ maxf(gun.data.projectile_speed, 1.0)
	var aim_at := drone.global_position + drone.velocity * flight
	var to := aim_at - mech.get_lock_point()
	input.aim_yaw = atan2(-to.x, -to.z)
	mech_aim.ai_target = aim_at
	var error := absf(wrapf(input.aim_yaw - mech.get_aim_yaw(), -PI, PI))
	var ready := error < deg_to_rad(fire_angle_deg) and gun.can_use()
	if weapons.right_data != null and weapons.right_data.two_handed:
		input.left_fire_held = ready
	else:
		input.fire_held = ready


## Walks to the nearest place the drones cannot see, and holds there. False: no cover found (it looks again after
## cover_check_time).
func _take_cover(threats: Array[AttackDrone], delta: float) -> bool:
	_cover_left -= delta
	if _cover_left <= 0.0:
		_cover_left = cover_check_time
		if not cover.is_finite() or not _hidden(cover, threats):
			cover = _find_cover(threats)
	if not cover.is_finite():
		return false
	var to := cover - mech.global_position
	to.y = 0.0
	if to.length() <= cover_arrive:
		return true
	var forward := to.normalized()
	input.aim_yaw = atan2(-forward.x, -forward.z)
	input.move_direction = forward
	input.forward_held = true
	input.boost_held = to.length() > cover_boost_distance
	return true


## The nearest reachable place around the mech that every drone's sight to it is blocked (the mech itself when it
## is hidden already). Vector3.INF = none.
func _find_cover(threats: Array[AttackDrone]) -> Vector3:
	var here := mech.global_position
	if _hidden(here, threats):
		return here
	var space := mech.get_world_3d().direct_space_state
	var chest := mech.get_lock_point() - here
	for distance in cover_distances:
		var best := Vector3.INF
		var best_cost := INF
		for i in cover_directions:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / float(cover_directions))
			var place := here + dir * distance
			# Reachable: a clear walk at knee and chest height, and ground under it.
			var knee := Vector3.UP * 2.0
			var walk := PhysicsRayQueryParameters3D.create(here + knee, place + knee, sight_mask)
			var walk_high := PhysicsRayQueryParameters3D.create(here + chest, place + chest, sight_mask)
			if not space.intersect_ray(walk).is_empty() or not space.intersect_ray(walk_high).is_empty():
				continue
			var down := PhysicsRayQueryParameters3D.create(place + knee, place + Vector3.DOWN * 3.0, sight_mask)
			var ground := space.intersect_ray(down)
			if ground.is_empty():
				continue
			place = ground.position
			if not _hidden(place, threats):
				continue
			var cost := distance
			if cost < best_cost:
				best = place
				best_cost = cost
		if best.is_finite():
			return best
	return Vector3.INF


## True when no drone sees the mech's chest and head at place.
func _hidden(place: Vector3, threats: Array[AttackDrone]) -> bool:
	var space := mech.get_world_3d().direct_space_state
	var chest := place + (mech.get_lock_point() - mech.global_position)
	for drone in threats:
		if not is_instance_valid(drone):
			continue
		for point in [chest, chest + Vector3.UP * 2.5]:
			var query := PhysicsRayQueryParameters3D.create(drone.global_position, point, sight_mask)
			if space.intersect_ray(query).is_empty():
				return false
	return true
