class_name CharDamageLook
extends Node
## Damage look of the new (rigged) mech: each part gets a charred, lumpy black crust that grows with
## its damage and covers the part fully near 1 HP (user reference, 2026-10-11). Weapons are parts too
## (Weapon R, Shield, Back L/R). The crust is a material overlay (shaders/char_damage.gdshader).
## Skinned part meshes move with their bone; each frame the overlay gets the bone's pose-to-rest
## transform, so the crust stays fixed on the part.

const SHADER := preload("res://shaders/char_damage.gdshader")

@export var health: MechHealth
@export var hitboxes: SkeletalHitboxes
## Optional. Its weapon parts get the crust too.
@export var weapons: WeaponController
## Damage (1 - HP fraction) where the crust starts to show, and where it covers the whole part.
@export_range(0.0, 1.0) var start_damage: float = 0.1
@export_range(0.0, 1.0) var full_damage: float = 0.998
## Meshes with fewer vertices than this (the joint balls, weapon boxes: hard edges) get the crust
## with no lumps.
@export var min_lump_vertices: int = 5000

## Crust materials by hit key: [MeshInstance3D, ShaderMaterial] pairs.
var _layers: Dictionary = {}

## One crust material made at load (lag spike fix 2026-10-18): it makes the renderer compile the crust
## shader then. Before, the first crust of a game compiled it in the frame of the hit (about 120 ms on
## Forward+ when a War Hammer hit broke a part). The shader stays while this material lives.
static var _warm: ShaderMaterial


func _ready() -> void:
	if _warm == null:
		_warm = ShaderMaterial.new()
		_warm.shader = SHADER
	health.damaged.connect(_on_damaged)
	health.part_reset.connect(_on_part_reset)
	hitboxes.skeleton.skeleton_updated.connect(_follow_bones)


## The crust amount for a part's damage now (0 to 1).
func amount_for(key: String) -> float:
	var damage := 1.0 - health.get_fraction(key)
	if not health.is_part_alive(key):
		damage = 1.0
	return clampf(inverse_lerp(start_damage, full_damage, damage), 0.0, 1.0)


func _on_damaged(key: String, _amount: float) -> void:
	var value := amount_for(key)
	if value <= 0.0:
		return
	if not _layers.has(key):
		_layers[key] = _make_layers(key)
	for pair: Array in _layers[key]:
		(pair[1] as ShaderMaterial).set_shader_parameter(&"amount", value)


## A weapon left the hand or came into it (its HP part was taken off or put on): the old crust layers are
## forgotten (a dropped weapon keeps the crust it has), and a part with damage gets its crust on the new meshes.
func _on_part_reset(key: String) -> void:
	_layers.erase(key)
	if health.hp.has(key):
		_on_damaged(key, 0.0)


func _make_layers(key: String) -> Array:
	var layers := []
	for mesh in _meshes(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		var vertices := 0
		if mesh.mesh is ArrayMesh:
			for surface in mesh.mesh.get_surface_count():
				vertices += (mesh.mesh as ArrayMesh).surface_get_array_len(surface)
		# Primitive meshes (boxes, cylinders) have hard edges too.
		if vertices < min_lump_vertices:
			material.set_shader_parameter(&"push", 0.0)
		mesh.material_overlay = material
		layers.append([mesh, material])
	return layers


## The meshes of a part: the skinned body meshes, or the weapon model meshes.
func _meshes(key: String) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in hitboxes.part_meshes.get(key, []):
		if is_instance_valid(mesh):
			found.append(mesh)
	if not found.is_empty() or weapons == null:
		return found
	var roots: Array[Node3D] = []
	match key:
		"Weapon R":
			roots = weapons.right_weapon_nodes()
		"Weapon L":
			roots = weapons.left_weapon_nodes()
		"Shield":
			roots = weapons.shield_nodes
		"Back L":
			if weapons.back_left != null:
				roots = [weapons.back_left]
		"Back R":
			if weapons.back_right != null:
				roots = [weapons.back_right]
	for root in roots:
		if not is_instance_valid(root):
			continue
		if root is MeshInstance3D:
			found.append(root)
		for node in root.find_children("*", "MeshInstance3D", true, false):
			found.append(node as MeshInstance3D)
	return found


## Skinned meshes: rest position = rest x pose inverse (skeleton space) x skinned position. Called
## when the skeleton has its final pose of the frame. A mesh that fell off (no skin) is at rest.
func _follow_bones() -> void:
	for key: String in _layers:
		for pair: Array in _layers[key]:
			# Check before the cast: casting a freed mesh (a part that broke off) is an error.
			if not is_instance_valid(pair[0]) or not hitboxes.mesh_bones.has(pair[0]):
				continue
			var mesh := pair[0] as MeshInstance3D
			(pair[1] as ShaderMaterial).set_shader_parameter(&"to_rest", Projection(hitboxes.mesh_to_rest(mesh)))
