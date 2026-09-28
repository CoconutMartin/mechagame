class_name Debris
extends RigidBody3D
## A broken part that falls off: the part's nodes move into a rigid body that tumbles to the
## ground with smoke, then disappears after a while.

## Seconds before the debris disappears.
@export var life: float = 20.0

var _age: float = 0.0


## Moves nodes into a new debris body in world. The nodes keep their place on screen.
## push: start velocity (the mech velocity plus a kick away from the mech).
static func drop(nodes: Array[Node3D], world: Node, push: Vector3) -> Debris:
	var alive: Array[Node3D] = []
	for node in nodes:
		if is_instance_valid(node) and node.is_inside_tree():
			alive.append(node)
	if alive.is_empty():
		return null
	var center := Vector3.ZERO
	for node in alive:
		center += node.global_position
	center /= alive.size()
	var debris := Debris.new()
	debris.name = "Debris"
	debris.collision_layer = 0
	debris.collision_mask = 1
	debris.mass = 5.0
	world.add_child(debris)
	debris.global_position = center
	var bounds := AABB()
	var first := true
	for node in alive:
		_stop_scripts(node)
		node.reparent(debris, true)
		for mesh in MechHealth._meshes(node):
			var box := (debris.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = (bounds.size if not first else Vector3.ONE).max(Vector3.ONE * 0.4)
	shape.shape = box_shape
	shape.position = bounds.get_center() if not first else Vector3.ZERO
	debris.add_child(shape)
	debris.linear_velocity = push
	debris.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	DamageSmoke.create(debris, shape.position, true)
	return debris


## Weapons and effects in the debris stop working.
static func _stop_scripts(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for group in [&"pauldron_l", &"pauldron_r", &"booster_flame", &"brake_flame", &"foot"]:
		if node.is_in_group(group):
			node.remove_from_group(group)
	for child in node.get_children():
		_stop_scripts(child)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > life:
		queue_free()
