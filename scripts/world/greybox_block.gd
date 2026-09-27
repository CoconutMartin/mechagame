@tool
class_name GreyboxBlock
extends StaticBody3D
## A box with matching collision, for greybox buildings, walls, and platforms.
## The origin is at the bottom center, so it sits on the ground at y = 0.
## Change Size in the Inspector and the mesh and collision update.

const GRID_MATERIAL := preload("res://materials/greybox_grid.tres")
const DOOR_MATERIAL := preload("res://materials/door.tres")
const DOOR_SIZE := Vector3(1.2, 2.0, 0.2)

@export var size: Vector3 = Vector3(20.0, 30.0, 20.0):
	set(value):
		size = value
		_rebuild()
@export var tint: Color = Color(0.55, 0.55, 0.56):
	set(value):
		tint = value
		_rebuild()
## Adds a 2 m door on the +Z face, to show human scale.
@export var add_door: bool = false:
	set(value):
		add_door = value
		_rebuild()

var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _door: MeshInstance3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_shape = CollisionShape3D.new()
		_door = MeshInstance3D.new()
		# Internal children are rebuilt from Size and never saved in the scene.
		add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)
		add_child(_shape, false, Node.INTERNAL_MODE_FRONT)
		add_child(_door, false, Node.INTERNAL_MODE_FRONT)

	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_mesh.material_override = GRID_MATERIAL
	_mesh.set_instance_shader_parameter("tint", tint)
	_mesh.position = Vector3(0.0, size.y * 0.5, 0.0)

	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape
	_shape.position = _mesh.position

	var door_box := BoxMesh.new()
	door_box.size = DOOR_SIZE
	_door.mesh = door_box
	_door.material_override = DOOR_MATERIAL
	_door.position = Vector3(0.0, DOOR_SIZE.y * 0.5, size.z * 0.5)
	_door.visible = add_door
