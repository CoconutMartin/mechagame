class_name Missile
extends Node3D
## A homing missile. It leaves the pod with a push, then speeds up and turns toward its target
## (or flies at the aim point when it has no target). It explodes on contact, near the target,
## or at the end of its life.

const EXPLOSION := preload("res://scenes/effects/explosion.tscn")

## Seconds before the missile explodes on its own.
@export var lifetime: float = 6.0
## Seconds after launch before the missile starts to steer.
@export var arm_time: float = 0.25
## Speed gain in m/s per second.
@export var acceleration: float = 160.0
## Explodes this close to its target, in meters.
@export var proximity: float = 3.0
## Layers the missile hits: 1 world, 2 mechs, 3 props.
@export_flags_3d_physics var collision_mask: int = 7

var velocity: Vector3 = Vector3.ZERO
var target: Node3D = null
var aim_point: Vector3 = Vector3.ZERO
var top_speed: float = 90.0
var turn_rate: float = 110.0

var _age: float = 0.0
var _exclude: Array[RID] = []


func launch(start_velocity: Vector3, homing_target: Node3D, point: Vector3, speed: float, turn_deg: float, shooter: RID) -> void:
	velocity = start_velocity
	target = homing_target
	aim_point = point
	top_speed = speed
	turn_rate = turn_deg
	_exclude = [shooter]


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		_explode(global_position)
		return
	var goal := aim_point
	if is_instance_valid(target):
		goal = target.get_lock_point() if target.has_method(&"get_lock_point") else target.global_position
	if _age > arm_time:
		var wanted := (goal - global_position).normalized()
		var current := velocity.normalized()
		var angle := current.angle_to(wanted)
		var step := minf(deg_to_rad(turn_rate) * delta, angle)
		if angle > 0.0001:
			var axis := current.cross(wanted)
			if axis.length_squared() > 0.000001:
				current = current.rotated(axis.normalized(), step)
		velocity = current * minf(velocity.length() + acceleration * delta, top_speed)
	else:
		velocity.y -= 9.8 * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit.position)
		return
	global_position = to
	if velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)
	if is_instance_valid(target) and global_position.distance_to(goal) < proximity:
		_explode(global_position)


func _explode(point: Vector3) -> void:
	var effect := EXPLOSION.instantiate() as Node3D
	get_parent().add_child(effect)
	effect.global_position = point
	if is_instance_valid(target) and target.global_position.distance_to(point) < 12.0 and target.has_method(&"on_hit"):
		target.on_hit(100.0)
	queue_free()
