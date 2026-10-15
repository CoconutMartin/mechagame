class_name SkeletalPartBreaker
extends Node
## What happens to a rigged mech's part when it is damaged or destroyed (the PartBreaker rules for a
## mech with a skeleton). Below half HP a part smokes. Destroyed parts:
##   Head: explodes and falls off (the mech dies).
##   Arm: falls off with its weapon (right) or its shield (left). That weapon is lost.
##   Side torso: explodes, its shoulder and its arm fall off with the arm's weapon, and the back unit
##        on that side falls off.
##   Shield, back unit, Weapon R (the right arm weapon: gun or pile bunker): falls off, the arm stays.
##   Leg: explodes and smokes. One leg left: walks 60% slower; boost speed stays.
##   Center torso, groin: explode (the mech dies).
## Falling parts are the skinned meshes frozen at their pose now, in rigid debris.

@export var mech: Mech
@export var health: MechHealth
@export var hitboxes: SkeletalHitboxes
## The mech's weapons (a destroyed arm or side torso loses its weapons).
@export var weapons: WeaponController
@export var camera_shake: CameraShake
## Part HP fraction where smoke starts.
@export_range(0.0, 1.0) var smoke_below: float = 0.5
## Smoke opacity when it starts (at smoke_below), and the HP fraction where it is fully solid
## (user request 2026-10-15: an almost broken part smokes with no transparency).
@export_range(0.0, 1.0) var smoke_start_opacity: float = 0.5
@export_range(0.0, 1.0) var smoke_solid_below: float = 0.1
## One leg destroyed: walk speed x this value.
@export var one_leg_speed_scale: float = 0.4
## Kick of a falling part, m/s (sideways and up).
@export var drop_push: float = 5.0

var _smoking: Dictionary = {}


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.part_destroyed.connect(_on_part_destroyed)


func _on_damaged(key: String, _amount: float) -> void:
	if not health.is_part_alive(key):
		return
	var fraction := health.get_fraction(key)
	if _smoking.has(key):
		var smoke := _smoking[key] as DamageSmoke if is_instance_valid(_smoking[key]) else null
		if smoke != null:
			smoke.set_opacity(_smoke_opacity(fraction))
		return
	if fraction >= smoke_below:
		return
	var place := _part_place(key)
	if not place.is_empty():
		var smoke := DamageSmoke.create(place[0], place[1])
		smoke.set_opacity(_smoke_opacity(fraction))
		_smoking[key] = smoke


## Smoke opacity for a part HP fraction: smoke_start_opacity at smoke_below, solid at smoke_solid_below.
func _smoke_opacity(fraction: float) -> float:
	var t := inverse_lerp(smoke_below, smoke_solid_below, fraction)
	return lerpf(smoke_start_opacity, 1.0, clampf(t, 0.0, 1.0))


func _on_part_destroyed(key: String) -> void:
	if camera_shake != null:
		camera_shake.add_shake(0.25, 0.3)
	var center := get_center(key)
	match key:
		"Head":
			PartBreaker.explode_in(_world(), center, 3.0)
			_drop(key, Vector3.UP)
		"Arm L", "Arm R":
			PartBreaker.explode_in(_world(), center, 2.0)
			_break_arm(key)
		"Torso L", "Torso R":
			PartBreaker.explode_in(_world(), center, 7.0)
			_heavy_smoke(key)
			_drop(key, _side_out(key))
			var arm := "Arm L" if key == "Torso L" else "Arm R"
			if health.is_part_alive(arm):
				health.remove_part(arm)
				_break_arm(arm)
			_break_back("Back L" if key == "Torso L" else "Back R")
		"Shield":
			PartBreaker.explode_in(_world(), center, 2.0)
			var nodes := weapons.shield_nodes.duplicate()
			weapons.lose_shield()
			_drop_nodes(nodes, -mech.global_basis.x)
		"Back L", "Back R":
			PartBreaker.explode_in(_world(), center, 3.0)
			_break_back(key)
		"Weapon R":
			PartBreaker.explode_in(_world(), center, 2.0)
			var nodes := weapons.right_weapon_nodes()
			weapons.lose_right_weapon()
			_drop_nodes(nodes, mech.global_basis.x - mech.global_basis.z)
		"Leg L", "Leg R":
			PartBreaker.explode_in(_world(), center, 3.0)
			_heavy_smoke(key)
			if health.is_alive():
				mech.one_leg = true
				mech.broken_leg_side = -1.0 if key == "Leg L" else 1.0
				mech.walk_speed *= one_leg_speed_scale
				mech.boost_speed_multiplier /= one_leg_speed_scale
		_:
			PartBreaker.explode_in(_world(), center, 7.0)


## An arm falls off with what it holds: the right arm with its weapon, the left arm with its shield
## (a two-hand weapon stays in the right hand alone).
func _break_arm(key: String) -> void:
	_drop(key, _side_out(key))
	if weapons == null:
		return
	var nodes: Array[Node3D] = []
	if key == "Arm L":
		nodes = weapons.shield_nodes.duplicate()
		if health.is_part_alive("Shield"):
			health.remove_part("Shield")
		weapons.lose_left_arm()
	else:
		nodes = weapons.right_weapon_nodes()
		if health.is_part_alive("Weapon R"):
			health.remove_part("Weapon R")
		weapons.lose_right_weapon()
	_drop_nodes(nodes, _side_out(key))


## A back unit falls off.
func _break_back(key: String) -> void:
	if weapons == null:
		return
	var pod := weapons.back_left if key == "Back L" else weapons.back_right
	if pod == null:
		return
	if health.is_part_alive(key):
		health.remove_part(key)
	weapons.lose_back_weapon(pod)
	_drop_nodes([pod] as Array[Node3D], Vector3.UP - mech.global_basis.z)


## Weapon models (not skinned) fall off in debris.
func _drop_nodes(nodes: Array[Node3D], away: Vector3) -> void:
	var unique: Array[Node3D] = []
	for node in nodes:
		if is_instance_valid(node) and not unique.has(node):
			unique.append(node)
	if not unique.is_empty():
		Debris.drop(unique, _world(), mech.velocity + (away.normalized() + Vector3.UP * 0.8) * drop_push)


## Middle of a part's meshes now (world). A weapon part: the middle of its nodes.
func get_center(key: String) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for node in health.get_nodes(key):
		sum += node.global_position
		count += 1
	for mesh: MeshInstance3D in hitboxes.part_meshes.get(key, []):
		if not is_instance_valid(mesh):
			continue
		var local := (mesh.transform * mesh.get_aabb()).get_center()
		if hitboxes.skeleton.is_ancestor_of(mesh):
			sum += _posed(mesh) * (mesh.transform.affine_inverse() * local)
		else:
			sum += mesh.global_position
		count += 1
	return sum / count if count > 0 else mech.global_position + Vector3.UP * 7.0


## The part's meshes fall off: each becomes a plain (not skinned) mesh at its pose now, in debris.
func _drop(key: String, away: Vector3) -> void:
	var nodes: Array[Node3D] = []
	for mesh: MeshInstance3D in hitboxes.part_meshes.get(key, []):
		if not is_instance_valid(mesh) or not hitboxes.skeleton.is_ancestor_of(mesh):
			continue
		var posed := _posed(mesh)
		mesh.skin = null
		mesh.skeleton = NodePath()
		mesh.global_transform = posed
		nodes.append(mesh)
	var push := mech.velocity + (away.normalized() + Vector3.UP * 0.8) * drop_push
	Debris.drop(nodes, _world(), push)


## World transform that shows a mesh skinned to one bone at the bone's pose now.
func _posed(mesh: MeshInstance3D) -> Transform3D:
	var skeleton := hitboxes.skeleton
	var bone: int = hitboxes.mesh_bones[mesh]
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) \
			* skeleton.get_bone_global_rest(bone).affine_inverse() * mesh.transform


func _heavy_smoke(key: String) -> void:
	var place := _part_place(key)
	if not place.is_empty():
		DamageSmoke.create(place[0], place[1], true)


## Where a part's smoke goes: [parent, offset] from its first hitbox (it follows the bone). A
## destroyed part has no hitboxes left: the middle of its meshes, on the bone of its first mesh.
func _part_place(key: String) -> Array:
	for hitbox in health.hitboxes.get(key, []):
		if is_instance_valid(hitbox) and hitbox.get_child_count() > 0:
			return [hitbox.get_parent(), hitbox.position + (hitbox.get_child(0) as Node3D).position]
	var meshes: Array = hitboxes.part_meshes.get(key, [])
	if meshes.is_empty() or not is_instance_valid(meshes[0]):
		return []
	var holder := hitboxes.get_attachment(hitboxes.mesh_bones[meshes[0]])
	return [holder, holder.to_local(get_center(key))]


func _side_out(key: String) -> Vector3:
	return -mech.global_basis.x if key.ends_with("L") else mech.global_basis.x


func _world() -> Node:
	return get_tree().current_scene if get_tree().current_scene != null else mech.get_parent()
