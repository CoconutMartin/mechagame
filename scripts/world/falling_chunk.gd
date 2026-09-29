class_name FallingChunk
extends RigidBody3D
## A building block that lost its support. It falls, and when it hits the ground or the building
## it breaks into rubble with dust and hurts the mechs near the impact.

## Set by DestructibleBuilding before it enters the tree.
var building: DestructibleBuilding
var size: Vector3 = Vector3.ONE
var tint: Color = Color.GRAY

var _age: float = 0.0
var _broken: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 1


func _physics_process(delta: float) -> void:
	_age += delta
	# Blocks start close to the rest of the building: a contact counts after a moment. A block that
	# never touches anything still breaks (safety).
	if (_age > 0.15 and get_contact_count() > 0) or _age > 6.0:
		_break()


func _break() -> void:
	if _broken:
		return
	_broken = true
	if building != null:
		building.shatter(global_transform, size, tint, linear_velocity, true)
	queue_free()
