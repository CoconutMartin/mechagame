class_name BuildingDamage
extends Node
## Damage for one urban building (made by BuildingGenerator in the game, not for edge blocks).
## A chunk takes damage from hits at or above its material's damage_threshold. At 0 HP it breaks:
## its boxes leave the building's MultiMeshes, rubble and dust in the material's debris color fly out
## (glass: small shards, no dust), and its collision goes away. The building's occluder turns off at
## the first break (holes would hide what is behind them).
## Support (low-rise buildings): chunks connect where their boxes touch; chunks that touch the ground
## carry the rest. Glass and doors carry nothing. A chunk with no path to the ground falls as a body
## and breaks when it lands (the impact hurts mechs near it). Towers (facade_only) never collapse.

## Hitbox layer (4): falling chunks hurt mechs, not other chunks.
const HITBOX_MASK := 8
## Kinds that do not carry other chunks.
const NOT_CARRYING := [UrbanChunk.Kind.GLASS, UrbanChunk.Kind.DOOR]

## Chunks whose lowest point is this close to the building base stand on the ground (meters).
@export var ground_tolerance: float = 0.2
## Boxes closer than this touch (meters).
@export var touch_gap: float = 0.08
## Rubble pieces per cubic meter of a broken chunk, and the limits per chunk.
@export var rubble_per_m3: float = 1.2
@export var min_rubble: int = 2
@export var max_rubble: int = 6
## Rubble piece size as a part of the chunk's smallest side... largest side.
@export var rubble_min_scale: float = 0.18
@export var rubble_max_scale: float = 0.35
## Rubble launch speed, m/s.
@export var rubble_speed: float = 5.0
## Most falling chunk bodies at once in the level; more unsupported chunks break where they are.
@export var max_falling: int = 60
## Damage to mech hitboxes where a falling chunk lands (full at the center), and the radius.
@export var fall_damage: float = 250.0
@export var fall_radius: float = 6.0

static var _falling_now: int = 0

var generator: BuildingGenerator
## Neighbors of each chunk (chunk -> Array of chunks).
var _links := {}
var _grounded := {}
var _broken_any := false


## Called by BuildingGenerator after it made the chunks.
func setup(building: BuildingGenerator) -> void:
	generator = building
	var boxes := {}
	for chunk in building.chunks:
		boxes[chunk] = _boxes_of(chunk)
		_links[chunk] = []
		chunk.damage_owner = self
		for box: AABB in boxes[chunk]:
			if box.position.y <= ground_tolerance:
				_grounded[chunk] = true
	# Towers never collapse: no support links (they are also the biggest buildings).
	if building.def.facade_only:
		return
	var list := building.chunks
	var bounds := {}
	for chunk in list:
		var all: Array = boxes[chunk]
		var merged: AABB = all[0] if not all.is_empty() else AABB()
		for box: AABB in all:
			merged = merged.merge(box)
		bounds[chunk] = merged.grow(touch_gap)
	for i in list.size():
		var near: AABB = bounds[list[i]]
		for j in range(i + 1, list.size()):
			# Whole-chunk bounds first (cheap), then the boxes.
			if near.intersects(bounds[list[j]]) and _touch(boxes[list[i]], boxes[list[j]]):
				_links[list[i]].append(list[j])
				_links[list[j]].append(list[i])


## A hit on a chunk (UrbanChunk.on_hit).
func damage(chunk: UrbanChunk, amount: float) -> void:
	if not _links.has(chunk) or amount <= 0.0:
		return
	var threshold := chunk.material_def.damage_threshold if chunk.material_def != null else 0.0
	if amount < threshold:
		return
	chunk.hp -= amount
	if chunk.hp <= 0.0:
		break_chunk(chunk)


## Breaks a chunk into rubble where it stands, then drops what lost its support.
func break_chunk(chunk: UrbanChunk) -> void:
	if not _links.has(chunk):
		return
	_remove(chunk)
	for box: AABB in _boxes_of(chunk):
		shatter(Transform3D(generator.global_basis, generator.global_transform * box.get_center()), box.size,
				_debris_color(chunk), Vector3.ZERO, false, chunk.kind == UrbanChunk.Kind.GLASS)
	chunk.queue_free()
	if not generator.def.facade_only:
		_drop_unsupported()


## Breaks a box into rubble (and dust unless it is glass). hurts: the impact hurts mechs near it.
## FallingChunk calls it when a falling chunk lands.
func shatter(place: Transform3D, size: Vector3, color: Color, velocity: Vector3, hurts: bool, glass: bool = false) -> void:
	var world := _world()
	color.a = 1.0
	if not glass:
		DustBurst.create(world, place.origin, size)
	var volume := size.x * size.y * size.z
	var count := clampi(roundi(volume * rubble_per_m3), min_rubble, max_rubble)
	var smallest := minf(size.x, minf(size.y, size.z))
	var largest := maxf(size.x, maxf(size.y, size.z))
	for i in count:
		var side := lerpf(smallest, largest, 0.5) * randf_range(rubble_min_scale, rubble_max_scale)
		var piece := Vector3(side, side * randf_range(0.4, 1.0), side * randf_range(0.6, 1.2))
		if glass:
			piece = Vector3(side * 0.5, side * 0.5, 0.05)
		var offset := Vector3(randf_range(-0.4, 0.4) * size.x, randf_range(-0.4, 0.4) * size.y, randf_range(-0.4, 0.4) * size.z)
		var away := (offset.normalized() + Vector3.UP * 0.5) * rubble_speed * randf_range(0.5, 1.0)
		Rubble.spawn(world, place * offset, piece, color * randf_range(0.85, 1.05), velocity * 0.3 + away)
	if hurts:
		Blast.apply(generator.get_world_3d(), place.origin, fall_radius, fall_damage, [], HITBOX_MASK)


## Chunks left standing (for tests).
func get_chunk_count() -> int:
	return _links.size()


func _remove(chunk: UrbanChunk) -> void:
	for other: UrbanChunk in _links[chunk]:
		if _links.has(other):
			_links[other].erase(chunk)
	_links.erase(chunk)
	_grounded.erase(chunk)
	# Hide its boxes in the building look.
	for piece: Vector2i in chunk.pieces:
		var mm: MultiMesh = generator.multimeshes[piece.x]
		mm.set_instance_transform(piece.y, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	if not _broken_any:
		_broken_any = true
		if generator.occluder != null:
			generator.occluder.visible = false


## Chunks with no path to the ground fall. Glass and doors pass no support on.
func _drop_unsupported() -> void:
	var supported := {}
	var open: Array = []
	for chunk: UrbanChunk in _grounded:
		supported[chunk] = true
		open.append(chunk)
	while not open.is_empty():
		var chunk: UrbanChunk = open.pop_back()
		if chunk.kind in NOT_CARRYING:
			continue
		for other: UrbanChunk in _links[chunk]:
			if not supported.has(other):
				supported[other] = true
				open.append(other)
	for chunk: UrbanChunk in _links.keys():
		if not supported.has(chunk):
			_fall(chunk)


## A chunk becomes a falling body made of its boxes (a little smaller, so it does not catch on its
## old neighbors). Past max_falling it breaks where it is.
func _fall(chunk: UrbanChunk) -> void:
	var boxes := _boxes_of(chunk)
	_remove(chunk)
	var color := _debris_color(chunk)
	if _falling_now >= max_falling or boxes.is_empty():
		for box: AABB in boxes:
			shatter(Transform3D(generator.global_basis, generator.global_transform * box.get_center()), box.size,
					color, Vector3.ZERO, false, chunk.kind == UrbanChunk.Kind.GLASS)
		chunk.queue_free()
		return
	var bounds := boxes[0]
	for box: AABB in boxes:
		bounds = bounds.merge(box)
	var body := FallingChunk.new()
	body.building = self
	body.size = bounds.size
	body.tint = color
	body.mass = maxf(chunk.volume * (chunk.material_def.density if chunk.material_def != null else 2.0) * 0.2, 5.0)
	var material: Material = chunk.material_def.get_material() if chunk.material_def != null else null
	for box: AABB in boxes:
		var mesh := MeshInstance3D.new()
		var shape_mesh := BoxMesh.new()
		shape_mesh.size = box.size
		mesh.mesh = shape_mesh
		mesh.material_override = material
		mesh.position = box.get_center() - bounds.get_center()
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size * 0.9
		collision.shape = shape
		collision.position = mesh.position
		body.add_child(collision)
	_world().add_child(body)
	body.global_transform = Transform3D(generator.global_basis, generator.global_transform * bounds.get_center())
	body.angular_velocity = Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4))
	_falling_now += 1
	body.tree_exited.connect(func() -> void: _falling_now -= 1)
	chunk.queue_free()


## The chunk's boxes in building space (from its collision shapes).
func _boxes_of(chunk: UrbanChunk) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for child in chunk.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			var size := (shape.shape as BoxShape3D).size
			boxes.append(AABB(chunk.position + shape.position - size * 0.5, size))
	return boxes


func _touch(a: Array, b: Array) -> bool:
	for box_a: AABB in a:
		var grown := box_a.grow(touch_gap)
		for box_b: AABB in b:
			if grown.intersects(box_b):
				return true
	return false


func _debris_color(chunk: UrbanChunk) -> Color:
	return chunk.material_def.debris_color if chunk.material_def != null else Color(0.5, 0.5, 0.5)


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else generator.get_parent()
