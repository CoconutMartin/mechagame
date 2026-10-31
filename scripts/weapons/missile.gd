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
@export var proximity: float = 3.5
## Terminal guidance: closer than this (meters) to its target, the missile turns faster,
## up to terminal_turn_multiplier times, so near targets are hit too.
@export var terminal_distance: float = 45.0
@export var terminal_turn_multiplier: float = 4.0
## Layers the missile hits: 1 world, 3 props, 4 hitboxes.
@export_flags_3d_physics var collision_mask: int = 29
## Blast radius in meters (Blast: full damage at the center, 30% at the edge).
@export var blast_radius: float = 8.0
## Road crater radius (meters) when it explodes on or just above the ground (Crater); 0 = none.
@export var crater_radius: float = 2.2

## Stagger points of the blast, the volley id and the volley cap (MechStability).
var stagger: float = 0.0
var shot_id: int = 0
var stagger_cap: float = 0.0
var velocity: Vector3 = Vector3.ZERO
var target: Node3D = null
var aim_point: Vector3 = Vector3.ZERO
var top_speed: float = 90.0
var turn_rate: float = 110.0
var damage: float = 150.0

var _age: float = 0.0
var _exclude: Array[RID] = []
## The mech that fired it (optional). Its exclude list is read again each step, so drones it launched after the
## missile left still are not hit (user rule 2026-10-31: own weapons never hit own drones).
var shooter_mech: Mech


func launch(start_velocity: Vector3, homing_target: Node3D, point: Vector3, speed: float, turn_deg: float, shooter: Array[RID]) -> void:
	velocity = start_velocity
	target = homing_target
	aim_point = point
	top_speed = speed
	turn_rate = turn_deg
	_exclude = shooter


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
		var turn := turn_rate
		if is_instance_valid(target):
			var closeness := terminal_distance / maxf(global_position.distance_to(goal), 1.0)
			turn *= clampf(closeness, 1.0, terminal_turn_multiplier)
		var step := minf(deg_to_rad(turn) * delta, angle)
		if angle > 0.0001:
			var axis := current.cross(wanted)
			if axis.length_squared() > 0.000001:
				current = current.rotated(axis.normalized(), step)
		velocity = current * minf(velocity.length() + acceleration * delta, top_speed)
	else:
		velocity.y -= 9.8 * delta
	if is_instance_valid(shooter_mech):
		_exclude = shooter_mech.get_hit_exclude()
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
	Blast.apply(get_world_3d(), point, blast_radius, damage, _exclude, Blast.MASK, stagger, shot_id, stagger_cap)
	_crater(point)
	queue_free()


## A crater when the blast is on or near the ground (within 2 m above it).
func _crater(point: Vector3) -> void:
	if crater_radius <= 0.0:
		return
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 2.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is GroundSlab:
		Crater.spawn(get_parent(), hit.position, crater_radius, hit.collider)
