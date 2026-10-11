class_name PS1SkinLook
extends Node
## PS1-style skin of the rigged mech (user request 2026-10-11): every body mesh keeps its own colors
## (the model's albedo texture and color) and gets shaders/ps1_skin.gdshader: chunky pixels, a pixel
## detail texture (seams, rivets, vents, dirt on the armor; rings on the joints and hands), 15-bit
## color with a dither, and a light vertex wobble. The detail sits on the part's rest position
## (to_rest each frame, like CharDamageLook), so it stays on the part.

const SHADER := preload("res://shaders/ps1_skin.gdshader")
const ARMOR_TEXTURE := preload("res://assets/textures/ps1/metal_panels.png")
const JOINT_TEXTURE := preload("res://assets/textures/ps1/joint_metal.png")

@export var hitboxes: SkeletalHitboxes
## Chunky pixels across the whole model texture (smaller = bigger pixels).
@export var uv_pixels: float = 256.0
## Detail texture pixels per meter, and how strong it shows (0 = off).
@export var texels_per_meter: float = 16.0
@export_range(0.0, 2.0) var detail_strength: float = 0.8
## Color scale: the skin has no metal shine, so it is scaled to the brightness of the model's own
## (metallic) material.
@export var brightness: float = 0.75
## Color steps per channel (32 = PS1 15-bit color).
@export var color_steps: float = 32.0
## Screen grid of the vertex snap (the PS1 wobble); (0, 0) = no snap.
@export var snap_grid: Vector2 = Vector2(640.0, 480.0)

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
	var original := mesh.get_active_material(0) as BaseMaterial3D
	var texture: Texture2D = original.albedo_texture if original != null else null
	material.set_shader_parameter(&"albedo_color", original.albedo_color if original != null else Color.WHITE)
	material.set_shader_parameter(&"use_albedo_texture", texture != null)
	material.set_shader_parameter(&"brightness", brightness)
	if texture != null:
		material.set_shader_parameter(&"albedo_texture", texture)
	var joint := String(mesh.name).to_lower().contains("joint") or bone_name.begins_with("hand")
	var detail: Texture2D = JOINT_TEXTURE if joint else ARMOR_TEXTURE
	material.set_shader_parameter(&"grey_texture", detail)
	material.set_shader_parameter(&"texture_size", float(detail.get_width()))
	material.set_shader_parameter(&"texels_per_meter", texels_per_meter)
	material.set_shader_parameter(&"detail_strength", detail_strength)
	material.set_shader_parameter(&"uv_pixels", uv_pixels)
	material.set_shader_parameter(&"uv_offset", Vector2(0.37 * index, 0.61 * index))
	material.set_shader_parameter(&"color_steps", color_steps)
	material.set_shader_parameter(&"snap_grid", snap_grid)
	return material


func _follow_bones() -> void:
	for pair: Array in _skins:
		var mesh := pair[0] as MeshInstance3D
		if is_instance_valid(mesh):
			(pair[1] as ShaderMaterial).set_shader_parameter(&"to_rest", Projection(hitboxes.mesh_to_rest(mesh)))
