@tool
class_name BuildingGenerator
extends Node3D
## Builds a building from a BuildingDef, in the editor and in the game (urban map).
## The origin is the bottom center of the footprint. The front face (shop windows, door) faces -Z.
##   Per floor: wall panels along each face (about chunk_width wide; a window opening per panel with
##   the glass set back in it), a floor slab on top, interior columns on a grid.
##   Roof: parapet (PARAPET), parapet and gravel (GRAVEL) or nothing (FLAT).
##   Towers (facade_only): a dark core box and columns behind the facade instead of open floors.
## Look: one MultiMesh per material (few draw calls). In the game each chunk is also an UrbanChunk
## (StaticBody3D, layer 1) with its box shapes. Edge buildings (indestructible) get one box collider.
## Generated nodes are internal: they are never saved in the scene.

const LIT_GLASS := preload("res://data/environment/materials/glass_lit.tres")
const INTERIOR := preload("res://data/environment/materials/interior.tres")
const SLAB_THICKNESS := 0.3
const COLUMN_SIZE := 0.6
const GLASS_THICKNESS := 0.06
const DOOR_SIZE := Vector2(1.0, 2.0)

@export var def: BuildingDef:
	set(value):
		def = value
		_queue_build()
## Changes which windows are lit.
@export var variant_seed: int = 0:
	set(value):
		variant_seed = value
		_queue_build()
## Part of the windows with a warm light.
@export_range(0.0, 1.0) var lit_window_chance: float = 0.08:
	set(value):
		lit_window_chance = value
		_queue_build()
## Strength growth with footprint area: integrity x (1 + this x area / 100 m²).
@export var area_strength_per_100m2: float = 0.25

## Chunks made in the game (empty in the editor).
var chunks: Array[UrbanChunk] = []
## One MultiMesh per material slot (see _slots).
var multimeshes: Array[MultiMesh] = []
var occluder: OccluderInstance3D

var _slots: Array[MaterialDef] = []
var _transforms: Array = []   # per slot: Array[Transform3D]
var _rng := RandomNumberGenerator.new()
var _queued := false
var _generated: Array[Node] = []


func _ready() -> void:
	build()


func _queue_build() -> void:
	if not is_node_ready() or _queued:
		return
	_queued = true
	build.call_deferred()


## Chunk HP multiplier of a building (tune here): its integrity multiplier, growing with the footprint
## area, so big buildings resist more.
func integrity_of(building: BuildingDef) -> float:
	var area := building.footprint_x * building.footprint_z
	return building.integrity_multiplier * (1.0 + area_strength_per_100m2 * area / 100.0)


func build() -> void:
	_queued = false
	for node in _generated:
		if is_instance_valid(node):
			node.queue_free()
	_generated.clear()
	chunks.clear()
	multimeshes.clear()
	_slots.clear()
	_transforms.clear()
	if def == null:
		return
	_rng.seed = hash(variant_seed) ^ hash(def.resource_path)
	var runtime := not Engine.is_editor_hint() and not def.indestructible
	for i in def.floor_count:
		_floor(i, runtime)
	_roof(runtime)
	if def.facade_only:
		_core(runtime)
	_make_multimeshes()
	_make_occluder()
	if not Engine.is_editor_hint() and def.indestructible:
		_single_collider()


# ---- Floors ----

func _floor(index: int, runtime: bool) -> void:
	var bottom := def.floor_bottom(index)
	var height := def.floor_top(index) - bottom
	var hx := def.footprint_x * 0.5
	var hz := def.footprint_z * 0.5
	var t := def.wall_thickness
	# Faces: [start, direction along the face, outward normal, length]. X faces run full width.
	var faces := [
		[Vector3(-hx, 0.0, -hz + t * 0.5), Vector3.RIGHT, Vector3.FORWARD, def.footprint_x, true],
		[Vector3(-hx, 0.0, hz - t * 0.5), Vector3.RIGHT, Vector3.BACK, def.footprint_x, false],
		[Vector3(-hx + t * 0.5, 0.0, -hz + t), Vector3.BACK, Vector3.LEFT, def.footprint_z - 2.0 * t, false],
		[Vector3(hx - t * 0.5, 0.0, -hz + t), Vector3.BACK, Vector3.RIGHT, def.footprint_z - 2.0 * t, false],
	]
	for face in faces:
		var length: float = face[3]
		var count := maxi(1, roundi(length / def.chunk_width))
		var width := length / count
		for p in count:
			var shop: bool = index == 0 and def.shop_front and face[4]
			var door: bool = shop and p == int(count / 2.0)
			_panel(face[0] + face[1] * (width * (p + 0.5)), face[1], face[2], width, bottom, height, index, shop, door, runtime)
	if not def.facade_only:
		_slab(index, def.floor_top(index), runtime)
		_columns(index, bottom, height - SLAB_THICKNESS, runtime)


## One wall panel: four pieces around a window opening (or one solid piece), glass in the opening.
func _panel(center: Vector3, along: Vector3, normal: Vector3, width: float, bottom: float, height: float,
		floor_index: int, shop: bool, door: bool, runtime: bool) -> void:
	var t := def.wall_thickness
	var ratio := 0.8 if shop else def.window_ratio
	var open_w := width * ratio
	var open_h := minf(height - 0.6, 2.8) if shop else height * def.window_height_ratio
	var sill := 0.35 if shop else (height - open_h) * 0.45
	if door:
		open_w = DOOR_SIZE.x
		open_h = DOOR_SIZE.y
		sill = 0.0
	var wall := _chunk(UrbanChunk.Kind.WALL, floor_index, def.wall_material, runtime)
	var base := center + Vector3(0.0, bottom, 0.0)
	if open_w <= 0.05 or open_h <= 0.05:
		_piece(wall, def.wall_material, base + Vector3(0.0, height * 0.5, 0.0), _size(along, normal, width, height, t))
	else:
		var side_w := (width - open_w) * 0.5
		var top_h := height - sill - open_h
		if sill > 0.01:
			_piece(wall, def.wall_material, base + Vector3(0.0, sill * 0.5, 0.0), _size(along, normal, width, sill, t))
		_piece(wall, def.wall_material, base + Vector3(0.0, sill + open_h + top_h * 0.5, 0.0), _size(along, normal, width, top_h, t))
		for s in [-1.0, 1.0]:
			var offset: Vector3 = along * (s * (open_w * 0.5 + side_w * 0.5))
			_piece(wall, def.wall_material, base + offset + Vector3(0.0, sill + open_h * 0.5, 0.0), _size(along, normal, side_w, open_h, t))
		var fill_kind := UrbanChunk.Kind.DOOR if door else UrbanChunk.Kind.GLASS
		var fill_mat: MaterialDef = def.door_material if door else def.glass_material
		if not door and _rng.randf() < lit_window_chance:
			fill_mat = LIT_GLASS
		var fill := _chunk(fill_kind, floor_index, fill_mat, runtime)
		var thick := 0.12 if door else GLASS_THICKNESS
		_piece(fill, fill_mat, base + Vector3(0.0, sill + open_h * 0.5, 0.0), _size(along, normal, open_w, open_h, thick))
		_finish_chunk(fill)
	_finish_chunk(wall)


func _slab(floor_index: int, top: float, runtime: bool) -> void:
	var t := def.wall_thickness
	var slab := _chunk(UrbanChunk.Kind.SLAB, floor_index, def.frame_material, runtime)
	_piece(slab, def.frame_material, Vector3(0.0, top - SLAB_THICKNESS * 0.5, 0.0),
		Vector3(def.footprint_x - 2.0 * t, SLAB_THICKNESS, def.footprint_z - 2.0 * t))
	_finish_chunk(slab)


func _columns(floor_index: int, bottom: float, height: float, runtime: bool) -> void:
	for x in _grid(def.footprint_x):
		for z in _grid(def.footprint_z):
			var column := _chunk(UrbanChunk.Kind.COLUMN, floor_index, def.frame_material, runtime)
			_piece(column, def.frame_material, Vector3(x, bottom + height * 0.5, z), Vector3(COLUMN_SIZE, height, COLUMN_SIZE))
			_finish_chunk(column)


## Interior column positions along one footprint side (none when the side is short).
func _grid(length: float) -> Array[float]:
	var spots: Array[float] = []
	var count := floori(length / def.column_spacing)
	for i in range(1, count + 1):
		var pos := -length * 0.5 + length * i / (count + 1)
		spots.append(pos)
	return spots


func _roof(runtime: bool) -> void:
	var top := def.get_height()
	var top_floor := def.floor_count - 1
	if def.roof_type == BuildingDef.RoofType.FLAT:
		return
	var rise := 1.0 if def.roof_type == BuildingDef.RoofType.PARAPET else 0.5
	var t := def.wall_thickness
	var hx := def.footprint_x * 0.5
	var hz := def.footprint_z * 0.5
	for side in [
			[Vector3(0.0, 0.0, -hz + t * 0.5), Vector3(def.footprint_x, rise, t)],
			[Vector3(0.0, 0.0, hz - t * 0.5), Vector3(def.footprint_x, rise, t)],
			[Vector3(-hx + t * 0.5, 0.0, 0.0), Vector3(t, rise, def.footprint_z - 2.0 * t)],
			[Vector3(hx - t * 0.5, 0.0, 0.0), Vector3(t, rise, def.footprint_z - 2.0 * t)]]:
		var parapet := _chunk(UrbanChunk.Kind.PARAPET, top_floor, def.frame_material, runtime)
		_piece(parapet, def.frame_material, side[0] + Vector3(0.0, top + rise * 0.5, 0.0), side[1])
		_finish_chunk(parapet)
	if def.roof_type == BuildingDef.RoofType.GRAVEL and def.roof_material != null:
		var gravel := _chunk(UrbanChunk.Kind.ROOF, top_floor, def.roof_material, runtime)
		_piece(gravel, def.roof_material, Vector3(0.0, top + 0.05, 0.0), Vector3(def.footprint_x - 2.0 * t, 0.1, def.footprint_z - 2.0 * t))
		_finish_chunk(gravel)


## Tower core: a dark box behind the facade and a ring of columns between it and the walls.
func _core(runtime: bool) -> void:
	var top := def.get_height()
	var inset := 2.4
	var core := _chunk(UrbanChunk.Kind.CORE, 0, INTERIOR, runtime)
	_piece(core, INTERIOR, Vector3(0.0, top * 0.5, 0.0), Vector3(def.footprint_x - 2.0 * inset, top, def.footprint_z - 2.0 * inset))
	_finish_chunk(core)
	var ring := def.wall_thickness + 1.0
	var step := def.chunk_width * 2.0
	for i in def.floor_count:
		var bottom := def.floor_bottom(i)
		var height := def.floor_top(i) - bottom
		var spots: Array[Vector3] = []
		var span_x := def.footprint_x - 2.0 * ring
		var span_z := def.footprint_z - 2.0 * ring
		var nx := maxi(int(span_x / step), 1)
		var nz := maxi(int(span_z / step), 1)
		for x in nx + 1:
			var px := -span_x * 0.5 + span_x * x / nx
			spots.append(Vector3(px, 0.0, -span_z * 0.5))
			spots.append(Vector3(px, 0.0, span_z * 0.5))
		for z in range(1, nz):
			var pz := -span_z * 0.5 + span_z * z / nz
			spots.append(Vector3(-span_x * 0.5, 0.0, pz))
			spots.append(Vector3(span_x * 0.5, 0.0, pz))
		for spot in spots:
			var column := _chunk(UrbanChunk.Kind.COLUMN, i, def.frame_material, runtime)
			_piece(column, def.frame_material, spot + Vector3(0.0, bottom + height * 0.5, 0.0), Vector3(COLUMN_SIZE, height, COLUMN_SIZE))
			_finish_chunk(column)


# ---- Pieces and chunks ----

func _size(along: Vector3, normal: Vector3, width: float, height: float, thickness: float) -> Vector3:
	return along.abs() * width + Vector3(0.0, height, 0.0) + normal.abs() * thickness


## A chunk (game only; null in the editor).
func _chunk(kind: UrbanChunk.Kind, floor_index: int, material: MaterialDef, runtime: bool) -> UrbanChunk:
	if not runtime:
		return null
	var chunk := UrbanChunk.new()
	chunk.kind = kind
	chunk.floor_index = floor_index
	chunk.material_def = material
	chunk.building = self
	chunk.collision_layer = 1
	chunk.collision_mask = 0
	return chunk


## One box of a chunk: a MultiMesh instance and (in the game) a collision box.
func _piece(chunk: UrbanChunk, material: MaterialDef, center: Vector3, size: Vector3) -> void:
	if material == null or size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
	var slot := _slots.find(material)
	if slot < 0:
		slot = _slots.size()
		_slots.append(material)
		_transforms.append([])
	var list: Array = _transforms[slot]
	list.append(Transform3D(Basis.from_scale(size), center))
	if chunk == null:
		return
	chunk.pieces.append(Vector2i(slot, list.size() - 1))
	chunk.volume += size.x * size.y * size.z
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	chunk.add_child(shape)


func _finish_chunk(chunk: UrbanChunk) -> void:
	if chunk == null:
		return
	if chunk.get_child_count() == 0:
		chunk.free()
		return
	var strength := chunk.material_def.hp_per_m3 if chunk.material_def != null else 100.0
	chunk.max_hp = chunk.volume * strength * integrity_of(def)
	chunk.hp = chunk.max_hp
	chunks.append(chunk)
	_add(chunk)


func _make_multimeshes() -> void:
	var box := BoxMesh.new()
	for slot in _slots.size():
		var list: Array = _transforms[slot]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		multimeshes.append(mm)
		var view := MultiMeshInstance3D.new()
		view.name = "Look_%s" % _slots[slot].resource_path.get_file().get_basename()
		view.multimesh = mm
		view.material_override = _slots[slot].get_material()
		# Buildings use dynamic GI (SDFGI); only the ground is baked into the lightmap.
		view.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		_add(view)


func _make_occluder() -> void:
	occluder = OccluderInstance3D.new()
	var box := BoxOccluder3D.new()
	var h := def.get_height()
	box.size = Vector3(maxf(def.footprint_x - 1.0, 0.5), maxf(h - 0.5, 0.5), maxf(def.footprint_z - 1.0, 0.5))
	occluder.occluder = box
	occluder.position = Vector3(0.0, h * 0.5, 0.0)
	_add(occluder)


## Edge buildings: one collider for the whole building.
func _single_collider() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var h := def.get_height() + (1.0 if def.roof_type != BuildingDef.RoofType.FLAT else 0.0)
	box.size = Vector3(def.footprint_x, h, def.footprint_z)
	shape.shape = box
	shape.position = Vector3(0.0, h * 0.5, 0.0)
	body.add_child(shape)
	_add(body)


func _add(node: Node) -> void:
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	_generated.append(node)
