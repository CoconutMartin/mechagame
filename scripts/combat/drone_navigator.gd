class_name DroneNavigator
extends RefCounted
## Flight help for an AttackDrone (user rule 2026-10-31: "drones cannot fly through buildings"; "seek the target if
## it gets to cover"). steer_to turns the speed toward a goal: straight when the way is clear, else over the
## buildings (it climbs until it can fly level over them, then goes down to the goal). move applies the speed and
## stops the drone on any wall or roof (layers in DroneData.sight_mask), so it never passes through. find_place
## gives a firing place that sees the target.

var _drone: AttackDrone
var _data: DroneData
var _waypoint: Vector3 = Vector3.INF
var _waypoint_goal: Vector3 = Vector3.INF
var _waypoint_left: float = 0.0


func _init(drone: AttackDrone, drone_data: DroneData) -> void:
	_drone = drone
	_data = drone_data


## True when nothing in sight_mask lies between a and b.
static func clear(drone: Node3D, a: Vector3, b: Vector3, mask: int) -> bool:
	if a.is_equal_approx(b):
		return true
	var query := PhysicsRayQueryParameters3D.create(a, b, mask)
	return drone.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## True when a drone at place sees point (no wall or building between).
static func sees(drone: AttackDrone, place: Vector3, point: Vector3) -> bool:
	return clear(drone, place, point, drone.data.sight_mask)


## Speed toward goal: there in about seconds on a clear way, at full speed around buildings.
func steer_to(goal: Vector3, seconds: float, delta: float) -> void:
	var pos := _drone.global_position
	_waypoint_left -= delta
	if _waypoint_left <= 0.0 or not _waypoint.is_finite() or goal.distance_to(_waypoint_goal) > 2.0:
		_waypoint_left = _data.path_check_time
		_waypoint_goal = goal
		_waypoint = _find_waypoint(pos, goal)
	var wanted: Vector3
	if _waypoint.distance_to(goal) < 2.0:
		wanted = (goal - pos) / maxf(seconds, 0.05)
	else:
		wanted = (_waypoint - pos).normalized() * _data.max_speed
		# Close to a waypoint: look for the next one now.
		if pos.distance_to(_waypoint) < 1.5:
			_waypoint_left = 0.0
	wanted = wanted.limit_length(_data.max_speed)
	_drone.velocity = _drone.velocity.lerp(wanted, clampf(delta * _data.steer, 0.0, 1.0))


## The next point on the way to goal: goal itself when the way is clear; the point over goal when the drone is
## high enough to fly level to it; else a point straight up from the drone, as low as lets it fly over.
func _find_waypoint(pos: Vector3, goal: Vector3) -> Vector3:
	var mask := _data.sight_mask
	if _clear_tube(pos, goal):
		return goal
	var over := Vector3(goal.x, pos.y, goal.z)
	if pos.y > goal.y and _clear_tube(pos, over) and clear(_drone, over, goal, mask):
		return over
	var h := _data.climb_step
	while h <= _data.climb_max:
		var up := pos + Vector3.UP * h
		if not clear(_drone, pos, up, mask):
			break
		var above_goal := Vector3(goal.x, up.y, goal.z)
		if _clear_tube(up, goal) or (_clear_tube(up, above_goal) and clear(_drone, above_goal, goal, mask)):
			return up
		h += _data.climb_step
	# No way over found: climb anyway.
	return pos + Vector3.UP * _data.climb_step


## A clear way for the drone's body: the center line and two lines one hit radius above and below it.
func _clear_tube(a: Vector3, b: Vector3) -> bool:
	var r := Vector3.UP * (_data.hit_radius + 0.3)
	var mask := _data.sight_mask
	return clear(_drone, a, b, mask) and clear(_drone, a + r, b + r, mask) and clear(_drone, a - r, b - r, mask)


## Moves the drone by its speed, stopping at walls and roofs (it slides along them).
func move(delta: float) -> void:
	var space := _drone.get_world_3d().direct_space_state
	var pos := _drone.global_position
	for i in 2:
		var step := _drone.velocity * delta
		var length := step.length()
		if length < 0.0001:
			break
		var dir := step / length
		var reach := length + _data.hit_radius
		var query := PhysicsRayQueryParameters3D.create(pos, pos + dir * reach, _data.sight_mask)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			_drone.global_position = pos + step
			return
		# Stop short of the surface and slide: drop the speed into the surface.
		var normal: Vector3 = hit.normal
		var allowed := maxf((hit.position as Vector3).distance_to(pos) - _data.hit_radius, 0.0)
		pos += dir * minf(allowed, length)
		var into := _drone.velocity.dot(normal)
		if into < 0.0:
			_drone.velocity -= normal * into
		delta *= 1.0 - minf(allowed / length, 1.0)
	_drone.global_position = pos


## A firing place for a drone on its flank (-1 left, 1 right of the line from_pos -> center, seen from from_pos):
## within the gun range of center, in sight of it, in free air and over the ground. Tries the flank angles of
## DroneData first, then the whole flank, then the other flank. Picks the valid place nearest to near.
## Vector3.INF = none found.
static func find_place(drone: AttackDrone, data: DroneData, center: Vector3, from_pos: Vector3, flank: float,
		near: Vector3) -> Vector3:
	var back := from_pos - center
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var tiers := [[data.flank_angle_min, data.flank_angle_max, flank], [10.0, 175.0, flank], [10.0, 175.0, -flank]]
	for tier: Array in tiers:
		var best := Vector3.INF
		var best_distance := INF
		for i in data.place_tries:
			# Turning back (center -> mech) about up by a positive angle goes to the mech's right: flank 1 = right.
			var angle := deg_to_rad(randf_range(tier[0], tier[1])) * float(tier[2])
			var place := center + back.rotated(Vector3.UP, angle) * randf_range(data.attack_distance_min,
					data.attack_distance_max) + Vector3.UP * randf_range(data.height_min, data.height_max)
			if not _good_place(drone, data, place, center):
				continue
			var d := place.distance_to(near)
			if d < best_distance:
				best = place
				best_distance = d
		if best.is_finite():
			return best
	return Vector3.INF


static func _good_place(drone: AttackDrone, data: DroneData, place: Vector3, center: Vector3) -> bool:
	if place.distance_to(center) > data.gun.range_m - 1.0 or not sees(drone, place, center):
		return false
	var space := drone.get_world_3d().direct_space_state
	# Free air around the place.
	var shape := SphereShape3D.new()
	shape.radius = data.place_clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, place)
	query.collision_mask = data.sight_mask
	if not space.intersect_shape(query, 1).is_empty():
		return false
	# Over the ground or a roof (not under the map).
	var down := PhysicsRayQueryParameters3D.create(place, place + Vector3.DOWN * 80.0, data.sight_mask)
	return not space.intersect_ray(down).is_empty()
