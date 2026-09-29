class_name Rubble
extends RigidBody3D
## A piece of broken building. It tumbles to the ground, lies there, then sinks into the ground
## and is removed. Mechs walk through it (no collision layer). Only max_count pieces exist at a
## time: the oldest piece goes first.

## Largest number of rubble pieces in the level.
static var max_count: int = 220
# Untyped: a typed read of a freed piece is an error.
static var _all: Array = []

## Seconds the piece lies on the ground before it sinks.
@export var life: float = 14.0
## Seconds to sink into the ground.
@export var sink_time: float = 1.5

var _age: float = 0.0
var _size: Vector3 = Vector3.ONE


static func spawn(world: Node, point: Vector3, size: Vector3, tint: Color, velocity: Vector3) -> Rubble:
	while _all.size() >= max_count:
		var oldest: Variant = _all.pop_front()
		if is_instance_valid(oldest):
			(oldest as Rubble).queue_free()
	var piece := Rubble.new()
	piece._size = size
	piece.collision_layer = 0
	piece.collision_mask = 1
	piece.mass = maxf(size.x * size.y * size.z * 2.0, 0.5)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = GridMaterials.get_material(tint)
	piece.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	piece.add_child(shape)
	world.add_child(piece)
	piece.global_position = point
	piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	piece.linear_velocity = velocity
	piece.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	_all.append(piece)
	return piece


func _exit_tree() -> void:
	_all.erase(self)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age < life:
		return
	# Sink: no more physics, move down by the piece size, then go.
	if not freeze:
		freeze = true
		collision_mask = 0
	global_position.y -= _size.length() / sink_time * delta
	if _age > life + sink_time:
		queue_free()
