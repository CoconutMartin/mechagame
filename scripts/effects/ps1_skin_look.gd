class_name PS1SkinLook
extends Node
## PS1-style skin of the rigged mech (user request 2026-10-11, PS1-era mech references): every body
## mesh gets shaders/ps1_skin.gdshader with a pixel texture and tint by its bone: gunmetal armor
## panels, khaki ribbed plates (pelvis, thighs, feet), dark joint metal; yellow hazard stripes on the
## shoulder blocks, forearms, shins and torso; a red emblem on the outer face of the right shoulder block. The pattern
## sits on the part's rest position (to_rest each frame, like CharDamageLook), so it stays on the part.

const SHADER := preload("res://shaders/ps1_skin.gdshader")
const ARMOR_TEXTURE := preload("res://assets/textures/ps1/metal_panels.png")
const PLATE_TEXTURE := preload("res://assets/textures/ps1/ribbed_plates.png")
const JOINT_TEXTURE := preload("res://assets/textures/ps1/joint_metal.png")

@export var hitboxes: SkeletalHitboxes
## Part colors (the grey textures are multiplied by them).
@export var armor_tint: Color = Color(0.21, 0.22, 0.22)
@export var plate_tint: Color = Color(0.35, 0.31, 0.21)
@export var joint_tint: Color = Color(0.13, 0.13, 0.13)
@export var stripe_color: Color = Color(0.86, 0.66, 0.12)
## Texture pixels per meter (bigger = finer pixels).
@export var texels_per_meter: float = 16.0
## Screen grid of the vertex snap (the PS1 wobble); (0, 0) = no snap.
@export var snap_grid: Vector2 = Vector2(640.0, 480.0)
## Bones whose meshes get khaki ribbed plates.
@export var plate_bones: PackedStringArray = ["pelvis", "thigh_L", "thigh_R", "foot_L", "foot_R"]
## Stripe bands per bone: [from, to] as parts of the mesh height (from its bottom, at rest).
@export var stripes: Dictionary = {
	"upper_arm_L": Vector2(0.12, 0.21), "upper_arm_R": Vector2(0.12, 0.21),
	"forearm_L": Vector2(0.6, 0.69), "forearm_R": Vector2(0.6, 0.69),
	"shin_L": Vector2(0.7, 0.78), "shin_R": Vector2(0.7, 0.78),
	"torso": Vector2(0.1, 0.17),
}
## Mesh with the emblem, the side it is on (mesh rest space; -X = the mech's right, the outer face
## of the right shoulder block, seen even with a shoulder weapon on top), and its radius (m).
@export var emblem_mesh: StringName = &"Arm_R_01"
@export var emblem_side: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var emblem_radius: float = 0.38

## [MeshInstance3D, ShaderMaterial] pairs.
var _skins: Array = []


func _ready() -> void:
	var skeleton := hitboxes.skeleton
	var index := 0
	for mesh: MeshInstance3D in hitboxes.mesh_bones:
		var bone_name := String(skeleton.get_bone_name(hitboxes.mesh_bones[mesh]))
		var material := _material(mesh, bone_name, index)
		mesh.material_override = material
		_skins.append([mesh, material])
		index += 1
	skeleton.skeleton_updated.connect(_follow_bones)


func _material(mesh: MeshInstance3D, bone_name: String, index: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var joint := String(mesh.name).to_lower().contains("joint") or bone_name.begins_with("hand")
	var texture: Texture2D = ARMOR_TEXTURE
	var tint := armor_tint
	if joint:
		texture = JOINT_TEXTURE
		tint = joint_tint
	elif bone_name in plate_bones:
		texture = PLATE_TEXTURE
		tint = plate_tint
	material.set_shader_parameter(&"grey_texture", texture)
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"texels_per_meter", texels_per_meter)
	material.set_shader_parameter(&"texture_size", float(texture.get_width()))
	material.set_shader_parameter(&"uv_offset", Vector2(0.37 * index, 0.61 * index))
	material.set_shader_parameter(&"snap_grid", snap_grid)
	var box := mesh.get_aabb()
	if not joint and stripes.has(bone_name):
		var band: Vector2 = stripes[bone_name]
		material.set_shader_parameter(&"stripe_color", stripe_color)
		material.set_shader_parameter(&"stripe_min", box.position.y + box.size.y * band.x)
		material.set_shader_parameter(&"stripe_max", box.position.y + box.size.y * band.y)
	if mesh.name == emblem_mesh:
		var side := emblem_side.normalized()
		material.set_shader_parameter(&"emblem_normal", side)
		material.set_shader_parameter(&"emblem_center", _face_center(mesh.mesh, side))
		material.set_shader_parameter(&"emblem_radius", emblem_radius)
	return material


## Middle of a mesh's outermost face along a direction (the vertices that face it and lie furthest
## along it).
static func _face_center(mesh: Mesh, up: Vector3) -> Vector3:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var highest := -INF
	for v in vertices:
		highest = maxf(highest, v.dot(up))
	var sum := Vector3.ZERO
	var count := 0
	for i in vertices.size():
		if normals[i].dot(up) > 0.9 and vertices[i].dot(up) > highest - 0.05:
			sum += vertices[i]
			count += 1
	return sum / count if count > 0 else vertices[0]


func _follow_bones() -> void:
	for pair: Array in _skins:
		var mesh := pair[0] as MeshInstance3D
		if is_instance_valid(mesh):
			(pair[1] as ShaderMaterial).set_shader_parameter(&"to_rest", Projection(hitboxes.mesh_to_rest(mesh)))
