@tool
class_name GroundSlab
extends StaticBody3D
## A flat box of ground (road, sidewalk, curb, plaza, parking lot) on layer 1 (world).
## The origin is the TOP center, so position.y is the walking height (roads 0, sidewalks 0.15).
## Its mesh has lightmap UVs and static GI: LightmapGI bakes the ground only.

@export var size: Vector3 = Vector3(10.0, 0.15, 10.0):
	set(value):
		size = value
		_rebuild()
@export var material_def: MaterialDef:
	set(value):
		material_def = value
		_rebuild()

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_shape = CollisionShape3D.new()
		# Built from Size; never saved in the scene.
		add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)
		add_child(_shape, false, Node.INTERNAL_MODE_FRONT)
	var box := BoxMesh.new()
	box.size = size
	box.add_uv2 = true
	_mesh.mesh = box
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_mesh.position = Vector3(0.0, -size.y * 0.5, 0.0)
	if material_def != null:
		_mesh.material_override = material_def.get_material()
	var shape := BoxShape3D.new()
	shape.size = size
	_shape.shape = shape
	_shape.position = _mesh.position
