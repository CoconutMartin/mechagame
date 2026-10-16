class_name ShieldBash
extends Node
## The Hex Shield dash hits (user request 2026-10-16). While the shield dash runs, a box in front of
## the mech looks for the hitbox of another mech. On the first contact: damage to the closest part
## (once per dash), a push for the target and the dash stops short.
## MechDodge makes this node and calls begin() when the shield dash starts.
## Only the body counts (head, torso, groin, legs, and a shield): an arm or a gun that sticks out does not
## stop the dash, like the mech bodies that stop each other at about 5.2 m.
##
## Damage kind &"punch": the stagger rules (SkeletalStaggerAnimation) stun a mech hit on a torso part
## by a punch ("Receive torso punch", it stays standing) whatever the damage, and 500 damage in one hit
## knocks it down. A hit on an arm, a leg or the head by a bash is plain damage.

signal bashed(target: Mech, part_key: String)

const IMPACT := preload("res://scenes/effects/impact_spark.tscn")

@export var mech: Mech
@export var dodge: MechDodge
## Damage to the closest part (once per dash).
@export var damage: float = 150.0
## Damage kind passed to PartHitbox.on_hit.
@export var hit_kind: StringName = &"punch"
## The target slides this far (meters) in push_time seconds, slowing down evenly (it moves by its position:
## the full body hit reaction holds the target's own speed at zero).
@export var push_distance: float = 5.0
@export var push_time: float = 0.6
## The box starts this far ahead of the mech center and reaches this far (meters). The mech bodies stop each
## other at about 5.2 m between their centers: the front of a target torso is 3.6 m away then.
@export var reach_start: float = 1.0
@export var reach_end: float = 3.8
## Box width (meters, the shield is about 3.6 m wide) and the heights it covers above the mech's feet.
@export var width: float = 5.0
@export var height_low: float = 0.5
@export var height_high: float = 9.0
## Where the bash lands on the target: this far ahead of the mech center at chest height (meters).
@export var contact_ahead: float = 2.7
## The check stops once the dash is slower than this (m/s) after it was faster.
@export var min_speed: float = 3.0

## Parts that stop the dash.
const BODY_KEYS: Array[String] = ["Head", "Torso C", "Torso L", "Torso R", "Groin", "Leg L", "Leg R", "Shield"]

## Running pushes: {target, direction, speed}.
var _pushes: Array[Dictionary] = []
var _active: bool = false
var _was_fast: bool = false
var _box := BoxShape3D.new()


## The dash starts: one bash is allowed.
func begin() -> void:
	_active = true
	_was_fast = false


func _ready() -> void:
	# After MechDodge (-6), before the Mech (0).
	process_physics_priority = -5


func _physics_process(delta: float) -> void:
	_update_pushes(delta)
	if not _active:
		return
	var animation := dodge.animation
	if animation == null or not animation.is_shield_dash():
		_active = false
		return
	var speed := animation.get_speed()
	_was_fast = _was_fast or speed >= min_speed
	if _was_fast and speed < min_speed:
		_active = false
		return
	var hitbox := _find_target()
	if hitbox != null:
		_bash(hitbox, animation)


## The body hitbox of another mech that the box touches first, then the closest body hitbox of that mech to
## the contact point (a torso part most of the time, the shield when the target holds one up).
func _find_target() -> PartHitbox:
	var forward := _forward()
	var length := reach_end - reach_start
	_box.size = Vector3(width, height_high - height_low, length)
	var center := mech.global_position + forward * (reach_start + length * 0.5)
	center.y = mech.global_position.y + (height_low + height_high) * 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _box
	query.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), center)
	query.collision_mask = PartHitbox.LAYER
	query.exclude = mech.get_hit_exclude()
	var point := _contact_point(forward)
	var touched: Mech = null
	var touched_distance := INF
	for hit: Dictionary in mech.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var hitbox := hit.collider as PartHitbox
		if hitbox == null or hitbox.health == null or hitbox.health.mech == null or hitbox.part_key not in BODY_KEYS:
			continue
		var candidate := hitbox.health.mech
		if candidate == mech or candidate.is_wrecked:
			continue
		var distance := _center(hitbox).distance_to(point)
		if distance < touched_distance:
			touched_distance = distance
			touched = candidate
	if touched == null:
		return null
	var best: PartHitbox = null
	var best_distance := INF
	for key: String in BODY_KEYS:
		for hitbox: Variant in touched.health.hitboxes.get(key, []):
			if not is_instance_valid(hitbox):
				continue
			var distance := _center(hitbox as PartHitbox).distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = hitbox as PartHitbox
	return best


## Where the mech's dash direction points on the ground.
func _forward() -> Vector3:
	var forward := -mech.global_basis.z
	forward.y = 0.0
	return forward.normalized()


## World center of a hitbox shape.
func _center(hitbox: PartHitbox) -> Vector3:
	var shape := hitbox.get_child(0) as CollisionShape3D
	return hitbox.global_transform * shape.position


func _contact_point(forward: Vector3) -> Vector3:
	return mech.get_lock_point() + forward * contact_ahead


func _bash(hitbox: PartHitbox, animation: SkeletalDodgeAnimation) -> void:
	_active = false
	var target := hitbox.health.mech
	var forward := _forward()
	var point := _contact_point(forward)
	var spark := IMPACT.instantiate() as Node3D
	mech.get_parent().add_child(spark)
	spark.global_position = point
	spark.look_at(point - forward, Vector3.UP)
	spark.scale = Vector3.ONE * 3.0
	hitbox.on_hit(damage, mech.global_position, hit_kind)
	animation.halt()
	bashed.emit(target, hitbox.part_key)
	_push(target, forward)


## The target slides away along the dash, slowing down evenly to a stop in push_time.
func _push(target: Mech, direction: Vector3) -> void:
	var start_speed := 2.0 * push_distance / maxf(push_time, 0.05)
	_pushes.append({"target": target, "direction": direction, "speed": start_speed})


func _update_pushes(delta: float) -> void:
	var slowdown := 2.0 * push_distance / maxf(push_time * push_time, 0.0025)
	for push in _pushes.duplicate():
		var target := push["target"] as Mech
		if not is_instance_valid(target) or target.is_wrecked or push["speed"] <= 0.0:
			_pushes.erase(push)
			continue
		# Mean speed of the frame, so the slide length comes out right.
		var next := maxf(push["speed"] - slowdown * delta, 0.0)
		var motion: Vector3 = push["direction"] * (push["speed"] + next) * 0.5 * delta
		push["speed"] = next
		target.move_and_collide(motion)
