class_name MechBuildingContact
extends Node
## Mechs walk through buildings (user request 2026-10-12): building chunks are on layer 5, which the
## mech body does not collide with. While the mech moves through a building, each part whose hitbox is
## inside a chunk takes a little damage (it adds up: walking through many buildings can break parts),
## and the chunks it pushes through take damage too (walls break as the mech plows through).

const BUILDING_LAYER := 16

@export var mech: Mech
@export var health: MechHealth
## Damage per second to each part inside a building at walking speed (0.3 x this when slow, more when
## running or boosting: x speed / walk speed).
@export var part_damage_per_second: float = 12.0
## Damage per second to each chunk the mech moves through, at walking speed.
@export var chunk_damage_per_second: float = 500.0
## Below this speed (m/s) nothing happens (standing inside a building).
@export var min_speed: float = 0.5
## Seconds between checks.
@export var interval: float = 0.2

var _wait: float = 0.0


func _physics_process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = interval
	if mech == null or health == null or not health.is_alive():
		return
	var speed := Vector3(mech.velocity.x, 0.0, mech.velocity.z).length()
	if speed < min_speed:
		return
	var pace := maxf(speed / maxf(mech.walk_speed, 0.1), 0.3)
	var space := mech.get_world_3d().direct_space_state
	var chunks := {}
	for key: String in health.hitboxes:
		if not health.is_part_alive(key):
			continue
		var inside := false
		for hitbox: PartHitbox in health.hitboxes[key]:
			if not is_instance_valid(hitbox) or not hitbox.is_inside_tree():
				continue
			for chunk in _chunks_in(space, hitbox):
				chunks[chunk] = true
				inside = true
		if inside:
			health.damage(key, part_damage_per_second * pace * interval)
	for chunk: Node in chunks:
		if is_instance_valid(chunk):
			chunk.on_hit(chunk_damage_per_second * pace * interval)


## Building chunks that overlap a hitbox's boxes.
func _chunks_in(space: PhysicsDirectSpaceState3D, hitbox: PartHitbox) -> Array:
	var found: Array = []
	for child in hitbox.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.shape == null or shape.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.collision_mask = BUILDING_LAYER
		for result in space.intersect_shape(query, 8):
			if result.collider is UrbanChunk and not found.has(result.collider):
				found.append(result.collider)
	return found
