class_name MechHealth
extends Node
## HP of each mech part (Phase 4). Builds a hitbox for each part from the part models, takes the
## damage that hitboxes and blasts send, and tells PartBreaker and MechDeath what broke.
## Keys: "Head", "Torso C", "Torso L", "Torso R", "Arm L", "Arm R", "Groin", "Leg L", "Leg R",
## "Booster" (backpack), "Shield", "Back L", "Back R".
## The core part is split by position into center, left and right torso; the legs part into
## groin (pelvis) and the two legs. Hits on the held weapon count for the arm that holds it.
## The mech is alive while the head, the center torso, the groin and at least one leg are intact.

signal damaged(key: String, amount: float)
signal part_destroyed(key: String)
## The mech is dead. cause = the part whose loss killed it.
signal destroyed(cause: String)

@export var mech: Mech
@export var assembler: MechAssembler
@export var weapons: WeaponController

@export_group("Split")
## Core part HP given to the center torso and to each side torso.
@export var center_torso_share: float = 0.6
@export var side_torso_share: float = 0.4
## Core part meshes farther than this from the middle (meters, torso space) are side torso.
@export var side_torso_x: float = 0.9
## Legs part HP given to the groin and to each leg.
@export var groin_share: float = 0.4
@export var leg_share: float = 0.6

## Max and current HP by key.
var max_hp: Dictionary = {}
var hp: Dictionary = {}
var is_destroyed: bool = false
## Hitboxes by key.
var hitboxes: Dictionary = {}
## Model nodes of each key after the split (PartBreaker and MechDeath hide or drop them).
var segment_nodes: Dictionary = {}


func _ready() -> void:
	mech.health = self
	if mech.stats != null:
		var part_hp := mech.stats.part_hp
		for key in ["Head", "Arm L", "Arm R"]:
			if part_hp.has(key):
				max_hp[key] = part_hp[key]
		if part_hp.has("Core"):
			max_hp["Torso C"] = part_hp["Core"] * center_torso_share
			max_hp["Torso L"] = part_hp["Core"] * side_torso_share
			max_hp["Torso R"] = part_hp["Core"] * side_torso_share
		if part_hp.has("Legs"):
			max_hp["Groin"] = part_hp["Legs"] * groin_share
			max_hp["Leg L"] = part_hp["Legs"] * leg_share
			max_hp["Leg R"] = part_hp["Legs"] * leg_share
	var booster := assembler.loadout.booster if assembler != null and assembler.loadout != null else null
	if booster != null and booster.scene != null:
		max_hp["Booster"] = booster.hp
	if weapons != null:
		if weapons.left_data != null and not weapons.shield_nodes.is_empty():
			max_hp["Shield"] = weapons.left_data.hp
		if weapons.back_left != null:
			max_hp["Back L"] = weapons.back_left.data.hp
		if weapons.back_right != null:
			max_hp["Back R"] = weapons.back_right.data.hp
	hp = max_hp.duplicate()
	_split_segments()
	for key: String in segment_nodes:
		_add_hitboxes(key, segment_nodes[key])


## Adds a part with full HP. For a mech not built from parts (a rigged mech: SkeletalHitboxes).
func add_part(key: String, max_value: float) -> void:
	max_hp[key] = max_value
	hp[key] = max_value


## Adds a hitbox for a part (it is removed when the part is destroyed).
func add_hitbox(key: String, hitbox: PartHitbox) -> void:
	var list: Array = hitboxes.get(key, [])
	list.append(hitbox)
	hitboxes[key] = list


## Sends damage to a part. Parts with no HP left take no more damage.
func damage(key: String, amount: float) -> void:
	if is_destroyed or not hp.has(key) or hp[key] <= 0.0 or amount <= 0.0:
		return
	hp[key] = maxf(hp[key] - amount, 0.0)
	damaged.emit(key, amount)
	if hp[key] <= 0.0:
		_remove_hitboxes(key)
		var dies := not is_alive()
		if dies:
			is_destroyed = true
		part_destroyed.emit(key)
		if dies:
			destroyed.emit(key)


## Destroys a part with its effects (part_destroyed) even on a dead mech, with no death check.
func break_part(key: String) -> void:
	if not is_part_alive(key):
		return
	hp[key] = 0.0
	_remove_hitboxes(key)
	part_destroyed.emit(key)


## Takes a part away with no signals (it went with another part, for example the arm with its side
## torso).
func remove_part(key: String) -> void:
	if hp.has(key):
		hp[key] = 0.0
	_remove_hitboxes(key)


## Head, center torso, groin and at least one leg intact.
func is_alive() -> bool:
	for key in ["Head", "Torso C", "Groin"]:
		if hp.has(key) and hp[key] <= 0.0:
			return false
	if hp.has("Leg L") and hp.has("Leg R"):
		return hp["Leg L"] > 0.0 or hp["Leg R"] > 0.0
	return true


func is_part_alive(key: String) -> bool:
	return hp.get(key, 0.0) > 0.0


## 0 to 1.
func get_fraction(key: String) -> float:
	var top: float = max_hp.get(key, 0.0)
	return hp.get(key, 0.0) / top if top > 0.0 else 0.0


## Model nodes of a key.
func get_nodes(key: String) -> Array[Node3D]:
	# Freed nodes (debris that is gone) are skipped: a typed array cannot hold them.
	var nodes: Array[Node3D] = []
	for node: Variant in segment_nodes.get(key, []):
		if is_instance_valid(node):
			nodes.append(node as Node3D)
	return nodes


## RIDs of this mech's hitboxes (own weapons skip them).
func get_hitbox_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for key: String in hitboxes:
		for hitbox: Variant in hitboxes[key]:
			if is_instance_valid(hitbox):
				rids.append((hitbox as PartHitbox).get_rid())
	return rids


## Sorts the part nodes into the hit keys.
func _split_segments() -> void:
	if assembler == null:
		return
	for part_key: String in assembler.part_nodes:
		for node: Node3D in assembler.part_nodes[part_key]:
			_add_node(_segment_key(part_key, node), node)
	if weapons == null:
		return
	if hp.has("Shield"):
		for node in weapons.shield_nodes:
			_add_node("Shield", node)
	if weapons.right_weapon != null:
		_add_node("Arm R", weapons.right_weapon)
		# Weapon parts mounted on the forearm (the pile bunker).
		for child in weapons.arm_ik_right.mid_joint.get_children():
			if child is Node3D and _has_mesh(child) and not get_nodes("Arm R").has(child):
				_add_node("Arm R", child)
	if weapons.back_left != null:
		_add_node("Back L", weapons.back_left)
	if weapons.back_right != null:
		_add_node("Back R", weapons.back_right)


func _add_node(key: String, node: Node3D) -> void:
	var list: Array = segment_nodes.get(key, [])
	list.append(node)
	segment_nodes[key] = list


## Core parts (core, booster, generator, FCS) split by side; legs split by socket.
func _segment_key(part_key: String, node: Node3D) -> String:
	if part_key == "Booster":
		return "Booster"
	if part_key == "Core":
		if node.position.x < -side_torso_x:
			return "Torso L"
		if node.position.x > side_torso_x:
			return "Torso R"
		return "Torso C"
	if part_key == "Legs":
		var socket := String(node.get_parent().name)
		if socket in ["HipL", "KneeL"]:
			return "Leg L"
		if socket in ["HipR", "KneeR"]:
			return "Leg R"
		return "Groin"
	return part_key


## One box per container node (a node that holds meshes, like a pivot or a weapon), and one box
## per socket for the loose meshes.
func _add_hitboxes(key: String, nodes: Array) -> void:
	var loose := {}
	for node: Node3D in nodes:
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
