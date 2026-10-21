class_name Rubble
extends RigidBody3D
## A piece of broken building. It tumbles down and is removed the moment it lands on the ground
## (user note 2026-10-21, for performance), sometimes with a small dust puff. A piece that comes to rest
## on a building lies there, then sinks and is removed. Mechs walk through it (no collision layer); a fast piece that hits a mech part hurts
## it a little (DebrisHurt). Only max_count pieces exist at a
## time: the oldest piece goes first.

## Largest number of rubble pieces in the level.
static var max_count: int = 220
# Untyped: a typed read of a freed piece is an error.
static var _all: Array = []

## Seconds the piece lies on the ground before it sinks.
@export var life: float = 14.0
## Seconds to sink into the ground.
@export var sink_time: float = 1.5
## Seconds in the air before a ground contact removes the piece (so a piece from a ground floor chunk
## is seen flying out).
@export var min_air_time: float = 0.15
## A contact counts as the ground when its normal points up at least this much (1 = straight up).
@export var ground_normal_y: float = 0.6
## Chance of a small dust puff where a piece lands (0 = never). Puffs share DustBurst's per frame cap.
@export_range(0.0, 1.0) var puff_chance: float = 0.2
## Opacity of the landing puff.
@export_range(0.0, 1.0) var puff_opacity: float = 0.35

const GROUND_LAYER := 1

var _age: float = 0.0
var _size: Vector3 = Vector3.ONE


## look: the material of what broke (phase 5b, user request 2026-10-21: rubble in the wall's own color and
## texture); null = the plain grid material in tint.
static func spawn(world: Node, point: Vector3, size: Vector3, tint: Color, velocity: Vector3, look: Material = null) -> Rubble:
	while _all.size() >= max_count:
		var oldest: Variant = _all.pop_front()
		if is_instance_valid(oldest):
			(oldest as Rubble).queue_free()
	var piece := Rubble.new()
	piece._size = size
	piece.collision_layer = 0
	piece.collision_mask = 1 | 16  # world and buildings
	piece.mass = maxf(size.x * size.y * size.z * 2.0, 0.5)
	var mesh := MeshInstance3D.new()
	# A shared rough unit piece, scaled (phase 5a: a new mesh per piece was slow; 5b: jagged pieces).
	mesh.mesh = RubbleShapes.pick()
	mesh.scale = size
	mesh.material_override = look if look != null else GridMaterials.get_material(tint, false)
	piece.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	piece.add_child(shape)
	# Flying rubble hurts mechs a little (minor damage).
	DebrisHurt.attach(piece)
	world.add_child(piece)
	piece.global_position = point
	piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	piece.linear_velocity = velocity
	piece.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	_all.append(piece)
	return piece


func _exit_tree() -> void:
	_all.erase(self)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# DebrisHurt turns on the contact reports.
	if _age < min_air_time or freeze or is_queued_for_deletion():
		return
	for i in state.get_contact_count():
		if state.get_contact_local_normal(i).y < ground_normal_y:
			continue
		var other := state.get_contact_collider_object(i) as CollisionObject3D
		if other == null or other.collision_layer & GROUND_LAYER == 0:
			continue
		if randf() < puff_chance:
			DustBurst.create(get_parent(), global_position, _size * 2.0, puff_opacity)
		queue_free()
		return


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
