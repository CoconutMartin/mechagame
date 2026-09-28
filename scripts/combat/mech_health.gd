class_name MechHealth
extends Node
## HP of each mech part (Phase 4). Builds a hitbox for each part from the part models, takes the
## damage that hitboxes and blasts send, and tells PartBreaker when a part is destroyed.
## Keys: "Head", "Core", "Arm L", "Arm R", "Legs", "Shield", "Back L", "Back R".
## Hits on the held weapon count for the arm that holds it. Core destroyed = mech destroyed.

signal damaged(key: String, amount: float)
signal part_destroyed(key: String)
signal destroyed

@export var mech: Mech
@export var assembler: MechAssembler
@export var weapons: WeaponController

## Max and current HP by key.
var max_hp: Dictionary = {}
var hp: Dictionary = {}
var is_destroyed: bool = false
## Hitboxes by key.
var hitboxes: Dictionary = {}


func _ready() -> void:
	mech.health = self
	if mech.stats != null:
		for key: String in mech.stats.part_hp:
			max_hp[key] = mech.stats.part_hp[key]
	if weapons != null:
		if weapons.left_data != null and not weapons.shield_nodes.is_empty():
			max_hp["Shield"] = weapons.left_data.hp
		if weapons.back_left != null:
			max_hp["Back L"] = weapons.back_left.data.hp
		if weapons.back_right != null:
			max_hp["Back R"] = weapons.back_right.data.hp
	hp = max_hp.duplicate()
	_build_hitboxes()


## Sends damage to a part. Parts with no HP left take no more damage.
func damage(key: String, amount: float) -> void:
	if is_destroyed or not hp.has(key) or hp[key] <= 0.0 or amount <= 0.0:
		return
	hp[key] = maxf(hp[key] - amount, 0.0)
	damaged.emit(key, amount)
	if hp[key] <= 0.0:
		_remove_hitboxes(key)
		part_destroyed.emit(key)
		if key == "Core":
			is_destroyed = true
			destroyed.emit()


## Takes a part away with no signals (it went with another part, for example the shield with the
## left arm).
func remove_part(key: String) -> void:
	hp[key] = 0.0
	_remove_hitboxes(key)


func is_part_alive(key: String) -> bool:
	return hp.get(key, 0.0) > 0.0


## 0 to 1.
func get_fraction(key: String) -> float:
	var top: float = max_hp.get(key, 0.0)
	return hp.get(key, 0.0) / top if top > 0.0 else 0.0


## RIDs of this mech's hitboxes (own weapons skip them).
func get_hitbox_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for key: String in hitboxes:
		for hitbox: PartHitbox in hitboxes[key]:
			if is_instance_valid(hitbox):
				rids.append(hitbox.get_rid())
	return rids


func _build_hitboxes() -> void:
	for key: String in assembler.part_nodes:
		_add_hitboxes(key, assembler.part_nodes[key])
	if weapons == null:
		return
	if hp.has("Shield"):
		_add_hitboxes("Shield", weapons.shield_nodes)
	if weapons.right_weapon != null:
		_add_hitboxes("Arm R", [weapons.right_weapon] as Array[Node3D])
		# Weapon parts mounted on the forearm (the pile bunker).
		var forearm := weapons.arm_ik_right.mid_joint
		for child in forearm.get_children():
			if child is Node3D and _has_mesh(child) and not assembler.part_nodes.get("Arm R", []).has(child):
				_add_hitboxes("Arm R", [child] as Array[Node3D])
	if weapons.back_left != null:
		_add_hitboxes("Back L", [weapons.back_left] as Array[Node3D])
	if weapons.back_right != null:
		_add_hitboxes("Back R", [weapons.back_right] as Array[Node3D])


## One box per container node (a node that holds meshes, like a pivot or a weapon), and one box
## per socket for the loose meshes of the part.
func _add_hitboxes(key: String, nodes: Array[Node3D]) -> void:
	var loose := {}
	for node in nodes:
		if node is MeshInstance3D:
			var socket := node.get_parent_node_3d()
			var list: Array = loose.get(socket, [])
			list.append(node)
			loose[socket] = list
		elif _has_mesh(node):
			_add_box(key, node, [node])
	for socket: Node3D in loose:
		_add_box(key, socket, loose[socket])


func _add_box(key: String, parent: Node3D, roots: Array) -> void:
	var bounds := AABB()
	var first := true
	var to_parent := parent.global_transform.affine_inverse()
	for root: Node3D in roots:
		for mesh in _meshes(root):
			var box := (to_parent * mesh.global_transform) * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	if first:
		return
	var list: Array = hitboxes.get(key, [])
	list.append(PartHitbox.create(parent, key, bounds, self))
	hitboxes[key] = list


func _remove_hitboxes(key: String) -> void:
	for hitbox in hitboxes.get(key, []):
		if is_instance_valid(hitbox):
			hitbox.queue_free()
	hitboxes.erase(key)


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D and root.visible:
		found.append(root)
	for child in root.get_children():
		# Flames and effects are not armor.
		if child is MeshInstance3D and (child.is_in_group(&"booster_flame") or child.cast_shadow == 0):
			continue
		if child.is_in_group(&"booster_flame") or child.is_in_group(&"brake_flame"):
			continue
		found.append_array(_meshes(child))
	return found


static func _has_mesh(root: Node) -> bool:
	return not _meshes(root).is_empty()
