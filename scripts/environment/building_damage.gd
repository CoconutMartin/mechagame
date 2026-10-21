class_name BuildingDamage
extends Node
## Damage for one urban building (made by BuildingGenerator in the game, not for edge blocks).
## A chunk takes full damage from hits at or above its material's damage_threshold, and less from weaker
## hits (x hit / threshold, so they add up). At 0 HP it breaks:
## its boxes leave the building's MultiMeshes, rubble and dust in the material's debris color fly out
## (glass: small shards, no dust), and its collision goes away. The building's occluder turns off at
## the first break (holes would hide what is behind them).
## Support: chunks connect where their boxes touch; chunks that touch the ground carry the rest. Glass
## and doors carry nothing. A chunk with no path to the ground falls as a body and breaks when it lands
## (the impact hurts mechs near it). Falling chunks are let go a few per frame, lowest first.
## Towers (facade_only, user answer 2026-10-12: towers collapse): when a floor loses collapse_fraction of
## its walls and columns, everything above it falls.

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
@export var min_rubble: int = 3
@export var max_rubble: int = 6
## Opacity of the dust when a chunk breaks (0 = clear, 1 = solid; user request 2026-10-15: 50%).
@export_range(0.0, 1.0) var dust_opacity: float = 0.5
## Rubble piece size as a part of the chunk's smallest side... largest side.
@export var rubble_min_scale: float = 0.18
@export var rubble_max_scale: float = 0.35
## Rubble launch speed, m/s.
@export var rubble_speed: float = 5.0
## Most falling chunk bodies at once in the level; more unsupported chunks break where they are.
@export var max_falling: int = 60

@export_group("Collapse (phase 5c)")
## A group of at least this many chunks that loses its support at once sags and leans as one mass and
## stays (CollapseMass); smaller groups fall chunk by chunk.
@export var mass_min_chunks: int = 10

@export_group("Wear (phase 5b)")
## A chunk below this part of its HP shows cracks and turns darker (ChunkCracks).
@export_range(0.0, 1.0) var crack_below: float = 0.5
## Blasts (missiles) and hits of at least this damage (cannon shells) leave a scorch mark (ScorchMark).
@export var scorch_min_damage: float = 150.0
## Scorch mark size (m across) for a blast and for a heavy shell.
@export var scorch_blast_size: float = 3.5
@export var scorch_shell_size: float = 1.6
## Bent bars on each face a broken concrete chunk shared with a standing neighbor (Rebar), a range.
@export var rebar_per_face: Vector2i = Vector2i(1, 2)
## Most bars for one broken chunk.
@export var rebar_per_break: int = 6
## Materials whose breaks show rebar (MaterialDef.display_name).
@export var rebar_materials: PackedStringArray = ["Concrete"]
@export_group("")
## Damage to mech hitboxes where a falling chunk lands (full at the center), and the radius. 0 = off.
@export var fall_damage: float = 0.0  # off since 2026-10-16 (user); 125 on 2026-10-15, 250 before
@export var fall_radius: float = 6.0
## Towers: part of a floor's wall and column volume that, broken, brings everything above it down.
@export_range(0.1, 1.0) var collapse_fraction: float = 0.6
## Unsupported chunks let go per physics frame (lowest first), so a collapse does not stall a frame.
@export var fall_per_frame: int = 15
## Support grid cell size (meters): only chunks in the same cells are tested for touching.
@export var grid_cell: float = 4.0

static var _falling_now: int = 0

var generator: BuildingGenerator
## Neighbors of each chunk (chunk -> Array of chunks).
var _links := {}
var _grounded := {}
var _broken_any := false
## Towers: wall and column volume per floor, and the part broken.
var _floor_total := {}
var _floor_lost := {}
var _collapsed_from: int = -1
## Chunks waiting to fall (lowest first).
var _fall_queue: Array = []
## True after a break: the support check runs once in the next physics frame (phase 5a, 2026-10-19: one
## check per broken chunk cost 14 ms when 45 chunks broke in one frame).
var _support_dirty: bool = false
## World place of the last broken chunk: a collapsing mass tips toward it.
var _last_break: Vector3 = Vector3.INF
var _queued := {}


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
		if building.def.facade_only and _counts_for_floor(chunk):
			_floor_total[chunk.floor_index] = _floor_total.get(chunk.floor_index, 0.0) + chunk.volume
	# Links: chunks in the same grid cells are tested (whole-chunk bounds first, then the boxes).
	var list := building.chunks
	var bounds := {}
	var grid := {}
	for i in list.size():
		var all: Array = boxes[list[i]]
		var merged: AABB = all[0] if not all.is_empty() else AABB()
		for box: AABB in all:
			merged = merged.merge(box)
		merged = merged.grow(touch_gap)
		bounds[list[i]] = merged
		var low := Vector3i((merged.position / grid_cell).floor())
		var high := Vector3i((merged.end / grid_cell).floor())
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(i)
	var tested := {}
	for key: Vector3i in grid:
		var cell: Array = grid[key]
		for a in cell.size():
			for b in range(a + 1, cell.size()):
				var i: int = cell[a]
				var j: int = cell[b]
				var pair := mini(i, j) * 100000 + maxi(i, j)
				if tested.has(pair):
					continue
				tested[pair] = true
				if (bounds[list[i]] as AABB).intersects(bounds[list[j]]) and _touch(boxes[list[i]], boxes[list[j]]):
					_links[list[i]].append(list[j])
					_links[list[j]].append(list[i])


## A hit on a chunk (UrbanChunk.on_hit).
func damage(chunk: UrbanChunk, amount: float, from: Vector3 = Vector3.INF, kind: StringName = &"") -> void:
	if not _links.has(chunk) or amount <= 0.0:
		return
	var glass := chunk.kind == UrbanChunk.Kind.GLASS
	if not glass and (kind == &"blast" or amount >= scorch_min_damage):
		ScorchMark.add(chunk, from, scorch_blast_size if kind == &"blast" else scorch_shell_size)
	var threshold := chunk.material_def.damage_threshold if chunk.material_def != null else 0.0
	# A hit below the material's threshold still counts, but less (user request 2026-10-12: weak
	# guns wear walls down): x hit / threshold (an SMG shot of 35 on concrete (80) does 15).
	if amount < threshold:
		amount *= amount / threshold
	chunk.hp -= amount
	if chunk.hp <= 0.0:
		break_chunk(chunk)
	elif not glass and chunk.hp < chunk.max_hp * crack_below:
		ChunkCracks.add(chunk, _boxes_in_chunk(chunk))


## Breaks a chunk into rubble where it stands, then drops what lost its support.
func break_chunk(chunk: UrbanChunk) -> void:
	if not _links.has(chunk):
		return
	if chunk.material_def != null and chunk.material_def.display_name in rebar_materials:
		var neighbors := []
		for other: UrbanChunk in _links[chunk]:
			if other.kind not in NOT_CARRYING and other.get_parent() == chunk.get_parent():
				neighbors.append([other, _boxes_of(other)])
		Rebar.spawn(_space(chunk), _boxes_of(chunk), neighbors, rebar_per_face, touch_gap, rebar_per_break)
	var space := _space(chunk)
	_last_break = space.global_transform * _bounds_of(chunk).get_center()
	_remove(chunk)
	for box: AABB in _boxes_of(chunk):
		shatter(Transform3D(space.global_basis, space.global_transform * box.get_center()), box.size,
				_debris_color(chunk), Vector3.ZERO, false, chunk.kind == UrbanChunk.Kind.GLASS, false, _look(chunk))
	chunk.queue_free()
	if generator.def.facade_only and _counts_for_floor(chunk):
		_check_floor(chunk.floor_index)
	_support_dirty = true


## Breaks a box into rubble (and dust unless it is glass). hurts: the impact hurts mechs near it.
## light: one rubble piece and dust only now and then (many chunks at once, a tower collapse).
## FallingChunk calls it when a falling chunk lands.
func shatter(place: Transform3D, size: Vector3, color: Color, velocity: Vector3, hurts: bool, glass: bool = false,
		light: bool = false, look: Material = null) -> void:
	var world := _world()
	color.a = 1.0
	if not glass and (not light or randf() < 0.3):
		DustBurst.create(world, place.origin, size, dust_opacity)
	var volume := size.x * size.y * size.z
	var count := 1 if light else clampi(roundi(volume * rubble_per_m3), min_rubble, max_rubble)
	var smallest := minf(size.x, minf(size.y, size.z))
	var largest := maxf(size.x, maxf(size.y, size.z))
	for i in count:
		var side := lerpf(smallest, largest, 0.5) * randf_range(rubble_min_scale, rubble_max_scale)
		var piece := Vector3(side, side * randf_range(0.4, 1.0), side * randf_range(0.6, 1.2))
		if glass:
			piece = Vector3(side * 0.5, side * 0.5, 0.05)
		var offset := Vector3(randf_range(-0.4, 0.4) * size.x, randf_range(-0.4, 0.4) * size.y, randf_range(-0.4, 0.4) * size.z)
		var away := (offset.normalized() + Vector3.UP * 0.5) * rubble_speed * randf_range(0.5, 1.0)
		Rubble.spawn(world, place * offset, piece, color * randf_range(0.85, 1.05), velocity * 0.3 + away, look)
	if hurts and fall_damage > 0.0:
		Blast.apply(generator.get_world_3d(), place.origin, fall_radius, fall_damage, [], HITBOX_MASK)


## True while a chunk stands in the building (not broken, not fallen).
func is_standing(chunk: UrbanChunk) -> bool:
	return _links.has(chunk)


## True once any chunk of the building broke (its occluder is off for good).
func has_broken() -> bool:
	return _broken_any


## Chunks left standing (for tests).
func get_chunk_count() -> int:
	return _links.size()


func _remove(chunk: UrbanChunk) -> void:
	for other: UrbanChunk in _links[chunk]:
		if _links.has(other):
			_links[other].erase(chunk)
	_links.erase(chunk)
	_grounded.erase(chunk)
	if generator.def.facade_only and _counts_for_floor(chunk):
		_floor_lost[chunk.floor_index] = _floor_lost.get(chunk.floor_index, 0.0) + chunk.volume
	# Hide its boxes in the building look.
	var look := chunk.get_look(generator)
	for piece: Vector2i in chunk.pieces:
		var mm: MultiMesh = look[piece.x]
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
	var loose: Array[UrbanChunk] = []
	for chunk: UrbanChunk in _links.keys():
		if not supported.has(chunk) and not _queued.has(chunk):
			loose.append(chunk)
	if loose.size() >= mass_min_chunks:
		_collapse_as_mass(loose)
		return
	var added := false
	for chunk in loose:
		_queued[chunk] = true
		_fall_queue.append(chunk)
		added = true
	if added:
		_fall_queue = _fall_queue.filter(func(c: Variant) -> bool: return is_instance_valid(c))
		_fall_queue.sort_custom(func(a: UrbanChunk, b: UrbanChunk) -> bool: return a.position.y < b.position.y)


func _physics_process(_delta: float) -> void:
	if _support_dirty:
		_support_dirty = false
		_drop_unsupported()
	var count := 0
	while not _fall_queue.is_empty() and count < fall_per_frame:
		# Untyped: a queued chunk can be freed meanwhile (broken by a hit or a mech walking through).
		var chunk: Variant = _fall_queue.pop_front()
		_queued.erase(chunk)
		if is_instance_valid(chunk) and _links.has(chunk):
			_fall(chunk as UrbanChunk)
			count += 1


## A large loose group sags and leans as one mass and stays (CollapseMass, user choice 2026-10-21): its
## chunks keep their links among themselves, lose the links to the rest, stand on the ground for good,
## and become children of the mass, which draws their boxes and tips toward the last break.
func _collapse_as_mass(loose: Array[UrbanChunk]) -> void:
	var in_mass := {}
	var area := AABB()
	var first := true
	for chunk in loose:
		in_mass[chunk] = true
		var box := _space(chunk).global_transform * _bounds_of(chunk)
		area = box if first else area.merge(box)
		first = false
	var center := area.get_center()
	var toward := (_last_break - center) if _last_break != Vector3.INF else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	toward.y = 0.0
	var mass := CollapseMass.new()
	mass.building = self
	mass.bounds = area
	mass.tip_direction = toward.normalized() if toward.length_squared() > 0.01 else Vector3.FORWARD
	mass.ground_y = generator.global_position.y
	var materials: Array[Material] = []
	for slot in generator.multimeshes.size():
		materials.append(generator.slot_material(slot))
	mass.make_look(generator.multimeshes.size(), materials)
	var world := _world() as Node3D
	mass.position = world.global_transform.affine_inverse() * CollapseMass.pivot_of(area, mass.tip_direction)
	world.add_child(mass)
	# The boxes of each chunk move from the building's MultiMeshes to the mass's.
	var lists := {}
	for chunk in loose:
		for other: UrbanChunk in _links[chunk].duplicate():
			if not in_mass.has(other):
				_links[chunk].erase(other)
				if _links.has(other):
					_links[other].erase(chunk)
		_grounded[chunk] = true
		_queued.erase(chunk)
		var shapes: Array[CollisionShape3D] = []
		for child in chunk.get_children():
			if child is CollisionShape3D:
				shapes.append(child as CollisionShape3D)
		var old_look := chunk.get_look(generator)
		chunk.reparent(mass, true)
		var moved: Array[Vector2i] = []
		for i in chunk.pieces.size():
			var piece := chunk.pieces[i]
			old_look[piece.x].set_instance_transform(piece.y, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			if i >= shapes.size():
				continue
			var size := (shapes[i].shape as BoxShape3D).size
			var list: Array = lists.get_or_add(piece.x, [])
			moved.append(Vector2i(piece.x, list.size()))
			list.append(chunk.transform * Transform3D(Basis.from_scale(size), shapes[i].position))
		chunk.pieces = moved
		chunk.look = mass.multimeshes
	for slot: int in lists:
		var mm := mass.multimeshes[slot]
		var list: Array = lists[slot]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])


## Towers: a floor that lost collapse_fraction of its walls and columns gives way; every chunk from that
## floor up loses its support (they fall, lowest first).
func _check_floor(floor_index: int) -> void:
	var total: float = _floor_total.get(floor_index, 0.0)
	if total <= 0.0 or (_collapsed_from >= 0 and floor_index >= _collapsed_from):
		return
	if _floor_lost.get(floor_index, 0.0) < total * collapse_fraction:
		return
	_collapsed_from = floor_index
	for chunk: UrbanChunk in _links.keys():
		if chunk.floor_index >= floor_index:
			# Cut its links: nothing holds it now.
			_grounded.erase(chunk)
			for other: UrbanChunk in _links[chunk]:
				if _links.has(other) and other.floor_index < floor_index:
					_links[other].erase(chunk)
			_links[chunk] = _links[chunk].filter(func(o: UrbanChunk) -> bool: return o.floor_index >= floor_index)


## Tower walls and columns count for the floor collapse (not glass, doors, the core or the roof).
static func _counts_for_floor(chunk: UrbanChunk) -> bool:
	return chunk.kind == UrbanChunk.Kind.WALL or chunk.kind == UrbanChunk.Kind.COLUMN


## A chunk becomes a falling body made of its boxes (a little smaller, so it does not catch on its
## old neighbors). Past max_falling it breaks where it is.
func _fall(chunk: UrbanChunk) -> void:
	var boxes := _boxes_of(chunk)
	_remove(chunk)
	var color := _debris_color(chunk)
	if _falling_now >= max_falling or boxes.is_empty():
		for box: AABB in boxes:
			shatter(Transform3D(_space(chunk).global_basis, _space(chunk).global_transform * box.get_center()), box.size,
					color, Vector3.ZERO, false, chunk.kind == UrbanChunk.Kind.GLASS, true, _look(chunk))
		chunk.queue_free()
		return
	var bounds := boxes[0]
	for box: AABB in boxes:
		bounds = bounds.merge(box)
	var body := FallingChunk.new()
	body.building = self
	body.size = bounds.size
	body.tint = color
	body.look = _look(chunk)
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
	body.global_transform = Transform3D(_space(chunk).global_basis, _space(chunk).global_transform * bounds.get_center())
	body.angular_velocity = Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4))
	_falling_now += 1
	body.tree_exited.connect(func() -> void: _falling_now -= 1)
	chunk.queue_free()


## The node whose space the chunk's boxes are in: the building, or the CollapseMass it leans with.
func _space(chunk: UrbanChunk) -> Node3D:
	return chunk.get_parent() as Node3D


## All the chunk's boxes in one (in its parent's space).
func _bounds_of(chunk: UrbanChunk) -> AABB:
	var boxes := _boxes_of(chunk)
	var bounds := boxes[0] if not boxes.is_empty() else AABB(chunk.position, Vector3.ZERO)
	for box in boxes:
		bounds = bounds.merge(box)
	return bounds


## The chunk's boxes in its own space (from its collision shapes).
func _boxes_in_chunk(chunk: UrbanChunk) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for child in chunk.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			var size := (shape.shape as BoxShape3D).size
			boxes.append(AABB(shape.position - size * 0.5, size))
	return boxes


## The chunk's boxes in its parent's space (the building or a CollapseMass), from its collision shapes.
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


## The chunk's own material for its rubble (null: no material, rubble in the debris color).
func _look(chunk: UrbanChunk) -> Material:
	return chunk.material_def.get_material() if chunk.material_def != null else null


func _debris_color(chunk: UrbanChunk) -> Color:
	return chunk.material_def.debris_color if chunk.material_def != null else Color(0.5, 0.5, 0.5)


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else generator.get_parent()
