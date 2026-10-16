class_name CameraWallSeeThrough
extends Node
## Building pieces between the camera and its mech are hidden, so a wall behind the player never
## blocks the view (user report 2026-10-16). The camera spring arm does not collide with buildings
## (layer 5), so the camera can be inside or behind a wall. Each physics frame boxes from the camera to
## the mech's chest and hips, and one to the screen center at the same depth, finds the building chunks in the
## way. Their pieces in the building MultiMeshes are hidden, and the building's occluder is off (it
## would hide the mech). A piece comes back when it is out of the way and still stands.
## MechCameraRig adds this node at runtime; it only works while its camera is the current one.

## Building chunks (layer 5).
const BUILDING_MASK := 16

@export var camera: Camera3D
## The mech the camera follows.
@export var mech: Node3D
## Width and height of the box from the camera to the mech (meters).
@export var corridor_width: float = 4.0
## Heights on the mech (meters above its origin) the boxes go to: the chest and the hips.
@export var chest_height: float = 6.0
@export var hip_height: float = 2.5
## The box stops this far before the mech (meters), so a wall the mech touches in front of it stays.
@export var stop_before_mech: float = 1.5

## Hidden chunks: UrbanChunk -> Array of [multimesh slot, instance, transform before].
var _hidden: Dictionary = {}
## Buildings whose occluder this node turned off (BuildingGenerator -> its BuildingDamage or null).
var _occluders_off: Dictionary = {}
var _box := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	_query.shape = _box
	_query.collision_mask = BUILDING_MASK
	_query.collide_with_areas = false


func _physics_process(_delta: float) -> void:
	if camera == null or mech == null or not camera.is_current():
		_show_all()
		return
	var from := camera.global_position
	var chest := mech.global_position + Vector3.UP * chest_height
	var depth := (chest - from).dot(-camera.global_basis.z)
	var center := from - camera.global_basis.z * depth
	var found := {}
	_collect(from, chest, found)
	_collect(from, mech.global_position + Vector3.UP * hip_height, found)
	_collect(from, center, found)
	for chunk: UrbanChunk in found:
		if not _hidden.has(chunk):
			_hide(chunk)
	for chunk: UrbanChunk in _hidden.keys():
		if not found.has(chunk):
			_show(chunk)
	_update_occluders()


func _exit_tree() -> void:
	_show_all()


## Adds the chunks in a box from `from` to `to` (stopping stop_before_mech short of it) to `found`.
func _collect(from: Vector3, to: Vector3, found: Dictionary) -> void:
	var line := to - from
	var length := line.length() - stop_before_mech
	if length <= 0.1:
		return
	var forward := line.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(forward, up)
	_box.size = Vector3(corridor_width, corridor_width, length)
	_query.transform = Transform3D(basis, from + forward * (length * 0.5))
	for result in mech.get_world_3d().direct_space_state.intersect_shape(_query, 128):
		var chunk := result.collider as UrbanChunk
		if chunk != null and chunk.building is BuildingGenerator:
			found[chunk] = true


func _hide(chunk: UrbanChunk) -> void:
	var generator := chunk.building as BuildingGenerator
	var saved: Array = []
	for piece: Vector2i in chunk.pieces:
		var mm: MultiMesh = generator.multimeshes[piece.x]
		saved.append([piece.x, piece.y, mm.get_instance_transform(piece.y)])
		mm.set_instance_transform(piece.y, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_hidden[chunk] = saved


## Puts a chunk's pieces back, unless it broke or fell meanwhile (BuildingDamage hid it for good).
func _show(chunk: UrbanChunk) -> void:
	var saved: Array = _hidden[chunk]
	_hidden.erase(chunk)
	if not is_instance_valid(chunk):
		return
	if chunk.damage_owner != null and not chunk.damage_owner.is_standing(chunk):
		return
	var generator := chunk.building as BuildingGenerator
	for entry: Array in saved:
		(generator.multimeshes[entry[0]] as MultiMesh).set_instance_transform(entry[1], entry[2])


func _show_all() -> void:
	for chunk: UrbanChunk in _hidden.keys():
		_show(chunk)
	_update_occluders()


## A building with hidden pieces has its occluder off; it comes back when none are hidden (and the
## building had not lost it to damage meanwhile).
func _update_occluders() -> void:
	var busy := {}
	for chunk: UrbanChunk in _hidden:
		if is_instance_valid(chunk):
			busy[chunk.building] = chunk.damage_owner
	for building: BuildingGenerator in busy:
		if not _occluders_off.has(building) and building.occluder != null and building.occluder.visible:
			building.occluder.visible = false
			_occluders_off[building] = busy[building]
	for building: BuildingGenerator in _occluders_off.keys():
		if busy.has(building):
			continue
		var damage: BuildingDamage = _occluders_off[building]
		_occluders_off.erase(building)
		if is_instance_valid(building) and building.occluder != null \
				and (damage == null or not is_instance_valid(damage) or not damage.has_broken()):
			building.occluder.visible = true
