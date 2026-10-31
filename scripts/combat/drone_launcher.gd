class_name DroneLauncher
extends Node
## Launches the attack drones of a drone back pack (user design 2026-10-31). The player holds T (action
## drone_launch) to lock a target: the "lockable" target nearest the mech aim inside the lock box, in range and in
## sight, locks after lock_time. Release T with a lock: drones_per_launch drones leave the pack, taken left and right
## in turn, outer first (a pair holds opposite flanks of the target, a pincer; AttackDrone). Release without a
## lock: nothing. Drones do not come back. BackPackMount adds it when the pack has DroneData and Drone<n> nodes.
## An AI pilot calls launch itself (AIDroneTactics).

signal launched(count: int)

## Layers that block the lock line of sight (1 = world, 5 = buildings).
@export_flags_3d_physics var sight_mask: int = 17

var mech: Mech
var data: DroneData
## Drone nodes still on the pack, per side (in launch order: top, middle, bottom).
var docked_left: Array[Node3D] = []
var docked_right: Array[Node3D] = []
## Drones in the air.
var flying: Array[AttackDrone] = []
## True while T is held.
var held: bool = false
## The locked target (null = none), the target being locked and its progress (0 to 1).
var locked: Node3D = null
var locking: Node3D = null
var lock_progress: float = 0.0
## Total drones the pack had.
var total: int = 0

var _next_left: bool = true


## Adds a DroneLauncher to mech for the pack model (nothing without DroneData or Drone nodes).
static func attach(target: Mech, model: Node3D, pack: BackPackPart) -> DroneLauncher:
	if target == null or model == null or pack == null or pack.drone == null:
		return null
	var launcher := DroneLauncher.new()
	launcher.name = "DroneLauncher"
	launcher.mech = target
	launcher.data = pack.drone
	for i in range(1, 25):
		var drone := model.find_child("Drone%d" % i, true, false) as Node3D
		if drone == null:
			break
		var dock := model.find_child("DroneDock%d" % i, true, false) as Node3D
		var side := (dock if dock != null else drone).position.x
		if side < 0.0:
			launcher.docked_left.append(drone)
		else:
			launcher.docked_right.append(drone)
	launcher.total = launcher.docked_left.size() + launcher.docked_right.size()
	if launcher.total == 0:
		launcher.free()
		return null
	target.add_child(launcher)
	return launcher


## Collision objects of the drones in the air (the mech's own weapons do not hit them).
func get_drone_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for drone in flying:
		if is_instance_valid(drone):
			rids.append(drone.get_rid())
	return rids


## Drones still on the pack.
func docked_count() -> int:
	return docked_left.size() + docked_right.size()


## The launcher of a mech, or null.
static func find(target: Node) -> DroneLauncher:
	return target.get_node_or_null(^"DroneLauncher") as DroneLauncher if target != null else null


func _unhandled_input(event: InputEvent) -> void:
	if mech == null or not mech.is_in_group(&"player") or not InputMap.has_action(&"drone_launch"):
		return
	if event.is_action_pressed(&"drone_launch", false):
		held = true
	elif event.is_action_released(&"drone_launch"):
		held = false
		if is_instance_valid(locked):
			launch(locked)
		_clear_lock()


func _physics_process(delta: float) -> void:
	for i in range(flying.size() - 1, -1, -1):
		if not is_instance_valid(flying[i]) or flying[i].is_queued_for_deletion():
			flying.remove_at(i)
	if held and docked_count() > 0:
		_update_lock(delta)
	elif not held:
		_clear_lock()


func _clear_lock() -> void:
	locked = null
	locking = null
	lock_progress = 0.0


func _update_lock(delta: float) -> void:
	if locked != null and not _can_lock(locked, false):
		locked = null
	if locked != null:
		return
	if locking == null or not _can_lock(locking, true):
		locking = _find_candidate()
		lock_progress = 0.0
	if locking == null:
		return
	lock_progress += delta / maxf(data.lock_time, 0.01)
	if lock_progress >= 1.0:
		locked = locking
		locking = null
		lock_progress = 0.0


## Launches up to drones_per_launch drones at target. Returns the number launched.
func launch(target: Node3D) -> int:
	if not is_instance_valid(target) or not mech.is_inside_tree():
		return 0
	var count := mini(data.drones_per_launch, docked_count())
	var world := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	for i in count:
		var take_left := _next_left
		if docked_left.is_empty():
			take_left = false
		elif docked_right.is_empty():
			take_left = true
		_next_left = not take_left
		var model: Node3D = docked_left.pop_front() if take_left else docked_right.pop_front()
		var side := -1.0 if take_left else 1.0
		# A pincer: each drone takes the flank of its side; left and right in turn give a pair both flanks.
		var drone := AttackDrone.launch(world, model, side, mech, target, side, data)
		flying.append(drone)
	if count > 0:
		launched.emit(count)
	return count


## The pack is gone: the drones on it go too (the flying ones keep flying).
func lose_docked() -> void:
	docked_left.clear()
	docked_right.clear()
	_clear_lock()


func _find_candidate() -> Node3D:
	var best: Node3D = null
	var best_angle := data.lock_box_deg
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var target := node as Node3D
		if not _can_lock(target, true):
			continue
		var angle := _angle_from_aim(target)
		if angle <= best_angle:
			best = target
			best_angle = angle
	return best


## True when target can be (box = true: is inside the lock box and) locked: in range and in sight.
func _can_lock(target: Node3D, box: bool) -> bool:
	if not is_instance_valid(target) or target == mech or not target.is_inside_tree():
		return false
	if not target.is_in_group(&"lockable"):
		return false
	if mech.global_position.distance_to(target.global_position) > data.lock_range_m:
		return false
	if box and _angle_from_aim(target) > data.lock_box_deg:
		return false
	var aim := _aim()
	if aim == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(aim.aim_origin.global_position, _lock_point(target), sight_mask)
	return get_viewport().world_3d.direct_space_state.intersect_ray(query).is_empty()


func _aim() -> MechAim:
	return mech.get_node_or_null(^"MechAim") as MechAim


func _angle_from_aim(target: Node3D) -> float:
	var aim := _aim()
	if aim == null:
		return 180.0
	var from := aim.aim_origin.global_position
	return rad_to_deg(aim.aim_direction.angle_to((_lock_point(target) - from).normalized()))


static func _lock_point(target: Node3D) -> Vector3:
	return target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position
