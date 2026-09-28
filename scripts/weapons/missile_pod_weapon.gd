class_name MissilePodWeapon
extends MechWeapon
## A missile pod on the back. Hold its key (Q = left, E = right) to lock targets: each target inside
## the lock box around the mech aim locks after lock_time (faster with a better head). Up to the
## FCS max locks (and the missiles left). Release: one missile per lock. No lock: one missile fires
## straight at the aim point. Uses ammo: the pod reloads one missile at a time (reload_time /
## magazine each), so it can lock and fire with the missiles it has, even while it reloads.
## A volley at locked targets entrenches the mech (it stops and braces). A free shot (no lock)
## does not.

const MISSILE := preload("res://scenes/weapons/missile.tscn")

## Seconds between missile launches in a volley.
@export var launch_interval: float = 0.12
## The mech stays entrenched this long after the last missile of a locked volley, in seconds.
@export var brace_after: float = 0.6
## Layers that block the lock line of sight (1 = world).
@export_flags_3d_physics var sight_mask: int = 1

## Locked targets, in lock order.
var locks: Array[Node3D] = []
## The target being locked now, and its lock progress (0 to 1).
var locking: Node3D = null
var lock_progress: float = 0.0

var _queue: Array = []
var _launch_wait: float = 0.0
var _next_tube: int = 0
## Time toward the next loaded missile.
var _trickle: float = 0.0


func is_lock_mode() -> bool:
	return trigger_held and ammo > 0


## True while the pod locks or launches (WeaponController keeps it as the active weapon).
func is_busy() -> bool:
	return trigger_held or not _queue.is_empty()


## One missile at a time instead of a full reload.
func start_reload() -> void:
	pass


func _update(delta: float) -> void:
	if ammo < data.magazine:
		_trickle += delta
		var each := data.reload_time / maxf(data.magazine, 1)
		if _trickle >= each:
			_trickle -= each
			ammo += 1
	else:
		_trickle = 0.0
	_update_launches(delta)
	if is_lock_mode():
		_update_locking(delta)
	elif trigger_released():
		_fire_volley()
	if not trigger_held:
		locking = null
		lock_progress = 0.0


func _update_locking(delta: float) -> void:
	# Drop locks that are gone or left the range.
	locks = locks.filter(func(t: Node3D) -> bool: return is_instance_valid(t) and _in_range(t))
	var max_locks := mini(controller.get_max_locks(), ammo)
	if locks.size() >= max_locks:
		locking = null
		return
	if locking == null or not _can_lock(locking):
		locking = _find_candidate()
		lock_progress = 0.0
	if locking == null:
		return
	lock_progress += delta * controller.get_lock_speed() / maxf(data.lock_time, 0.01)
	if lock_progress >= 1.0:
		locks.append(locking)
		locking = null
		lock_progress = 0.0


func _fire_volley() -> void:
	if ammo <= 0:
		locks.clear()
		return
	var targets: Array = locks.duplicate()
	var locked := not targets.is_empty()
	if not locked:
		targets = [null]  # Straight at the aim point.
	targets = targets.slice(0, ammo)
	if locked:
		controller.mech.brace(targets.size() * launch_interval + brace_after)
	for target in targets:
		_queue.append(target)
	consume(targets.size())
	locks.clear()
	_after_shot()


func _update_launches(delta: float) -> void:
	_launch_wait = maxf(_launch_wait - delta, 0.0)
	if _queue.is_empty() or _launch_wait > 0.0:
		return
	_launch_wait = launch_interval
	var target = _queue.pop_front()
	var tubes := find_children("Launch*", "Marker3D", false, false)
	var tube := tubes[_next_tube % tubes.size()] as Node3D if not tubes.is_empty() else self
	_next_tube += 1
	var missile := MISSILE.instantiate() as Missile
	controller.get_world().add_child(missile)
	missile.global_transform = tube.global_transform
	var aim_point := controller.mech_aim.aim_point
	missile.launch(-tube.global_basis.z * 30.0 + Vector3.UP * 10.0, target if is_instance_valid(target) else null,
			aim_point, data.projectile_speed, data.missile_turn_deg, controller.mech.get_hit_exclude())
	missile.damage = data.damage


func _find_candidate() -> Node3D:
	var best: Node3D = null
	var best_angle := data.lock_box_deg
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var target := node as Node3D
		if locks.has(target) or not _can_lock(target):
			continue
		var angle := _angle_from_aim(target)
		if angle <= best_angle:
			best = target
			best_angle = angle
	return best


func _can_lock(target: Node3D) -> bool:
	if not is_instance_valid(target) or not _in_range(target):
		return false
	if _angle_from_aim(target) > data.lock_box_deg:
		return false
	var from := controller.mech_aim.aim_origin.global_position
	var query := PhysicsRayQueryParameters3D.create(from, _lock_point(target), sight_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _in_range(target: Node3D) -> bool:
	var range_m := minf(data.range_m, controller.get_lock_range())
	return controller.mech.global_position.distance_to(target.global_position) <= range_m


func _angle_from_aim(target: Node3D) -> float:
	var from := controller.mech_aim.aim_origin.global_position
	return rad_to_deg(controller.mech_aim.aim_direction.angle_to((_lock_point(target) - from).normalized()))


static func _lock_point(target: Node3D) -> Vector3:
	return target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position


func get_status_text() -> String:
	var text := "%d / %d" % [ammo, data.magazine]
	if ammo < data.magazine:
		text += "  +%s" % _bar(_trickle / (data.reload_time / maxf(data.magazine, 1)))
	if trigger_held:
		text += "  LOCK %d/%d" % [locks.size(), mini(controller.get_max_locks(), ammo)]
	return text
