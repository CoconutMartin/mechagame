class_name FootLeveler
extends Node
## Keeps the feet flat on the ground (Phase 8b fix for feet going into the ground). Each foot turns
## at its ankle pivot (groups foot_pivot_l and foot_pivot_r, from the leg part model):
##   Near the ground: the sole lies flat on the ground under it (a ray finds the ground and its
##   slope), up to max_angle_deg away from the shin.
##   High above the ground (in the air): the foot hangs in line with the shin, toes a little down.
## Body lift: when a pose puts a knee or thigh under the ground (deep slide crouch, kneel), the body
## rises by that much (standing mechs only; BodyGroundClamp handles falls).
## Ground clamp: when a pose puts the sole under the ground (skid, kneel, dodge, falls), the leg
## bends (two-bone IK from the hip, knee kept in its bend plane) so the ankle comes up to the ground.
## Runs last, after every leg pose (walk, IK, falls, power down). It sits outside the Animation node,
## so it keeps working when a destroyed mech stops its animation.

@export var mech: Mech
## The body node that holds the hips (raised when a knee or thigh would go into the ground).
@export var upper_body: Node3D
## Largest foot turn away from the shin, in degrees (ankle limit).
@export var max_angle_deg: float = 110.0
## Ankle to sole, in meters.
@export var sole_depth: float = 0.55
## The foot lies flat when its sole is this close to the ground, and hangs free this high up (meters).
@export var flat_height: float = 0.4
@export var free_height: float = 2.0
## The ground ray starts this far above the ankle, in meters.
@export var ray_start_height: float = 5.0
## Toe drop of a hanging foot, in degrees.
@export var hang_toe_down_deg: float = 12.0
## Ground layers for the ray (1 = world).
@export_flags_3d_physics var ground_mask: int = 1
## When the ground clamp bends a leg whose knee is closer than this to the hip-ankle line (meters),
## the knee bends toward the body front (a straight leg has no bend side of its own).
@export var straight_leg_pole_m: float = 0.05

var _pivots: Array[Node3D] = []
## Box around each foot's meshes, in its pivot space (by pivot).
var _bounds := {}


func _ready() -> void:
	# After the fall and power down poses (12, 13).
	process_physics_priority = 14


func _physics_process(_delta: float) -> void:
	if _pivots.is_empty():
		for group in [&"foot_pivot_l", &"foot_pivot_r"]:
			var found := GroupNodes.find(mech, group)
			if not found.is_empty():
				_pivots.append(found[0])
	var space := mech.get_world_3d().direct_space_state
	# Standing mechs (also a destroyed one that powers down standing). Falls: BodyGroundClamp.
	if upper_body != null and mech.is_on_floor() and not mech.is_fallen:
		_lift_body()
	for pivot in _pivots:
		# A foot that fell off with its leg is no longer on this mech.
		if not is_instance_valid(pivot) or not mech.is_ancestor_of(pivot):
			continue
		_level(pivot, space)


func _level(pivot: Node3D, space: PhysicsDirectSpaceState3D) -> void:
	var hang := Basis(Vector3.RIGHT, -deg_to_rad(hang_toe_down_deg))
	var ankle := pivot.global_position
	# From well above the ankle, so an ankle deep in the ground still finds the ground top.
	var query := PhysicsRayQueryParameters3D.create(ankle + Vector3.UP * ray_start_height, ankle + Vector3.DOWN * (free_height + 1.0), ground_mask)
	query.exclude = mech.get_hit_exclude()
	query.hit_from_inside = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		pivot.basis = hang
		return
	var normal: Vector3 = hit.normal
	var height := (ankle - (hit.position as Vector3)).dot(normal) - sole_depth
	if height < 0.0:
		_lift_leg(pivot, ankle - normal * height)
		height = 0.0
	var shin := pivot.get_parent_node_3d().global_basis.orthonormalized()
	var weight := 1.0 - smoothstep(flat_height, free_height, height)
	# Flat foot: up = the ground normal, toes = the shin forward laid on the ground.
	var forward := -shin.z
	forward = (forward - normal * forward.dot(normal))
	if forward.length_squared() < 0.0001:
		forward = shin.y.cross(normal)
	var flat := Basis.looking_at(forward.normalized(), normal)
	var local := (shin.inverse() * flat).get_rotation_quaternion()
	# Ankle limit.
	var limit := deg_to_rad(max_angle_deg)
	var angle := local.get_angle()
	if angle > limit:
		local = Quaternion.IDENTITY.slerp(local, limit / angle)
	var blended := Basis(hang.get_rotation_quaternion().slerp(local, weight))
	# No part of the foot may go into the ground: first the foot lies flat, then the leg lifts.
	var ground_y: float = (hit.position as Vector3).y
	if _lowest(pivot, blended) < ground_y:
		blended = Basis(local)
		var depth := ground_y - _lowest(pivot, blended)
		if depth > 0.0:
			_lift_leg(pivot, pivot.global_position + Vector3.UP * depth)
			# The shin moved: lay the foot flat again in the new shin space.
			var new_shin := pivot.get_parent_node_3d().global_basis.orthonormalized()
			var again := (new_shin.inverse() * flat).get_rotation_quaternion()
			if again.get_angle() > limit:
				again = Quaternion.IDENTITY.slerp(again, limit / again.get_angle())
			blended = Basis(again)
	pivot.basis = blended


## Lowest world height of the foot box with this pivot basis.
func _lowest(pivot: Node3D, local_basis: Basis) -> float:
	if not _bounds.has(pivot):
		_bounds[pivot] = _foot_box(pivot)
	var box: AABB = _bounds[pivot]
	var to_world := Transform3D(pivot.get_parent_node_3d().global_basis.orthonormalized() * local_basis, pivot.global_position)
	var low := INF
	for i in 8:
		low = minf(low, (to_world * box.get_endpoint(i)).y)
	return low


static func _foot_box(pivot: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_pivot := pivot.global_transform.affine_inverse()
	for node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var part := (to_pivot * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box if not first else AABB(Vector3(-0.7, -0.6, -2.2), Vector3(1.4, 0.6, 3.5))


## Bends the leg (hip and knee) so the ankle reaches target. The knee keeps its bend side.
func _lift_leg(pivot: Node3D, target: Vector3) -> void:
	var knee := pivot.get_parent_node_3d()
	var hip := knee.get_parent_node_3d()
	if hip == null or knee == null:
		return
	# Bend side = how far the knee sits off the hip-ankle line. Only the part across the line counts:
	# with a thigh and shin of different lengths a straight knee is off the middle along the line,
	# and that would point the bend along the leg (the IK then bends it sideways).
	var line := (pivot.global_position - hip.global_position).normalized()
	var pole := knee.global_position - hip.global_position
	pole -= line * pole.dot(line)
	# A (nearly) straight leg has no bend side: bend toward the body front.
	if pole.length() < straight_leg_pole_m:
		pole = -hip.get_parent_node_3d().global_basis.z
	TwoBoneIK.solve_to(hip, knee, target, pole, knee.position.length(), pivot.position.length())


## Raises the body when a knee or thigh is under the ground (mech origin = ground height).
func _lift_body() -> void:
	var ground := mech.global_position.y
	var low := INF
	for pivot in _pivots:
		if not is_instance_valid(pivot) or not mech.is_ancestor_of(pivot):
			continue
		var knee := pivot.get_parent_node_3d()
		for joint: Node3D in [knee, knee.get_parent_node_3d()]:
			if not _bounds.has(joint):
				_bounds[joint] = _box_without(joint, pivot)
			var box: AABB = _bounds[joint]
			for i in 8:
				low = minf(low, (joint.global_transform * box.get_endpoint(i)).y)
	if low < ground:
		upper_body.position.y += ground - low


## Box around the meshes that belong to a leg joint (not its child joints or the foot), in its space.
static func _box_without(joint: Node3D, pivot: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_joint := joint.global_transform.affine_inverse()
	for child in joint.get_children():
		if child == pivot or child is PartHitbox or not child is MeshInstance3D:
			continue
		var mesh := child as MeshInstance3D
		var part := (to_joint * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box if not first else AABB(Vector3(-0.5, -1.0, -0.5), Vector3(1.0, 1.0, 1.0))
