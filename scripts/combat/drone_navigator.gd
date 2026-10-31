class_name DroneNavigator
extends RefCounted
## Flight help for an AttackDrone (user rules 2026-10-31: "drones cannot fly through buildings", "seek the target
## if it gets to cover", "flight height max 12.5 m", "go around buildings higher than 12.5 m", "cannot touch building
## corners").
##   Ceiling: the drone stays at most DroneData.max_height over the ground under it (the first GroundSlab below).
##   Way: straight when a sphere of clear_radius sweeps clear to the goal; else over the low buildings at the cruise
##   height (the ceiling less clear_radius) when that is clear; else around the tall ones: a grid path (AStarGrid2D,
##   cells of path_cell m) at the cruise height, shortened where a sweep is clear, then down to the goal.
##   Move: the drone body (hit_radius + skin) sweeps each step and stops before any wall, roof or corner, then
##   slides along it, so it never touches one.
## find_place gives a firing place under the ceiling that sees the target, within the gun range and at most
## max_tilt_up_deg below it (a target on a roof above the ceiling can be attacked from under it).

## Cell solidity cache shared by all drones: key Vector3i(cell x, cruise height dm, cell z) -> [solid, time].
static var _cells: Dictionary = {}

var _drone: AttackDrone
var _data: DroneData
## The planned way: points to fly through, the goal last.
var _path: PackedVector3Array = PackedVector3Array()
var _path_goal: Vector3 = Vector3.INF
var _plan_left: float = 0.0
var _ground_y: float = 0.0
var _ground_left: float = 0.0
## Seconds the plans to the current goal have found no way (the goal may be shut in at this height).
var blocked_time: float = 0.0


func _init(drone: AttackDrone, drone_data: DroneData) -> void:
	_drone = drone
	_data = drone_data
	# Fallback ground: the pack is about 7.7 m over the launching mech's feet.
	var at := drone.global_position
	_ground_y = ground_height(drone, at, drone_data.sight_mask, at.y - 7.7)


## True when nothing in sight_mask lies on the line a -> b.
static func clear(drone: Node3D, a: Vector3, b: Vector3, mask: int) -> bool:
	if a.is_equal_approx(b):
		return true
	var query := PhysicsRayQueryParameters3D.create(a, b, mask)
	return drone.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## True when a drone at place aims at point with at most max_tilt_up_deg up (any angle down).
static func tilt_ok(data: DroneData, place: Vector3, point: Vector3) -> bool:
	var to := point - place
	var flat := Vector2(to.x, to.z).length()
	return to.y <= 0.0 or rad_to_deg(atan2(to.y, flat)) <= data.max_tilt_up_deg + 0.01


## True when a drone at place sees point (no wall or building between).
static func sees(drone: AttackDrone, place: Vector3, point: Vector3) -> bool:
	return clear(drone, place, point, drone.data.sight_mask)


## The safe part (0 to 1) of a sphere of radius moving a -> b: 1 = it touches nothing.
static func sweep(drone: Node3D, a: Vector3, b: Vector3, radius: float, mask: int) -> float:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, a)
	query.motion = b - a
	query.collision_mask = mask
	var space := drone.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return 0.0
	if query.motion.length_squared() < 0.000001:
		return 1.0
	var result := space.cast_motion(query)
	return result[0] if result.size() > 0 else 1.0


## Height of the ground (a GroundSlab) under place; roofs and floors above it are skipped. Without one: fallback.
static func ground_height(drone: Node3D, place: Vector3, mask: int, fallback: float) -> float:
	var space := drone.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var from := place + Vector3.UP * 0.5
	for i in 12:
		var query := PhysicsRayQueryParameters3D.create(from, Vector3(place.x, place.y - 300.0, place.z), mask | 1,
				exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return fallback
		if hit.collider is GroundSlab:
			return (hit.position as Vector3).y
		exclude.append(hit.rid)
	return fallback


## The highest the drone's center may be over place (the ground there + max_height).
func ceiling_at(place: Vector3) -> float:
	return ground_height(_drone, place, _data.sight_mask, _ground_y) + _data.max_height


## Radius of the sphere a way must sweep clear (the body, its skin and the corner margin).
func _clear_radius() -> float:
	return _data.hit_radius + _data.skin + _data.corner_margin


## Speed toward goal: there in about seconds on a clear way, at full speed along a longer way.
func steer_to(goal: Vector3, seconds: float, delta: float) -> void:
	var pos := _drone.global_position
	_plan_left -= delta
	if _plan_left <= 0.0 or _path.is_empty() or goal.distance_to(_path_goal) > 3.0:
		_plan_left = _data.path_check_time
		_path_goal = goal
		_path = plan(pos, goal)
		blocked_time = blocked_time + _data.path_check_time if _path.size() == 1 and not _path[0].is_equal_approx(goal) \
				and _path[0].distance_to(pos) < 0.5 else 0.0
	# Next point: drop the ones reached.
	while _path.size() > 1 and pos.distance_to(_path[0]) < 1.5:
		_path.remove_at(0)
	var wanted: Vector3
	if _path.size() <= 1:
		var last := goal if _path.is_empty() else _path[0]
		wanted = (last - pos) / maxf(seconds, 0.05)
	else:
		wanted = (_path[0] - pos).normalized() * _data.max_speed
	wanted = wanted.limit_length(_data.max_speed)
	_drone.velocity = _drone.velocity.lerp(wanted, clampf(delta * _data.steer, 0.0, 1.0))


## The way from pos to goal: [goal] when clear; over low buildings at the cruise height; else around the tall ones
## on a grid path. When no way is found: [pos] (it holds and plans again).
func plan(pos: Vector3, goal: Vector3) -> PackedVector3Array:
	var r := _clear_radius()
	var mask := _data.sight_mask
	if sweep(_drone, pos, goal, r, mask) >= 1.0:
		return PackedVector3Array([goal])
	var cruise := minf(ceiling_at(pos), ceiling_at(goal)) - _data.hit_radius - _data.skin
	var up := Vector3(pos.x, maxf(pos.y, cruise), pos.z)
	var over_goal := Vector3(goal.x, cruise, goal.z)
	var climb_ok := sweep(_drone, pos, up, r, mask) >= 1.0
	var start := up if climb_ok else pos
	if climb_ok and sweep(_drone, up, over_goal, r, mask) >= 1.0 and sweep(_drone, over_goal, goal, r, mask) >= 1.0:
		return PackedVector3Array([up, over_goal, goal])
	var around := _grid_path(start, goal, cruise)
	if around.is_empty():
		return PackedVector3Array([start])
	if climb_ok and not up.is_equal_approx(pos):
		around.insert(0, up)
	return around


## A grid path at height cruise from start to a free cell from which goal is reachable, shortened where a sweep is
## clear, with goal last. Empty when none.
func _grid_path(start: Vector3, goal: Vector3, cruise: float) -> PackedVector3Array:
	var cell := _data.path_cell
	var margin := _data.path_margin
	var lo := Vector2(minf(start.x, goal.x) - margin, minf(start.z, goal.z) - margin)
	var hi := Vector2(maxf(start.x, goal.x) + margin, maxf(start.z, goal.z) + margin)
	var origin := Vector2i(floori(lo.x / cell), floori(lo.y / cell))
	var size := Vector2i(ceili(hi.x / cell) - origin.x + 1, ceili(hi.y / cell) - origin.y + 1)
	if size.x * size.y > _data.path_max_cells:
		return PackedVector3Array()
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in size.x:
		for z in size.y:
			if _solid(origin + Vector2i(x, z), cruise):
				grid.set_point_solid(Vector2i(x, z))
	# Start and end at free cells the drone sweeps clear to (near a wall its own cell can be solid).
	var from_cell := _free_cell_near(grid, start, origin, cruise)
	var to_cell := _free_cell_near(grid, goal, origin, cruise)
	if from_cell.x < 0 or to_cell.x < 0:
		return PackedVector3Array()
	var cells := grid.get_id_path(from_cell, to_cell)
	if cells.is_empty():
		return PackedVector3Array()
	var points := PackedVector3Array()
	for c in cells:
		points.append(Vector3((origin.x + c.x + 0.5) * cell, cruise, (origin.y + c.y + 0.5) * cell))
	points.append(goal)
	return _shorten(start, points, _cell_center(from_cell, origin, cruise))


func _cell_of(place: Vector3, origin: Vector2i) -> Vector2i:
	var cell := _data.path_cell
	return Vector2i(floori(place.x / cell), floori(place.z / cell)) - origin


func _cell_center(c: Vector2i, origin: Vector2i, cruise: float) -> Vector3:
	var cell := _data.path_cell
	return Vector3((origin.x + c.x + 0.5) * cell, cruise, (origin.y + c.y + 0.5) * cell)


## The free cell nearest place (rings outward) whose center at the cruise height and place sweep clear to each
## other. Vector2i(-1, -1) = none.
func _free_cell_near(grid: AStarGrid2D, place: Vector3, origin: Vector2i, cruise: float) -> Vector2i:
	var center := _cell_of(place, origin)
	var cell := _data.path_cell
	for ring in 6:
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var c := center + Vector2i(dx, dz)
				if not grid.is_in_boundsv(c) or grid.is_point_solid(c):
					continue
				var p := Vector3((origin.x + c.x + 0.5) * cell, cruise, (origin.y + c.y + 0.5) * cell)
				if sweep(_drone, p, place, _data.hit_radius + _data.skin, _data.sight_mask) >= 1.0:
					return c
	return Vector2i(-1, -1)


## True when a cell has no free room at height cruise (cached for cell_cache_time seconds: buildings break).
func _solid(c: Vector2i, cruise: float) -> bool:
	var key := Vector3i(c.x, roundi(cruise * 10.0), c.y)
	var now := Time.get_ticks_msec() * 0.001
	if _cells.has(key) and now - float(_cells[key][1]) < _data.cell_cache_time:
		return _cells[key][0]
	var cell := _data.path_cell
	var shape := SphereShape3D.new()
	# Room for the way between two cell centers (a diagonal step passes within 0.71 cells of each center).
	shape.radius = cell * 0.75 + _clear_radius()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3((c.x + 0.5) * cell, cruise, (c.y + 0.5) * cell))
	query.collision_mask = _data.sight_mask
	var solid := not _drone.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	_cells[key] = [solid, now]
	return solid


## Drops the points the drone can skip: from each point it flies to the farthest later one it sweeps clear to.
## The first cell center stays when the start cannot skip it (the drone first gets there).
func _shorten(start: Vector3, points: PackedVector3Array, first: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var from := start
	var i := 0
	var r := _clear_radius()
	if sweep(_drone, start, first, r, _data.sight_mask) < 1.0:
		out.append(first)
		from = first
		i = 1
	while i < points.size():
		var best := i
		var j := mini(points.size() - 1, i + _data.path_shorten_reach)
		while j > i:
			if sweep(_drone, from, points[j], r, _data.sight_mask) >= 1.0:
				best = j
				break
			j -= 1
		out.append(points[best])
		from = points[best]
		i = best + 1
	return out


## Moves the drone by its speed under the ceiling. Its body (hit_radius + skin) sweeps each step and stops before
## any wall, roof or corner; then it slides along it.
func move(delta: float) -> void:
	_ground_left -= delta
	if _ground_left <= 0.0:
		_ground_left = 0.2
		_ground_y = ground_height(_drone, _drone.global_position, _data.sight_mask, _ground_y)
	var top := _ground_y + _data.max_height
	var body := _data.hit_radius + _data.skin
	var space := _drone.get_world_3d().direct_space_state
	var pos := _drone.global_position
	# Touching something already (a wall that appeared, a slide into a corner): out along the contact normal first,
	# and no speed into it.
	var push := _contact_normal(pos, body)
	if push != Vector3.ZERO:
		pos += push * _data.skin
		var into_wall := _drone.velocity.dot(push)
		if into_wall < 0.0:
			_drone.velocity -= push * into_wall
	for i in 2:
		var step := _drone.velocity * delta
		if pos.y + step.y > top:
			step.y = top - pos.y
			_drone.velocity.y = minf(_drone.velocity.y, 0.0)
		if step.length_squared() < 0.00000001:
			break
		# The body sweep, and a ray from the center as a second guard; a little short of the contact.
		var safe := minf(_sweep_motion(pos, step, body), _ray_safe(pos, step, body))
		safe = maxf(safe - 0.02, 0.0) if safe < 1.0 else 1.0
		pos += step * safe
		if safe >= 1.0:
			break
		# Slide: drop the speed into the surface (its normal from a slightly bigger sphere at the stop).
		var normal := _contact_normal(pos, body + 0.05)
		var into := _drone.velocity.dot(normal)
		if into < 0.0:
			_drone.velocity -= normal * into
		delta *= 1.0 - safe
	_drone.global_position = pos


## The safe part of the motion of the body sphere (it starts free; when it starts touching, only motions away).
func _sweep_motion(pos: Vector3, motion: Vector3, radius: float) -> float:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, pos)
	query.motion = motion
	query.collision_mask = _data.sight_mask
	var result := _drone.get_world_3d().direct_space_state.cast_motion(query)
	return result[0] if result.size() > 0 else 1.0


## The safe part of motion by a ray from the center that must stay radius short of any surface.
func _ray_safe(pos: Vector3, motion: Vector3, radius: float) -> float:
	var length := motion.length()
	var dir := motion / length
	var query := PhysicsRayQueryParameters3D.create(pos, pos + dir * (length + radius), _data.sight_mask)
	var hit := _drone.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return clampf(((hit.position as Vector3).distance_to(pos) - radius) / length, 0.0, 1.0)


func _contact_normal(pos: Vector3, radius: float) -> Vector3:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, pos)
	query.collision_mask = _data.sight_mask
	var info := _drone.get_world_3d().direct_space_state.get_rest_info(query)
	if info.is_empty():
		return Vector3.ZERO
	return info.normal


## A firing place for a drone on its flank (-1 left, 1 right of the line from_pos -> center, seen from from_pos):
## within the gun range of center, in sight of it, in free air, over the ground and under the ceiling. Tries the
## flank angles of DroneData first, then the whole flank, then the other flank. Picks the valid place nearest to
## near. Vector3.INF = none found.
static func find_place(drone: AttackDrone, data: DroneData, center: Vector3, from_pos: Vector3, flank: float,
		near: Vector3, avoid: PackedVector3Array = PackedVector3Array()) -> Vector3:
	var back := from_pos - center
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var tiers := [[data.flank_angle_min, data.flank_angle_max, flank], [10.0, 175.0, flank], [10.0, 175.0, -flank]]
	var ground := ground_height(drone, center, data.sight_mask, center.y - 5.0)
	var top := ground + data.max_height - data.hit_radius - data.skin
	for tier: Array in tiers:
		var best := Vector3.INF
		var best_distance := INF
		for i in data.place_tries:
			# Turning back (center -> mech) about up by a positive angle goes to the mech's right: flank 1 = right.
			var angle := deg_to_rad(randf_range(tier[0], tier[1])) * float(tier[2])
			var place := center + back.rotated(Vector3.UP, angle) * randf_range(data.attack_distance_min,
					data.attack_distance_max) + Vector3.UP * randf_range(data.height_min, data.height_max)
			place.y = minf(place.y, top)
			if not _good_place(drone, data, place, center) or _near_any(place - center, avoid, data.avoid_radius):
				continue
			var d := place.distance_to(near)
			if d < best_distance:
				best = place
				best_distance = d
		if best.is_finite():
			return best
	return Vector3.INF


## True when offset is within radius of any of the avoided offsets (places relative to the target).
static func _near_any(offset: Vector3, avoid: PackedVector3Array, radius: float) -> bool:
	for a in avoid:
		if a.distance_to(offset) < radius:
			return true
	return false


static func _good_place(drone: AttackDrone, data: DroneData, place: Vector3, center: Vector3) -> bool:
	if place.distance_to(center) > data.gun.range_m - 1.0 or not tilt_ok(data, place, center) \
			or not sees(drone, place, center):
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
	var down := PhysicsRayQueryParameters3D.create(place, place + Vector3.DOWN * 80.0, data.sight_mask | 1)
	return not space.intersect_ray(down).is_empty()
