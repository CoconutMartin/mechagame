@tool
class_name DestructibleBuilding
extends Node3D
## A greybox building made of blocks (BuildingChunk) that weapons can break (Phase 4c).
## The origin is at the bottom center, like GreyboxBlock. In the editor it shows one box.
##   A block at 0 HP breaks into rubble with a dust cloud.
##   Support: a block stands while it connects to a ground block through face neighbors. Blocks
##   with no support fall, and break when they hit the ground or the building. Their impact hurts
##   mechs near it (hitboxes only, so it does not break more blocks).

const GRID_MATERIAL := preload("res://materials/greybox_grid.tres")
const DOOR_MATERIAL := preload("res://materials/door.tres")
const DOOR_SIZE := Vector3(1.2, 2.0, 0.2)
## Layer 4 (hitboxes, value 8): falling blocks hurt mechs only.
const HITBOX_MASK := 8

@export var size: Vector3 = Vector3(18.0, 40.0, 18.0):
	set(value):
		size = value
		_update_preview()
@export var tint: Color = Color(0.55, 0.55, 0.56):
	set(value):
		tint = value
		_update_preview()
## Adds a 2 m door on the +Z face, to show human scale.
@export var add_door: bool = false

@export_group("Blocks")
## Wanted block size, in meters. The real size divides the building evenly.
@export var chunk_size: Vector3 = Vector3(6.0, 5.0, 6.0)
## HP of one block.
@export var chunk_hp: float = 1000.0
## Tint of a block at 0 HP = tint x this value.
@export_range(0.0, 1.0) var dark_scale: float = 0.55
## Rubble pieces from one broken block.
@export var rubble_per_chunk: int = 5
## Rubble piece size, as a part of the block size (random between these).
@export var rubble_min_scale: float = 0.22
@export var rubble_max_scale: float = 0.42
## Rubble start speed away from the block center, in m/s.
@export var rubble_speed: float = 5.0

@export_group("Falling blocks")
## Damage of a falling block to mechs near its impact (full at the center, 30% at the edge).
@export var fall_damage: float = 250.0
## Radius of that damage, in meters.
@export var fall_radius: float = 6.0

var _cells := {}
var _cell_size := Vector3.ONE
var _counts := Vector3i.ONE
var _box: BoxMesh
var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	_build()


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	var box := BoxMesh.new()
	box.size = size
	_preview.mesh = box
	_preview.material_override = GRID_MATERIAL
	_preview.set_instance_shader_parameter("tint", tint)
	_preview.position = Vector3(0.0, size.y * 0.5, 0.0)


## Builds the grid of blocks.
func _build() -> void:
	_counts = Vector3i(maxi(roundi(size.x / chunk_size.x), 1), maxi(roundi(size.y / chunk_size.y), 1),
			maxi(roundi(size.z / chunk_size.z), 1))
	_cell_size = Vector3(size.x / _counts.x, size.y / _counts.y, size.z / _counts.z)
	_box = BoxMesh.new()
	_box.size = _cell_size
	var shape := BoxShape3D.new()
	shape.size = _cell_size
	for x in _counts.x:
		for y in _counts.y:
			for z in _counts.z:
				_add_chunk(Vector3i(x, y, z), shape)
	if add_door:
		var door := MeshInstance3D.new()
		var door_box := BoxMesh.new()
		door_box.size = DOOR_SIZE
		door.mesh = door_box
		door.material_override = DOOR_MATERIAL
		var chunk: BuildingChunk = _cells[Vector3i(floori(_counts.x * 0.5), 0, _counts.z - 1)]
		chunk.add_child(door)
		door.position = Vector3(0.0, DOOR_SIZE.y * 0.5 - _cell_size.y * 0.5, _cell_size.z * 0.5)


func _add_chunk(cell: Vector3i, shape: BoxShape3D) -> void:
	var chunk := BuildingChunk.new()
	chunk.name = "Chunk_%d_%d_%d" % [cell.x, cell.y, cell.z]
	chunk.building = self
	chunk.cell = cell
	chunk.max_hp = chunk_hp
	chunk.hp = chunk_hp
	chunk.collision_layer = 1
	chunk.collision_mask = 0
	chunk.position = _cell_center(cell)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box
	chunk.add_child(mesh)
	chunk.mesh = mesh
	var collision := CollisionShape3D.new()
	collision.shape = shape
	chunk.add_child(collision)
	add_child(chunk)
	chunk.show_damage(tint, dark_scale)
	_cells[cell] = chunk


## Block center in the building's space.
func _cell_center(cell: Vector3i) -> Vector3:
	return Vector3((cell.x + 0.5) * _cell_size.x - size.x * 0.5, (cell.y + 0.5) * _cell_size.y,
			(cell.z + 0.5) * _cell_size.z - size.z * 0.5)


## Weapons hit a block (BuildingChunk.on_hit).
func damage_chunk(chunk: BuildingChunk, amount: float) -> void:
	if not _cells.has(chunk.cell) or amount <= 0.0:
		return
	chunk.hp -= amount
	if chunk.hp > 0.0:
		chunk.show_damage(tint, dark_scale)
		return
	_cells.erase(chunk.cell)
	shatter(chunk.global_transform, _cell_size, tint * dark_scale, Vector3.ZERO, false)
	chunk.queue_free()
	_drop_unsupported()


## Breaks a block into rubble with dust. hurts: the impact hurts mechs near it.
func shatter(place: Transform3D, block: Vector3, color: Color, velocity: Vector3, hurts: bool) -> void:
	var world := _world()
	color.a = 1.0
	DustBurst.create(world, place.origin, block)
	for i in rubble_per_chunk:
		var piece := block * randf_range(rubble_min_scale, rubble_max_scale)
		var offset := Vector3(randf_range(-0.3, 0.3) * block.x, randf_range(-0.3, 0.3) * block.y,
				randf_range(-0.3, 0.3) * block.z)
		var away := (offset.normalized() + Vector3.UP * 0.5) * rubble_speed * randf_range(0.5, 1.0)
		Rubble.spawn(world, place * offset, piece, color * randf_range(0.85, 1.05), velocity * 0.3 + away)
	if hurts:
		Blast.apply(get_world_3d(), place.origin, fall_radius, fall_damage, [], HITBOX_MASK)


## Blocks that no longer connect to the ground fall.
func _drop_unsupported() -> void:
	var supported := {}
	var open: Array[Vector3i] = []
	for cell: Vector3i in _cells:
		if cell.y == 0:
			supported[cell] = true
			open.append(cell)
	var steps: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN,
			Vector3i.FORWARD, Vector3i.BACK]
	while not open.is_empty():
		var cell: Vector3i = open.pop_back()
		for step in steps:
			var next := cell + step
			if _cells.has(next) and not supported.has(next):
				supported[next] = true
				open.append(next)
	for cell: Vector3i in _cells.keys():
		if not supported.has(cell):
			_fall(_cells[cell])
			_cells.erase(cell)


## A block becomes a falling body (a little smaller, so it does not touch its old neighbors).
func _fall(chunk: BuildingChunk) -> void:
	var body := FallingChunk.new()
	body.building = self
	body.size = _cell_size
	body.tint = tint * lerpf(dark_scale, 1.0, clampf(chunk.hp / chunk.max_hp, 0.0, 1.0))
	body.tint.a = 1.0
	body.mass = 50.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box
	mesh.material_override = GridMaterials.get_material(body.tint)
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _cell_size * 0.9
	collision.shape = shape
	body.add_child(collision)
	var place := chunk.global_transform
	_world().add_child(body)
	body.global_transform = place
	body.angular_velocity = Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4))
	chunk.queue_free()


## Blocks left standing (for tests and the HUD).
func get_chunk_count() -> int:
	return _cells.size()


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else get_parent()
