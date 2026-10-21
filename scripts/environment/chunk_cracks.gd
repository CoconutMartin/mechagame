class_name ChunkCracks
extends RefCounted
## Crack stage of a damaged building chunk (phase 5b, user choice 2026-10-19): a chunk below
## BuildingDamage.crack_below of its HP gets a thin see-through shell over each of its boxes with
## cracks on a dark film, so it looks cracked and darker before it breaks. A mesh (not a Decal), so it
## shows in every renderer. The shell is a child of the chunk and goes when the chunk breaks or falls.

const TEXTURE := preload("res://assets/textures/decals/crack_overlay.png")
## The shell stands this far out of the chunk's faces (m).
const LIFT := 0.03
## Meters per crack texture repeat.
const TEXTURE_SCALE_M := 3.0

static var _mesh: BoxMesh
static var _material: StandardMaterial3D


## Adds the crack shell to a chunk. boxes: the chunk's boxes in its own space.
static func add(chunk: UrbanChunk, boxes: Array[AABB]) -> void:
	if chunk.has_meta(&"cracked"):
		return
	chunk.set_meta(&"cracked", true)
	_setup()
	for box in boxes:
		var shell := MeshInstance3D.new()
		shell.name = "Cracks"
		shell.mesh = _mesh
		shell.material_override = _material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.position = box.get_center()
		shell.scale = box.size + Vector3.ONE * LIFT * 2.0
		chunk.add_child(shell)


static func _setup() -> void:
	if _mesh != null:
		return
	_mesh = BoxMesh.new()
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_texture = TEXTURE
	_material.roughness = 1.0
	_material.uv1_triplanar = true
	_material.uv1_world_triplanar = true
	var repeat := 1.0 / TEXTURE_SCALE_M
	_material.uv1_scale = Vector3(repeat, repeat, repeat)
	_material.uv1_triplanar_sharpness = 8.0
