class_name BodyGroundClamp
extends Node
## Keeps a fallen or destroyed mech out of the ground (Phase 8b fix). While MechFall moves the body
## (topple, lie, roll, get up), the lowest point of every visible body mesh is found; if it is under
## the ground, the body rises (MechFall.ground_lift) so it rests on that point. When the pose no
## longer needs the lift, it sinks back at settle_speed.
## The held weapon is not counted: it hangs from the hand, so it turns up around its grip until it
## is out of the ground.
## Runs after every pose script and FootLeveler.

@export var mech: Mech
@export var fall: MechFall
## The body node (Visual).
@export var body: Node3D
@export var weapons: WeaponController
## Lift removed per second when the body floats above the ground, in meters.
@export var settle_speed: float = 1.5
## Ground layers for the ray (1 = world).
@export_flags_3d_physics var ground_mask: int = 1

## Box of each mesh in its own space (cached).
var _boxes := {}


func _ready() -> void:
	process_physics_priority = 15


func _physics_process(delta: float) -> void:
	if fall == null or fall.state == MechFall.State.IDLE:
		return
	var ground := _ground_height()
	var weapon := weapons.right_weapon if weapons != null else null
	var low := _lowest(body, weapon)
	var depth := ground - low
	if depth > 0.0:
		fall.ground_lift += depth
		body.global_position.y += depth
	elif fall.ground_lift > 0.0:
		var sink := minf(minf(-depth, settle_speed * delta), fall.ground_lift)
		fall.ground_lift -= sink
		body.global_position.y -= sink
	if weapon != null and is_instance_valid(weapon) and body.is_ancestor_of(weapon):
		_lift_weapon(weapon, ground)


func _ground_height() -> float:
	var from := mech.global_position + Vector3.UP * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, ground_mask)
	query.exclude = mech.get_hit_exclude()
	var hit := mech.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else mech.global_position.y


## Lowest world height of the visible meshes under root (skipping the skip node and flames).
func _lowest(root: Node, skip: Node) -> float:
	var low := INF
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or (skip != null and skip.is_ancestor_of(mesh)) or mesh.cast_shadow == 0:
			continue
		if not _boxes.has(mesh):
			_boxes[mesh] = mesh.get_aabb()
		var box: AABB = _boxes[mesh]
		var to_world := mesh.global_transform
		for i in 8:
			low = minf(low, (to_world * box.get_endpoint(i)).y)
	return low


## Turns the weapon around its grip (up or down, whichever works) until it is out of the ground.
func _lift_weapon(weapon: Node3D, ground: float) -> void:
	var depth := ground - _lowest(weapon, null)
	if depth <= 0.0:
		return
	var grip := weapon.get_node_or_null(^"GripRight") as Node3D
	var pivot := grip.global_position if grip != null else weapon.global_position
	var axis := weapon.global_basis.x.normalized()
	var start := weapon.global_transform
	var best := start
	var best_depth := depth
	for sign in [1.0, -1.0]:
		for step in range(1, 11):
			var turn := Transform3D(Basis(axis, sign * deg_to_rad(9.0 * step)), Vector3.ZERO)
			var moved := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot) * start
			weapon.global_transform = moved
			var d := ground - _lowest(weapon, null)
			if d < best_depth:
				best_depth = d
				best = moved
			if d <= 0.0:
				break
	weapon.global_transform = best
